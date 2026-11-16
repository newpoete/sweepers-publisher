# frozen_string_literal: true

require 'date'
require 'time'
require_relative 'http'

module Sweepers
  # Just enough of Bluesky's API (AT Protocol XRPC) to post as one account
  # (sweepers-editor#127). Reads go to the public AppView and need no login;
  # writes go through the account's PDS (via the bsky.social entryway) and need a
  # session from an app password, never the account password.
  #
  # The app password is used once, to sign in, and never kept. The session's
  # token is kept only for the writes, and inspect hides it.
  class Bluesky
    class Error < StandardError; end

    ENTRYWAY = 'https://bsky.social/xrpc'
    APPVIEW = 'https://public.api.bsky.app/xrpc'
    FEED_LIMIT = 10 # a re-run only needs to see today's post, the newest

    attr_reader :handle

    def initialize(handle, http: HTTP.new)
      @handle = handle
      @http = http
      @session = nil
    end

    # The account's DID, from its handle (public, no login).
    def did
      @did ||= @session&.fetch('did') ||
               @http.get_json("#{APPVIEW}/com.atproto.identity.resolveHandle", { handle: handle }).fetch('did')
    end

    # The account's own posts on a UTC date, newest first (public, no login).
    # Reposts and replies are left out, so only a post this account made counts.
    def posts_on(date)
      feed = @http.get_json("#{APPVIEW}/app.bsky.feed.getAuthorFeed",
                            { actor: did, filter: 'posts_no_replies', limit: FEED_LIMIT })
      feed.fetch('feed').filter_map do |item|
        post = item.fetch('post')
        next if item['reason'] || post.dig('author', 'did') != did

        post if Time.iso8601(post.dig('record', 'createdAt')).utc.to_date == date
      end
    end

    # Signs in with an app password. Returns the session's DID and handle.
    def login(app_password)
      @session = @http.post_json("#{ENTRYWAY}/com.atproto.server.createSession",
                                 { identifier: handle, password: app_password })
      { 'did' => @session.fetch('did'), 'handle' => @session.fetch('handle') }
    rescue HTTP::Error => e
      raise Error, "sign-in as #{handle} failed (#{e.message})"
    end

    def logged_in?
      !@session.nil?
    end

    # Uploads an image for a link card. Returns the blob to put in the card's thumb.
    def upload_blob(bytes, mime_type)
      @http.post_bytes("#{ENTRYWAY}/com.atproto.repo.uploadBlob", bytes,
                       content_type: mime_type, token: access_token).fetch('blob')
    rescue HTTP::Error => e
      raise Error, "uploading the card image failed (#{e.message})"
    end

    # Creates a post from a record (Sweepers::Post#record), stamped now.
    # Returns its at:// URI and CID.
    def create_post(record, now: Time.now.utc)
      body = { repo: did, collection: 'app.bsky.feed.post',
               record: record.merge('createdAt' => now.utc.iso8601(3)) }
      @http.post_json("#{ENTRYWAY}/com.atproto.repo.createRecord", body, token: access_token).slice('uri', 'cid')
    rescue HTTP::Error => e
      raise Error, "creating the post failed (#{e.message})"
    end

    # The web address of a post, from its at:// URI.
    def self.web_url(handle, uri)
      "https://bsky.app/profile/#{handle}/post/#{uri.split('/').last}"
    end

    def inspect
      "#<#{self.class.name} #{handle}#{' (signed in)' if logged_in?}>"
    end

    private

    def access_token
      raise Error, 'not signed in' unless @session

      @session.fetch('accessJwt')
    end
  end
end
