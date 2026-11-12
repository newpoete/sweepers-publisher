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
    class InvalidQueue < StandardError; end

    QUEUE_VERSION = 1
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

    attr_reader :date, :base_url

    def initialize(queue, date:, base_url: DEFAULT_BASE_URL)
      @date = date
      @base_url = base_url.chomp('/')
      @leaves = parse(queue)
    end

    # Leaves due by the release date: the only ones that may leave this class.
    def due_leaves
      @due_leaves ||= @leaves.select { |leaf| leaf.date <= date }
    end

    # The newest due leaf for each day of year, as Flask's Leaf.by_day_of_year
    # chose it: the latest year, then the latest publish.
    def leaves_by_day
      @leaves_by_day ||= due_leaves.group_by(&:day_of_year).transform_values do |leaves|
        leaves.max_by { |leaf| [leaf.year, leaf.published_at] }
      end
    end

    # Flask's Leaf.selections: leaves from the last 90 days (not today) scoring
    # 8 or more; the 7 best by score (newer first on ties), shown newest first.
    #
    # One intended difference: the window is measured on real dates. Flask
    # matched on day of year alone, so a past year's leaf could slip into it.
    def selections
      @selections ||= begin
        recent = leaves_by_day.values.select do |leaf|
          (1..SELECTION_DAYS).cover?((date - leaf.date).to_i) && leaf.score.to_i >= SELECTION_MIN_SCORE
        end
        best = recent.sort_by { |leaf| [-leaf.score, date - leaf.date] }.first(SELECTION_LIMIT)
        best.sort_by { |leaf| date - leaf.date }
      end
    end

    # Every released file, as { relative path => content }.
    def files
      files = {
        'release.json' => json(release_record),
        'selections.json' => json(selections.map { |leaf| selection_record(leaf) })
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
      selections.each do |leaf|
        FileUtils.mkdir_p(File.join(staging, 'selection'))
        FileUtils.cp(selection_shell, File.join(staging, 'selection', "#{leaf.day_of_year}.html"))
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

    def leaf_record(leaf)
      { day_of_year: leaf.day_of_year, year: leaf.year, html: leaf.html }
    end

    def selection_record(leaf)
      {
        day_of_year: leaf.day_of_year,
        date: leaf.date.iso8601,
        snippet: leaf.snippet.to_s.strip.empty? ? self.class.snippet(leaf.html) : leaf.snippet
      }
    end

    def sitemap
      paths = %w[today yesterday selections] + selections.map { |leaf| "selection/#{leaf.day_of_year}" }
      paths.map { |path| "#{base_url}/#{path}\n" }.join
    end

    def json(data)
      "#{JSON.pretty_generate(data)}\n"
    end

    def parse(queue)
      raise InvalidQueue, "unsupported queue version: #{queue['version'].inspect}" unless queue['version'] == QUEUE_VERSION
      raise InvalidQueue, 'queue has no leaves array' unless queue['leaves'].is_a?(Array)

      queue['leaves'].each_with_index.map { |raw, i| parse_leaf(raw, i) }
    end

    def parse_leaf(raw, index)
      where = "leaf #{index}"
      int = ->(key) { raw[key].is_a?(Integer) ? raw[key] : raise(InvalidQueue, "#{where}: #{key} must be an integer") }
      day = int.call('day_of_year')
      raise InvalidQueue, "#{where}: day_of_year #{day} is outside 1-366" unless (1..366).cover?(day)
      raise InvalidQueue, "#{where}: html must be a non-empty string" unless raw['html'].is_a?(String) && !raw['html'].empty?
      raise InvalidQueue, "#{where}: score must be an integer or null" unless raw['score'].nil? || raw['score'].is_a?(Integer)

      Leaf.new(aphorism_id: int.call('aphorism_id'), draft_id: int.call('draft_id'), year: int.call('year'),
               day_of_year: day, html: raw['html'], snippet: raw['snippet'], score: raw['score'],
               published_at: Time.iso8601(raw.fetch('published_at')))
    rescue KeyError, ArgumentError => e
      raise InvalidQueue, "#{where}: #{e.message}"
    end
  end
end
