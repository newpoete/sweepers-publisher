# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'crypto'

module Sweepers
  # The queue: one age-encrypted JSON file per published leaf, in one directory
  # (data/queue/ for real leaves, spec/fixtures/queue/ for fixtures).
  #
  # Files are named with a random id, so names reveal nothing but how many
  # leaves exist. They are never edited: republishing a day adds a new file, and
  # a publish adds about 1 KB to the repo's history.
  module Queue
    module_function

    # Encrypts one leaf hash to the recipients and writes it as a new file.
    # Returns the path written.
    def add(leaf, dir, recipients_file)
      path = File.join(dir, "#{SecureRandom.hex(8)}.age")
      raise "#{path} already exists" if File.exist?(path)

      File.write(path, Crypto.encrypt(JSON.generate(leaf), recipients_file))
      path
    end

    # Decrypts every *.age file in dir. Returns leaf hashes, each tagged with
    # its file name under "source" for error messages. Any failure raises.
    def load(dir, identity)
      raise Crypto::Error, "queue directory #{dir} not found" unless Dir.exist?(dir)

      Dir.glob(File.join(dir, '*.age')).sort.map do |path|
        JSON.parse(Crypto.decrypt(File.binread(path), identity)).merge('source' => File.basename(path))
      rescue JSON::ParserError => e
        raise Crypto::Error, "#{File.basename(path)}: invalid JSON (#{e.message[0, 80]})"
      end
    end
  end
end
