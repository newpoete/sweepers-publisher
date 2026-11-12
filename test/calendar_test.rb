# frozen_string_literal: true

require 'test_helper'

class CalendarTest < Minitest::Test
  include QueueHelpers

  def test_day_of_year_uses_the_canonical_leap_year
    assert_equal 1, doy('2026-01-01')
    assert_equal 59, doy('2026-02-28')
    assert_equal 61, doy('2026-03-01'), 'day 60 is reserved for 29 February in every year'
    assert_equal 60, doy('2028-02-29')
    assert_equal 317, doy('2026-11-12'), 'the parity snapshot day'
    assert_equal 366, doy('2026-12-31')
  end

  def test_leaf_date_round_trips_ordinary_days
    assert_equal Date.new(2026, 11, 12), Sweepers::Calendar.leaf_date(2026, 317)
    assert_equal Date.new(2026, 12, 31), Sweepers::Calendar.leaf_date(2026, 366)
    assert_equal Date.new(2027, 1, 1), Sweepers::Calendar.leaf_date(2027, 1)
  end

  def test_leap_day_leaf_falls_on_29_february_in_leap_years
    assert_equal Date.new(2028, 2, 29), Sweepers::Calendar.leaf_date(2028, 60)
  end

  def test_leap_day_leaf_falls_on_1_march_in_other_years
    assert_equal Date.new(2027, 3, 1), Sweepers::Calendar.leaf_date(2027, 60)
  end

  def test_ordinal
    assert_equal %w[1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd 31st],
                 [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map { |d| Sweepers::Calendar.ordinal(d) }
  end
end
