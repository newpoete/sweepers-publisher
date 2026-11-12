# frozen_string_literal: true

require 'date'

module Sweepers
  # Day-of-year arithmetic on the Sweepers canonical calendar.
  #
  # Every leaf belongs to a day of a 366-day canonical leap year (2000), as in
  # the Flask app and the editor: 1 January is day 1, 29 February is day 60 and
  # 31 December is day 366, in every year. A leaf belongs to its date whatever
  # the year. Day 60 is never "today" in a non-leap year.
  module Calendar
    CANONICAL_YEAR = 2000

    module_function

    # The canonical day of year (1-366) for a real date.
    def day_of_year(date)
      Date.new(CANONICAL_YEAR, date.month, date.day).yday
    end

    # The day of year as a date in the canonical year, for its month and day.
    def canonical_date(day_of_year)
      Date.new(CANONICAL_YEAR, 1, 1) + (day_of_year - 1)
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
