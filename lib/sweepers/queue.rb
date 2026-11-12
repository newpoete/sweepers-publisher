# frozen_string_literal: true

require 'json'
require_relative 'crypto'

module Sweepers
  # The queue: one age-encrypted JSON leaf per day of year, in one directory
  # (data/queue/ for real leaves, spec/fixtures/queue/ for fixtures), named by
  # its three-digit day: 001.age to 366.age. Publishing a day overwrites its
  # file, so the queue never holds more than 366 files.
  module Queue
    FILE_NAME = /\A(\d{3})\.age\z/

    module_function

    def path_for(dir, day_of_year)
      File.join(dir, format('%03d.age', day_of_year))
    end

    # Encrypts one leaf hash to the recipients and writes (or overwrites) its
    # day's file. Returns the path written.
    def write(leaf, dir, recipients_file)
      day = leaf.fetch('day_of_year') { leaf.fetch(:day_of_year) }
      raise ArgumentError, "day_of_year #{day.inspect} is outside 1-366" unless (1..366).cover?(day)

      path = path_for(dir, day)
      File.write(path, Crypto.encrypt(JSON.generate(leaf), recipients_file))
      path
    end

    # Decrypts every day file in dir. Returns leaf hashes, each tagged with its
    # file name under "source" for error messages. Any failure raises: a file
    # that isn't named for a day, invalid JSON, or a leaf filed under the wrong day.
    def load(dir, identity)
      raise Crypto::Error, "queue directory #{dir} not found" unless Dir.exist?(dir)

      Dir.glob(File.join(dir, '*.age')).sort.map { |path| load_file(path, identity) }
    end

    def load_file(path, identity)
      name = File.basename(path)
      day = name[FILE_NAME, 1]&.to_i
      raise Crypto::Error, "#{name}: queue files must be named 001.age to 366.age" unless day && (1..366).cover?(day)

      leaf = JSON.parse(Crypto.decrypt(File.binread(path), identity))
      raise Crypto::Error, "#{name}: holds a leaf for day #{leaf['day_of_year'].inspect}" unless leaf['day_of_year'] == day

      leaf.merge('source' => name)
    rescue JSON::ParserError => e
      raise Crypto::Error, "#{name}: invalid JSON (#{e.message[0, 80]})"
    end
  end
end
