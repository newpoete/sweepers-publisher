# frozen_string_literal: true

require 'test_helper'

class ReleaseTest < Minitest::Test
  include QueueHelpers

  # Due by date: the UTC day boundary.

  def test_a_leaf_is_released_on_its_day_and_not_the_day_before
    leaf = queue_leaf(2026, 318, html: '<p>FUTURE-318</p>')
    refute release([leaf], '2026-11-12').leaves_by_day.key?(318)
    assert release([leaf], '2026-11-13').leaves_by_day.key?(318)
  end

  def test_no_future_leaf_appears_in_any_released_file
    leaves = [queue_leaf(2026, 317, score: 10), queue_leaf(2026, 318, score: 10, html: '<p>FUTURE-318</p>'),
              queue_leaf(2027, 1, score: 10, html: '<p>FUTURE-2027</p>')]
    files = release(leaves, '2026-11-12').files
    files.each_value { |content| refute_match(/FUTURE/, content) }
    assert files.key?('leaves/317.json')
  end

  # The newest due leaf for each day.

  def test_newest_year_wins_for_a_day
    leaves = [queue_leaf(2025, 317, html: '<p>old</p>'), queue_leaf(2026, 317, html: '<p>new</p>')]
    assert_equal '<p>new</p>', release(leaves, '2026-11-12').leaves_by_day[317].html
  end

  def test_past_year_leaf_stands_in_until_this_years_leaf_is_due
    leaves = [queue_leaf(2025, 318, html: '<p>last year</p>'), queue_leaf(2026, 318, html: '<p>this year</p>')]
    assert_equal '<p>last year</p>', release(leaves, '2026-11-12').leaves_by_day[318].html
    assert_equal '<p>this year</p>', release(leaves, '2026-11-13').leaves_by_day[318].html
  end

  def test_latest_publish_wins_within_a_year
    leaves = [queue_leaf(2026, 300, html: '<p>first</p>', published_at: '2026-09-01T00:00:00Z'),
              queue_leaf(2026, 300, html: '<p>republished</p>', published_at: '2026-10-01T00:00:00Z')]
    assert_equal '<p>republished</p>', release(leaves, '2026-11-12').leaves_by_day[300].html
  end

  # Year rollover and leap day.

  def test_new_year_releases_day_one_and_keeps_december
    leaves = [queue_leaf(2026, 366), queue_leaf(2027, 1)]
    r = release(leaves, '2027-01-01')
    assert_equal [1, 366], r.leaves_by_day.keys.sort
    record = JSON.parse(r.files['release.json'])
    assert_equal({ 'date' => '2026-12-31', 'day_of_year' => 366 }, record['yesterday'])
  end

  def test_leap_day_leaf_in_a_non_leap_year_waits_until_1_march
    leaf = queue_leaf(2027, 60)
    refute release([leaf], '2027-02-28').leaves_by_day.key?(60)
    assert release([leaf], '2027-03-01').leaves_by_day.key?(60)
  end

  def test_leap_day_leaf_in_a_leap_year_is_released_on_29_february
    leaf = queue_leaf(2028, 60)
    refute release([leaf], '2028-02-28').leaves_by_day.key?(60)
    r = release([leaf], '2028-02-29')
    assert r.leaves_by_day.key?(60)
    assert_equal 60, JSON.parse(r.files['release.json'])['day_of_year']
  end

  # Selections (Flask's Leaf.selections).

  def test_selections_keep_the_best_seven_and_show_them_newest_first
    # Days 300-316 (17 leaves) before 2026-11-12 (day 317), scores cycling 6-10.
    leaves = (300..316).map { |day| queue_leaf(2026, day, score: 6 + (day % 5)) }
    days = release(leaves, '2026-11-12').selections.map(&:day_of_year)
    # 10s fall on days 314, 309, 304; 9s on 313, 308, 303; the newest 8 is 312.
    assert_equal [314, 313, 312, 309, 308, 304, 303], days
  end

  def test_selections_skip_today_low_scores_and_leaves_older_than_90_days
    leaves = [queue_leaf(2026, 317, score: 10), # today
              queue_leaf(2026, 316, score: 7),  # below 8
              queue_leaf(2026, 227, score: 10), # exactly 90 days before 2026-11-12
              queue_leaf(2026, 226, score: 10)] # 91 days
    assert_equal [227], release(leaves, '2026-11-12').selections.map(&:day_of_year)
  end

  def test_selections_span_the_new_year
    leaves = [queue_leaf(2026, 360, score: 9), queue_leaf(2027, 3, score: 8)]
    assert_equal [3, 360], release(leaves, '2027-01-05').selections.map(&:day_of_year)
  end

  def test_a_past_years_leaf_is_not_a_recent_selection
    # Flask matched selections on day of year only; this release uses real dates.
    leaves = [queue_leaf(2025, 310, score: 10)]
    assert_empty release(leaves, '2026-11-12').selections
  end

  def test_selection_snippet_prefers_the_snippet_field
    leaves = [queue_leaf(2026, 316, score: 9, html: '<p>full text</p>', snippet: 'short')]
    assert_equal 'short', JSON.parse(release(leaves, '2026-11-12').files['selections.json']).first['snippet']
  end

  def test_snippet_matches_jinja_striptags_and_truncate
    assert_equal "Don't panic.", Sweepers::Release.snippet("<p>Don&#39;t <em>panic</em>.</p>\n")
    long = "<p>#{(['word'] * 100).join(' ')}</p>"
    snippet = Sweepers::Release.snippet(long)
    assert_operator snippet.length, :<=, 300
    assert snippet.end_with?('word ...'), snippet[-20..]
  end

  # Output files.

  def test_files_for_an_empty_queue
    files = release([], '2026-11-12').files
    assert_equal %w[release.json selections.json sitemap.txt], files.keys.sort
    assert_equal [], JSON.parse(files['selections.json'])
  end

  def test_sitemap_uses_https_and_lists_selections
    leaves = [queue_leaf(2026, 314, score: 10)]
    sitemap = release(leaves, '2026-11-12').files['sitemap.txt'].lines.map(&:chomp)
    assert_equal %w[today yesterday selections selection/314].map { |p| "#{Sweepers::Release::DEFAULT_BASE_URL}/#{p}" },
                 sitemap
  end

  def test_write_builds_a_complete_site_and_refuses_to_overwrite
    leaves = [queue_leaf(2026, 314, score: 10), queue_leaf(2026, 317)]
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'site')
      r = release(leaves, '2026-11-12')
      r.write(out, site_dir: File.join(ROOT, 'site'), data_dir: File.join(ROOT, 'data'))
      %w[release.json selections.json sitemap.txt mountweazel.json leaves/314.json leaves/317.json
         selection/314.html selection.html].each { |path| assert File.exist?(File.join(out, path)), path }
      assert_equal({ 'html' => JSON.parse(File.read(File.join(ROOT, 'data', 'mountweazel.json')))['html'] },
                   JSON.parse(File.read(File.join(out, 'mountweazel.json'))))
      assert_raises(ArgumentError) { r.write(out, site_dir: File.join(ROOT, 'site'), data_dir: File.join(ROOT, 'data')) }
      refute File.exist?("#{out}.partial")
    end
  end

  # Queue validation: bad input fails loudly.

  def test_invalid_queues_are_rejected
    assert_raises(Sweepers::Release::InvalidQueue) { Sweepers::Release.new({ 'version' => 2, 'leaves' => [] }, date: Date.today) }
    assert_raises(Sweepers::Release::InvalidQueue) { release([queue_leaf(2026, 367)], '2026-11-12') }
    assert_raises(Sweepers::Release::InvalidQueue) { release([queue_leaf(2026, 1).merge('html' => '')], '2026-11-12') }
    assert_raises(Sweepers::Release::InvalidQueue) { release([queue_leaf(2026, 1).merge('published_at' => 'soon')], '2026-11-12') }
    assert_raises(Sweepers::Release::InvalidQueue) { release([queue_leaf(2026, 1).tap { |l| l.delete('year') }], '2026-11-12') }
  end
end
