# frozen_string_literal: true

require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'time'
require_relative 'calendar'

module Sweepers
  # Turns the decrypted queue into the site's data for one release date.
  #
  # Only leaves due on or before the release date (UTC) are written anywhere.
  # See docs/data-contract.md for every file this produces.
  class Release
    class InvalidLeaf < StandardError; end

    LEAF_VERSION = 1
    SELECTION_DAYS = 90
    SELECTION_LIMIT = 7
    SELECTION_MIN_SCORE = 8
    SNIPPET_LENGTH = 300
    DEFAULT_BASE_URL = 'https://newpoete.github.io/sweepers-publisher'

    Leaf = Struct.new(:aphorism_id, :draft_id, :year, :day_of_year, :html, :snippet, :score,
                      :published_at, keyword_init: true) do
      def date
        Calendar.leaf_date(year, day_of_year)
      end
    end

    # A current selection: the leaf, and the date it's listed under (the most
    # recent occurrence of its day of year before the release date).
    Selection = Struct.new(:leaf, :date, :days_ago, keyword_init: true)

    attr_reader :date, :base_url

    # leaves: the decrypted queue, an array of leaf hashes (see Sweepers::Queue).
    def initialize(leaves, date:, base_url: DEFAULT_BASE_URL)
      @date = date
      @base_url = base_url.chomp('/')
      @leaves = leaves.map { |raw| parse_leaf(raw) }
    end

    # Leaves due by the release date: the only ones that may leave this class.
    def due_leaves
      @due_leaves ||= @leaves.select { |leaf| leaf.date <= date }
    end

    # The newest due leaf for each day of year, as Flask's Leaf.by_day_of_year
    # chose it: the latest year, then the latest publish. A day keeps showing
    # an old year's leaf indefinitely until a newer one is published and due.
    def leaves_by_day
      @leaves_by_day ||= due_leaves.group_by(&:day_of_year).transform_values do |leaves|
        leaves.max_by { |leaf| [leaf.year, leaf.published_at] }
      end
    end

    # Flask's Leaf.selections. For each of the 90 days before the release date
    # (today excluded), take that day of year's current leaf, from any year,
    # as Flask's day-of-year window did. Keep scores of 8 or more, then the 7
    # best by score (newer first on ties), listed newest first.
    def selections
      @selections ||= begin
        recent = (1..SELECTION_DAYS).filter_map do |days_ago|
          day = date - days_ago
          leaf = leaves_by_day[Calendar.day_of_year(day)]
          Selection.new(leaf: leaf, date: day, days_ago: days_ago) if leaf && leaf.score.to_i >= SELECTION_MIN_SCORE
        end
        best = recent.sort_by { |s| [-s.leaf.score, s.days_ago] }.first(SELECTION_LIMIT)
        best.sort_by(&:days_ago)
      end
    end

    # Every released file, as { relative path => content }.
    def files
      files = {
        'release.json' => json(release_record),
        'selections.json' => json(selections.map { |selection| selection_record(selection) })
      }
      leaves_by_day.each_value do |leaf|
        files["leaves/#{leaf.day_of_year}.json"] = json(leaf_record(leaf))
      end
      files['sitemap.txt'] = sitemap
      files
    end

    # Writes the site: the static shell from site_dir, the static data files,
    # then the released files. out_dir must not exist yet, so that a failed
    # release never leaves a half-written site behind.
    def write(out_dir, site_dir:, data_dir:)
      raise ArgumentError, "#{out_dir} already exists" if File.exist?(out_dir)

      staging = "#{out_dir}.partial"
      FileUtils.rm_rf(staging)
      FileUtils.mkdir_p(staging)
      FileUtils.cp_r(File.join(site_dir, '.'), staging) if Dir.exist?(site_dir)
      FileUtils.cp(File.join(data_dir, 'mountweazel.json'), staging)
      files.each do |path, content|
        target = File.join(staging, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, content)
      end
      selection_shell = File.join(site_dir, 'selection.html')
      selections.each do |selection|
        FileUtils.mkdir_p(File.join(staging, 'selection'))
        FileUtils.cp(selection_shell, File.join(staging, 'selection', "#{selection.leaf.day_of_year}.html"))
      end
      File.rename(staging, out_dir)
    end

    # Jinja2 2.8's striptags + truncate(300), as used by Flask's selections page:
    # tags removed, entities decoded, whitespace collapsed, then cut at a word
    # boundary, then " ..." appended (Jinja 2.8 adds the space; the live site
    # shows "would not trail ...").
    def self.snippet(html, length = SNIPPET_LENGTH)
      text = CGI.unescapeHTML(html.gsub(/<!--.*?-->|<[^>]*>/m, '')).split.join(' ')
      return text if text.length <= length

      cut = text[0, length - 3]
      cut = cut.rpartition(' ').first if cut.include?(' ')
      "#{cut} ..."
    end

    private

    def release_record
      yesterday = date - 1
      {
        date: date.iso8601,
        day_of_year: Calendar.day_of_year(date),
        yesterday: { date: yesterday.iso8601, day_of_year: Calendar.day_of_year(yesterday) },
        released_at: Time.now.utc.iso8601
      }
    end

    # Pages show a leaf under the release's date, whatever year it was
    # published for (as Flask did with the current year), so no year is released.
    def leaf_record(leaf)
      { day_of_year: leaf.day_of_year, html: leaf.html }
    end

    def selection_record(selection)
      leaf = selection.leaf
      {
        day_of_year: leaf.day_of_year,
        date: selection.date.iso8601,
        snippet: leaf.snippet.to_s.strip.empty? ? self.class.snippet(leaf.html) : leaf.snippet
      }
    end

    def sitemap
      paths = %w[today yesterday selections] + selections.map { |s| "selection/#{s.leaf.day_of_year}" }
      paths.map { |path| "#{base_url}/#{path}\n" }.join
    end

    def json(data)
      "#{JSON.pretty_generate(data)}\n"
    end

    def parse_leaf(raw)
      where = raw['source'] || 'leaf'
      raise InvalidLeaf, "#{where}: unsupported version #{raw['version'].inspect}" unless raw['version'] == LEAF_VERSION

      int = ->(key) { raw[key].is_a?(Integer) ? raw[key] : raise(InvalidLeaf, "#{where}: #{key} must be an integer") }
      day = int.call('day_of_year')
      raise InvalidLeaf, "#{where}: day_of_year #{day} is outside 1-366" unless (1..366).cover?(day)
      raise InvalidLeaf, "#{where}: html must be a non-empty string" unless raw['html'].is_a?(String) && !raw['html'].empty?
      raise InvalidLeaf, "#{where}: score must be an integer or null" unless raw['score'].nil? || raw['score'].is_a?(Integer)

      Leaf.new(aphorism_id: int.call('aphorism_id'), draft_id: int.call('draft_id'), year: int.call('year'),
               day_of_year: day, html: raw['html'], snippet: raw['snippet'], score: raw['score'],
               published_at: Time.iso8601(raw.fetch('published_at')))
    rescue KeyError, ArgumentError => e
      raise InvalidLeaf, "#{where}: #{e.message}"
    end
  end
end
