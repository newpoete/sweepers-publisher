# frozen_string_literal: true

require 'minitest/autorun'
require 'date'
require 'json'
require 'tmpdir'
require 'sweepers/calendar'
require 'sweepers/crypto'
require 'sweepers/release'

ROOT = File.expand_path('..', __dir__)
FIXTURES = File.join(ROOT, 'test', 'fixtures')

module QueueHelpers
  # A queue leaf for (year, day_of_year); the published time defaults to noon,
  # 30 days before the leaf's date.
  def queue_leaf(year, day, score: 5, html: nil, published_at: nil, snippet: nil)
    date = Sweepers::Calendar.leaf_date(year, day)
    {
      'aphorism_id' => (year * 1000) + day, 'draft_id' => 1, 'year' => year, 'day_of_year' => day,
      'html' => html || "<p>leaf #{year}-#{day}</p>\n", 'snippet' => snippet, 'score' => score,
      'published_at' => published_at || Time.utc(date.year, date.month, date.day, 12).-(30 * 86_400).iso8601
    }
  end

  def queue(*leaves)
    { 'version' => 1, 'leaves' => leaves }
  end

  def release(leaves, date)
    Sweepers::Release.new(queue(*leaves), date: Date.iso8601(date))
  end

  def doy(date)
    Sweepers::Calendar.day_of_year(Date.iso8601(date))
  end

  def age_installed?
    system('age', '--version', out: File::NULL, err: File::NULL)
  rescue Errno::ENOENT
    false
  end
end
