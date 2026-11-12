# frozen_string_literal: true

# The committed fixture queue (spec/fixtures/queue/) released on 2026-11-12
# must reproduce what the live site showed that day (the parity snapshot).
RSpec.describe Sweepers::Release do
  context 'when releasing the fixture queue on the parity date, 2026-11-12' do
    it 'matches the live site: today, yesterday and selections, with no future leaf' do
      skip_without_age
      identity = File.read(File.join(FIXTURES, 'fixture-identity.txt'))
      leaves = Sweepers::Queue.load(File.join(FIXTURES, 'queue'), identity)
      parity = JSON.parse(File.read(File.join(FIXTURES, 'parity-leaves.json')))['leaves']
      parity_html = ->(day) { parity.find { |leaf| leaf['day_of_year'] == day }['html'] }
      release = described_class.new(leaves, date: Date.new(2026, 11, 12))

      expect(release.leaves_by_day[317].html).to eq(parity_html.call(317))
      expect(release.leaves_by_day[316].html).to eq(parity_html.call(316))
      expect(release.selections.map { |s| s.leaf.day_of_year }).to eq([314, 301, 298, 280, 275, 274, 272])
      expect(release.leaves_by_day.size).to eq(366)
      expect(release.leaves_by_day[318].year).to eq(2019)
      expect(release.files.values.join).not_to match(/2026 \(day 3(1[89]|2\d|30)\)|2027 \(day/)
    end
  end
end
