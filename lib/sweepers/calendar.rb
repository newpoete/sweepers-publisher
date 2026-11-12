# frozen_string_literal: true

require 'date'

module Sweepers
  # Day-of-year arithmetic on the Sweepers canonical calendar.
  #
  # Every leaf is filed under a day of a 366-day canonical leap year (2000), as in
  # the Flask app and the editor: 1 January is day 1, 29 February is day 60 and
  # 31 December is day 366, in every year.
  module Calendar
    CANONICAL_YEAR = 2000

    module_function

    # The canonical day of year (1-366) for a real date.
    def day_of_year(date)
      Date.new(CANONICAL_YEAR, date.month, date.day).yday
    end

    # The real date a leaf filed under (year, day_of_year) falls on.
    #
    # Day 60 (29 February) in a non-leap year has no real date. It's treated as
    # 1 March, so the leaf is never due early, and it's never shown as "today",
    # since no non-leap date maps to day 60, which matches Flask.
    def leaf_date(year, day_of_year)
      canonical = Date.new(CANONICAL_YEAR, 1, 1) + (day_of_year - 1)
      return Date.new(year, 3, 1) if canonical.month == 2 && canonical.day == 29 && !Date.leap?(year)

      Date.new(year, canonical.month, canonical.day)
    end

    # The English ordinal for a day of the month: 1st, 2nd, 3rd, 4th ... 21st.
    def ordinal(day)
      suffix = if (11..13).cover?(day % 100) then 'th'
               else { 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(day % 10, 'th')
               end
      "#{day}#{suffix}"
    end
  end
end
