# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Sweepers
  # A small JSON-over-HTTPS client on Net::HTTP (sweepers-editor#127), the one
  # place the posting code touches the network. Specs replace it with an
  # instance_double.
  #
  # Errors carry the status and the server's error code and message, never the
  # request: a request may hold a password or a token.
  class HTTP
    class Error < StandardError
      attr_reader :status, :code

      def initialize(status, code, message)
        @status = status
        @code = code
        super("HTTP #{status}#{" #{code}" if code}#{": #{message}" if message}")
      end
    end

    TIMEOUT = 30 # seconds, for opening, reading and writing

    # GET a URL, with an optional query. Returns the parsed JSON body, or nil
    # for a 404 when not_found: :nil (a day with no leaf has no file).
    def get_json(url, query = {}, not_found: :raise)
      uri = URI(url)
      uri.query = URI.encode_www_form(query) unless query.empty?
      response = request(uri, Net::HTTP::Get.new(uri))
      return nil if not_found == :nil && response.code == '404'

      parse(response)
    end

    # POST a JSON body, with an optional bearer token. Returns the parsed JSON body.
    def post_json(url, body, token: nil)
      uri = URI(url)
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req['Authorization'] = "Bearer #{token}" if token
      req.body = JSON.generate(body)
      parse(request(uri, req))
    end

    # POST raw bytes (an image), with a bearer token. Returns the parsed JSON body.
    def post_bytes(url, bytes, content_type:, token:)
      uri = URI(url)
      req = Net::HTTP::Post.new(uri, 'Content-Type' => content_type, 'Authorization' => "Bearer #{token}")
      req.body = bytes
      parse(request(uri, req))
    end

    # Never show a request or token in a log or an error.
    def inspect
      "#<#{self.class.name}>"
    end

    private

    def request(uri, req)
      req['User-Agent'] = 'sweepers-publisher (+https://sweeperscalendar.com)'
      req['Accept'] = 'application/json'
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                          open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) do |http|
        http.request(req)
      end
    end

    def parse(response)
      body = response.body.to_s
      data = body.empty? ? {} : JSON.parse(body)
      return data if response.is_a?(Net::HTTPSuccess)

      raise Error.new(response.code.to_i, data['error'], data['message'])
    rescue JSON::ParserError
      raise Error.new(response.code.to_i, nil, 'the response was not JSON')
    end
  end
end
