# frozen_string_literal: true

# The committed fixture queue (spec/fixtures/queue/, written by bin/fixtures) released on
# 2026-11-12 must reproduce what the live site showed that day (the parity snapshot).
RSpec.describe Sweepers::Release do
  context 'when releasing the fixture queue on the parity date, 2026-11-12' do
    it 'matches the live site and releases only the last three days and selections' do
      skip_without_age
      leaves = load_fixture_queue
      parity = JSON.parse(File.read(File.join(FIXTURES, 'parity-leaves.json')))['leaves']
      parity_html = ->(day) { parity.find { |leaf| leaf['day_of_year'] == day }['html'] }
      release = described_class.new(leaves, date: Date.new(2026, 11, 12))

      expect(leaves.map { |leaf| leaf['day_of_year'] }.sort)
        .to eq([200, 272, 274, 275, 280, 298, 300, 301, 310, 314, 315, 316, 317, 318])
      expect(release.released_leaves[317].html).to eq(parity_html.call(317))
      expect(release.released_leaves[316].html).to eq(parity_html.call(316))
      expect(release.selections.map { |s| s.leaf.day_of_year }).to eq([314, 301, 298, 280, 275, 274, 272])
      expect(released_days(release)).to eq([272, 274, 275, 280, 298, 301, 314, 315, 316, 317])
    end
  end

  context 'when releasing the fixture queue on a day with no leaf, 2026-11-14' do
    it 'releases no leaf for today, and the days before it that have one' do
      skip_without_age
      release = described_class.new(load_fixture_queue, date: Date.new(2026, 11, 14))

      expect(release.released_leaves.keys & [319, 318, 317]).to eq([318, 317])
    end
  end
end
