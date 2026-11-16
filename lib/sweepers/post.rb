# frozen_string_literal: true

require 'cgi'
require 'date'

module Sweepers
  # The calendar's daily Bluesky post, built from a released leaf (sweepers-editor#126).
  #
  # The post's text is only the aphorism, as plain text: no date and no link. The
  # link is a card (an app.bsky.embed.external embed), which sits in its own field
  # of the post record and doesn't count toward the 300-grapheme limit. The card
  # links the home page and is described by the entry's date, as the site's leaf
  # heading writes it ("Monday, 16 November 2026").
  #
  # A leaf too long for one post is cut at the last word break that fits, and ends
  # with "…". Pure code: no network, no secrets. Signing in, uploading the card's
  # image and setting createdAt belong to the client (sweepers-editor#127).
  class Post
    MAX_GRAPHEMES = 300 # Bluesky's limit on a post's text
    MAX_BYTES = 3000 # ...and on its UTF-8 size, which 300 graphemes rarely reach
    ELLIPSIS = '…'
    LANGS = ['en'].freeze

    CARD_URI = 'https://sweeperscalendar.com'
    CARD_TITLE = 'The Sweepers Calendar'
    # The card's description: the entry's date, as the site's heading writes it
    # (calendar.js: weekday, day without a leading zero, month, year). Ruby's
    # strftime names days and months in English whatever the locale.
    CARD_DATE_FORMAT = '%A, %-d %B %Y'

    # Named entities CGI.unescapeHTML leaves alone, which a leaf may use.
    ENTITIES = {
      '&nbsp;' => ' ', '&mdash;' => '—', '&ndash;' => '–', '&hellip;' => '…',
      '&lsquo;' => '‘', '&rsquo;' => '’', '&ldquo;' => '“', '&rdquo;' => '”'
    }.freeze

    attr_reader :text, :date

    # Whether the leaf was too long for one post and had to be cut.
    def cut? = @cut

    # html: the leaf's HTML (leaves/<day_of_year>.json). date: the entry's date,
    # the release date in release.json.
    def self.from_leaf(html, date:)
      full = plain_text(html)
      text = fit(full)
      new(text, date: date, cut: text != full)
    end

    def initialize(text, date:, cut: false)
      @text = text
      @date = date
      @cut = cut
    end

    # The leaf's HTML as plain text. Paragraphs are separated by a blank line and
    # <br> by a line break; tags are dropped, entities decoded, and runs of spaces
    # within a line collapsed (leaves often have two spaces after a full stop).
    def self.plain_text(html)
      text = html.gsub(/<!--.*?-->/m, '')
                 .gsub(%r{</p\s*>\s*<p\b[^>]*>}i, "\n\n")
                 .gsub(%r{<br\s*/?>}i, "\n")
                 .gsub(/<[^>]*>/, '')
      text = CGI.unescapeHTML(text.gsub(/&[a-z]+;/) { |entity| ENTITIES.fetch(entity, entity) })
      text.split("\n").map { |line| line.tr(" ", ' ').split.join(' ') }.join("\n")
          .gsub(/\n{3,}/, "\n\n").strip
    end

    # The text as is if it fits in a post. Otherwise, cut at the last word break
    # that leaves room for the ellipsis, with trailing spaces and joining
    # punctuation (, ; : and dashes) dropped. A single word too long to fit is
    # cut mid-word, which no real leaf does.
    def self.fit(text)
      return text if fits?(text)

      graphemes = text.grapheme_clusters
      room = MAX_GRAPHEMES - 1
      room -= 1 until fits?(graphemes.first(room).join + ELLIPSIS)
      head = graphemes.first(room).join
      head = head[/\A.*\s/m] || head unless graphemes[room].to_s.match?(/\A\s/)
      "#{head.sub(/[\s,;:\-–—]+\z/, '')}#{ELLIPSIS}"
    end

    def self.fits?(text)
      text.grapheme_clusters.size <= MAX_GRAPHEMES && text.bytesize <= MAX_BYTES
    end

    def card_description
      date.strftime(CARD_DATE_FORMAT)
    end

    # The post record's fields, less what only the client knows: createdAt, and
    # the card's image (thumb), which must be uploaded first. Pass the uploaded
    # blob as thumb to include it.
    def record(thumb: nil)
      external = { 'uri' => CARD_URI, 'title' => CARD_TITLE, 'description' => card_description }
      external['thumb'] = thumb if thumb
      {
        '$type' => 'app.bsky.feed.post',
        'text' => text,
        'langs' => LANGS,
        'embed' => { '$type' => 'app.bsky.embed.external', 'external' => external }
      }
    end
  end
end
