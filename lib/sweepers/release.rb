# frozen_string_literal: true

require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'time'
require_relative 'calendar'

module Sweepers
  # Turns the decrypted queue into the site's data for one release date (UTC).
  #
  # A leaf belongs to its day of year, whatever the year. The release writes
  # only the days the site shows: today, yesterday and the current selections.
  # Selections look back, never ahead, so no day after the release date is ever
  # written anywhere. See docs/data-contract.md for every file this produces.
  class Release
    class InvalidLeaf < StandardError; end

    LEAF_VERSION = 1
    SELECTION_DAYS = 90
    SELECTION_LIMIT = 7
    SELECTION_MIN_SCORE = 8
    SNIPPET_LENGTH = 300
    DEFAULT_BASE_URL = 'https://newpoete.github.io/sweepers-publisher'

    Leaf = Struct.new(:aphorism_id, :draft_id, :day_of_year, :html, :snippet, :score, :published_at,
                      keyword_init: true)

    # A current selection: the leaf, and the date it's listed under (the most
    # recent date its day of year fell on before the release date).
    Selection = Struct.new(:leaf, :date, :days_ago, keyword_init: true)

    attr_reader :date, :base_url

    # leaves: the decrypted queue, an array of leaf hashes (see Sweepers::Queue),
    # at most one per day of year.
    def initialize(leaves, date:, base_url: DEFAULT_BASE_URL)
      @date = date
      @base_url = base_url.chomp('/')
      @queue = index_by_day(leaves.map { |raw| parse_leaf(raw) })
    end

    def today
      Calendar.day_of_year(date)
    end

    def yesterday
      Calendar.day_of_year(date - 1)
    end

    # Flask's Leaf.selections. For each of the 90 days before the release date
    # (today excluded), take that day's leaf. Keep scores of 8 or more, then the
    # 7 best by score (more recent day first on ties), listed newest first.
    def selections
      @selections ||= begin
        recent = (1..SELECTION_DAYS).filter_map do |days_ago|
          day = date - days_ago
          leaf = @queue[Calendar.day_of_year(day)]
          Selection.new(leaf: leaf, date: day, days_ago: days_ago) if leaf && leaf.score.to_i >= SELECTION_MIN_SCORE
        end
        best = recent.sort_by { |s| [-s.leaf.score, s.days_ago] }.first(SELECTION_LIMIT)
        best.sort_by(&:days_ago)
      end
    end

    # The only leaves that leave this class, by day: today, yesterday and the
    # current selections, where the queue has a leaf for them.
    def released_leaves
      @released_leaves ||= ([today, yesterday] + selections.map { |s| s.leaf.day_of_year })
                           .uniq.filter_map { |day| @queue[day] }
                           .to_h { |leaf| [leaf.day_of_year, leaf] }
    end

    # Every released file, as { relative path => content }.
    def files
      files = {
        'release.json' => json(release_record),
        'selections.json' => json(selections.map { |selection| selection_record(selection) })
      }
      released_leaves.each_value do |leaf|
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
      {
        date: date.iso8601,
        day_of_year: today,
        yesterday: { date: (date - 1).iso8601, day_of_year: yesterday },
        released_at: Time.now.utc.iso8601
      }
    end

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

    def index_by_day(leaves)
      leaves.each_with_object({}) do |leaf, by_day|
        raise InvalidLeaf, "two leaves for day #{leaf.day_of_year}" if by_day.key?(leaf.day_of_year)

        by_day[leaf.day_of_year] = leaf
      end
    end

    def parse_leaf(raw)
      where = raw['source'] || 'leaf'
      raise InvalidLeaf, "#{where}: unsupported version #{raw['version'].inspect}" unless raw['version'] == LEAF_VERSION

      int = ->(key) { raw[key].is_a?(Integer) ? raw[key] : raise(InvalidLeaf, "#{where}: #{key} must be an integer") }
      day = int.call('day_of_year')
      raise InvalidLeaf, "#{where}: day_of_year #{day} is outside 1-366" unless (1..366).cover?(day)
      raise InvalidLeaf, "#{where}: html must be a non-empty string" unless raw['html'].is_a?(String) && !raw['html'].empty?
      raise InvalidLeaf, "#{where}: score must be an integer or null" unless raw['score'].nil? || raw['score'].is_a?(Integer)

      Leaf.new(aphorism_id: int.call('aphorism_id'), draft_id: int.call('draft_id'), day_of_year: day,
               html: raw['html'], snippet: raw['snippet'], score: raw['score'],
               published_at: Time.iso8601(raw.fetch('published_at')))
    rescue KeyError, ArgumentError => e
      raise InvalidLeaf, "#{where}: #{e.message}"
    end
  end
end
