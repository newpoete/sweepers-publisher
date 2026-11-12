# frozen_string_literal: true

RSpec.describe Sweepers::Calendar do
  describe '.day_of_year' do
    it 'numbers days on a 366-day canonical leap year' do
      expect(described_class.day_of_year(Date.new(2026, 1, 1))).to eq(1)
      expect(described_class.day_of_year(Date.new(2026, 2, 28))).to eq(59)
      expect(described_class.day_of_year(Date.new(2026, 11, 12))).to eq(317)
      expect(described_class.day_of_year(Date.new(2026, 12, 31))).to eq(366)
    end

    context 'when the year is not a leap year' do
      it 'skips day 60, which belongs to 29 February' do
        expect(described_class.day_of_year(Date.new(2026, 3, 1))).to eq(61)
      end
    end

    context 'when the date is 29 February' do
      it 'returns day 60' do
        expect(described_class.day_of_year(Date.new(2028, 2, 29))).to eq(60)
      end
    end
  end

  describe '.canonical_date' do
    it 'returns the month and day of a day of year, in the canonical year' do
      expect(described_class.canonical_date(60)).to eq(Date.new(2000, 2, 29))
      expect(described_class.canonical_date(317)).to eq(Date.new(2000, 11, 12))
    end
  end

  describe '.ordinal' do
    it 'adds English ordinal suffixes, including the teens' do
      ordinals = [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map { |day| described_class.ordinal(day) }
      expect(ordinals).to eq(%w[1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd 31st])
    end
  end
end
