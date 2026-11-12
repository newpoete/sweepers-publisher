# frozen_string_literal: true

# Builders for queue leaves: the factory for this project (no database, so
# plain hashes rather than FactoryBot). Call them inside each example.
module LeafHelpers
  def build_leaf(day, score: 5, html: nil, snippet: nil)
    {
      'version' => 1, 'aphorism_id' => 1000 + day, 'draft_id' => 1, 'day_of_year' => day,
      'html' => html || "<p>leaf #{day}</p>\n", 'snippet' => snippet, 'score' => score,
      'published_at' => '2026-01-01T12:00:00Z'
    }
  end

  def release_on(date, *leaves)
    Sweepers::Release.new(leaves, date: Date.iso8601(date))
  end

  def released_days(release)
    release.released_leaves.keys.sort
  end
end
