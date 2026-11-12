# frozen_string_literal: true

RSpec.describe Sweepers::Queue do
  describe '.add' do
    it 'writes one encrypted file per leaf under a random name' do
      skip_without_age
      Dir.mktmpdir do |dir|
        _identity, recipients = generate_age_key(dir)
        first = described_class.add(build_leaf(2026, 1), dir, recipients)
        second = described_class.add(build_leaf(2026, 1), dir, recipients)
        expect([first, second].map { |path| File.basename(path) }).to all(match(/\A\h{16}\.age\z/))
        expect(first).not_to eq(second)
        expect(File.read(first)).not_to include('leaf 2026-1')
      end
    end
  end

  describe '.load' do
    it 'decrypts every leaf in the directory and tags its source file' do
      skip_without_age
      Dir.mktmpdir do |dir|
        identity, recipients = generate_age_key(dir)
        path = described_class.add(build_leaf(2026, 5), dir, recipients)
        described_class.add(build_leaf(2026, 6), dir, recipients)
        leaves = described_class.load(dir, identity)
        expect(leaves.map { |leaf| leaf['day_of_year'] }).to contain_exactly(5, 6)
        expect(leaves.map { |leaf| leaf['source'] }).to include(File.basename(path))
      end
    end

    context 'when a file decrypts to invalid JSON' do
      it 'raises an error naming the file' do
        skip_without_age
        Dir.mktmpdir do |dir|
          identity, recipients = generate_age_key(dir)
          File.write(File.join(dir, 'bad.age'), Sweepers::Crypto.encrypt('not json', recipients))
          expect { described_class.load(dir, identity) }.to raise_error(Sweepers::Crypto::Error, /bad\.age: invalid JSON/)
        end
      end
    end

    context 'when the directory does not exist' do
      it 'raises an error' do
        expect { described_class.load('/nonexistent/queue', 'key') }.to raise_error(Sweepers::Crypto::Error, /not found/)
      end
    end
  end
end
