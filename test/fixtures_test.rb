# frozen_string_literal: true

require 'test_helper'

# The committed fixture queue reproduces the live site of 2026-11-12 (the
# parity snapshot): the same today, yesterday and selections.
class FixturesTest < Minitest::Test
  include QueueHelpers

  def setup
    skip 'age CLI not installed' unless age_installed?
    identity = File.read(File.join(FIXTURES, 'fixture-identity.txt'))
    plaintext = Sweepers::Crypto.decrypt(File.binread(File.join(FIXTURES, 'queue.age')), identity)
    @queue = JSON.parse(plaintext)
    @parity = JSON.parse(File.read(File.join(FIXTURES, 'parity-leaves.json')))
    @release = Sweepers::Release.new(@queue, date: Date.new(2026, 11, 12))
  end

  def parity_html(day)
    @parity['leaves'].find { |l| l['day_of_year'] == day }['html']
  end

  def test_today_and_yesterday_match_the_live_site
    assert_equal parity_html(317), @release.leaves_by_day[317].html
    assert_equal parity_html(316), @release.leaves_by_day[316].html
  end

  def test_selections_match_the_live_site
    assert_equal [314, 301, 298, 280, 275, 274, 272], @release.selections.map(&:day_of_year)
  end

  def test_fixture_covers_every_day_and_some_future
    days = @queue['leaves'].map { |l| [l['year'], l['day_of_year']] }
    assert_equal (1..366).to_a, days.select { |y, _| y == 2026 }.map(&:last).sort
    assert days.any? { |y, _| y == 2027 }, 'future leaves exist'
    refute @release.files.values.join.include?('2027'), 'no 2027 leaf released on 2026-11-12'
  end
end
