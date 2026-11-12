# frozen_string_literal: true

# Builders for queue leaves: the factory for this project (no database, so
# plain hashes rather than FactoryBot). Call them inside each example.
module LeafHelpers
  # A queue leaf for (year, day_of_year). Published at noon, 30 days before
  # the leaf's date, unless given.
  def build_leaf(year, day, score: 5, html: nil, published_at: nil, snippet: nil)
    date = Sweepers::Calendar.leaf_date(year, day)
    {
      'version' => 1, 'aphorism_id' => (year * 1000) + day, 'draft_id' => 1, 'year' => year,
      'day_of_year' => day, 'html' => html || "<p>leaf #{year}-#{day}</p>\n", 'snippet' => snippet,
      'score' => score,
      'published_at' => published_at || (Time.utc(date.year, date.month, date.day, 12) - (30 * 86_400)).iso8601
    }
  end

  def release_on(date, *leaves)
    Sweepers::Release.new(leaves, date: Date.iso8601(date))
  end
end
