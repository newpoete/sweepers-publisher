# frozen_string_literal: true

require 'date'
require_relative 'bluesky'
require_relative 'http'
require_relative 'post'

module Sweepers
  # Posts today's leaf from the live site to Bluesky, at most once a day
  # (sweepers-editor#127). It reads only what the site already serves
  # (release.json, then leaves/<day_of_year>.json), so it never needs the
  # queue's key, and it posts nothing unless all of these hold:
  #
  # - the live release is for today (UTC), so a late release posts nothing;
  # - today has a leaf;
  # - the account has no post of its own dated today (deleting that post lets a
  #   re-run post again).
  class DailyPost
    SITE = 'https://sweeperscalendar.com'
    # The link card's image: the woodcut from both accounts' avatars
    # (sweepers-editor docs/social/newpoete-avatar.jpg, 400×400, 26 KB).
    CARD_IMAGE = File.expand_path('../../data/bluesky-card.jpg', __dir__)
    CARD_IMAGE_TYPE = 'image/jpeg'

    # status: :posted, :would_post (a dry run) or :skipped. post: the
    # Sweepers::Post, when there's a leaf. url: the post's bsky.app address,
    # when one exists.
    Result = Data.define(:status, :message, :post, :url)

    def initialize(bluesky, http: HTTP.new, site: SITE, card_image: CARD_IMAGE)
      @bluesky = bluesky
      @http = http
      @site = site
      @card_image = card_image
    end

    # today: the UTC date. dry_run: build and check everything, sign in and
    # write nothing. app_password: needed only to post.
    def run(today:, dry_run:, app_password: nil)
      release = @http.get_json("#{@site}/release.json")
      date = Date.iso8601(release.fetch('date'))
      return skipped("The live release is for #{date}, not today (#{today}), so there's nothing to post yet.") if date != today

      day = release.fetch('day_of_year')
      leaf = @http.get_json("#{@site}/leaves/#{day}.json", not_found: :nil)
      return skipped("Today (#{date}, day #{day}) has no leaf, so there's nothing to post.") unless leaf

      post = Post.from_leaf(leaf.fetch('html'), date: date)
      existing = @bluesky.posts_on(today).first
      return skipped("@#{@bluesky.handle} already posted today.", post: post, url: url_of(existing['uri'])) if existing
      return Result.new(:would_post, "Dry run: would post day #{day} as @#{@bluesky.handle}.", post, nil) if dry_run

      publish(post, day, app_password)
    end

    private

    def publish(post, day, app_password)
      raise Bluesky::Error, 'no app password given' if app_password.to_s.empty?

      @bluesky.login(app_password)
      thumb = @bluesky.upload_blob(File.binread(@card_image), CARD_IMAGE_TYPE)
      created = @bluesky.create_post(post.record(thumb: thumb))
      Result.new(:posted, "Posted day #{day} as @#{@bluesky.handle}.", post, url_of(created.fetch('uri')))
    end

    def skipped(message, post: nil, url: nil)
      Result.new(:skipped, message, post, url)
    end

    def url_of(uri)
      Bluesky.web_url(@bluesky.handle, uri)
    end
  end
end
