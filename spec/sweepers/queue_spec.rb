# frozen_string_literal: true

RSpec.describe Sweepers::Queue do
  describe '.write' do
    it "writes an encrypted file named for the leaf's day" do
      skip_without_age
      Dir.mktmpdir do |dir|
        _identity, recipients = generate_age_key(dir)
        path = described_class.write(build_leaf(5), dir, recipients)
        expect(File.basename(path)).to eq('005.age')
        expect(File.read(path)).not_to include('leaf 5')
      end
    end

    context 'when the day already has a file' do
      it 'overwrites it, so the queue keeps one leaf per day' do
        skip_without_age
        Dir.mktmpdir do |dir|
          identity, recipients = generate_age_key(dir)
          described_class.write(build_leaf(5, html: '<p>first</p>'), dir, recipients)
          described_class.write(build_leaf(5, html: '<p>second</p>'), dir, recipients)
          leaves = described_class.load(dir, identity)
          expect(leaves.map { |leaf| leaf['html'] }).to eq(['<p>second</p>'])
        end
      end
    end
  end

  describe '.load' do
    it 'decrypts every day file and tags its source file' do
      skip_without_age
      Dir.mktmpdir do |dir|
        identity, recipients = generate_age_key(dir)
        described_class.write(build_leaf(5), dir, recipients)
        described_class.write(build_leaf(366), dir, recipients)
        leaves = described_class.load(dir, identity)
        expect(leaves.map { |leaf| [leaf['day_of_year'], leaf['source']] }).to eq([[5, '005.age'], [366, '366.age']])
      end
    end

    context 'when a file is not named for a day' do
      it 'raises an error naming the file' do
        skip_without_age
        Dir.mktmpdir do |dir|
          identity, recipients = generate_age_key(dir)
          File.write(File.join(dir, '400.age'), Sweepers::Crypto.encrypt('{}', recipients))
          expect { described_class.load(dir, identity) }.to raise_error(Sweepers::Crypto::Error, /400\.age: queue files must be named/)
        end
      end
    end

    context "when a file holds another day's leaf" do
      it 'raises an error naming the file' do
        skip_without_age
        Dir.mktmpdir do |dir|
          identity, recipients = generate_age_key(dir)
          File.write(File.join(dir, '007.age'), Sweepers::Crypto.encrypt(JSON.generate(build_leaf(8)), recipients))
          expect { described_class.load(dir, identity) }.to raise_error(Sweepers::Crypto::Error, /007\.age: holds a leaf for day 8/)
        end
      end
    end

    context 'when a file decrypts to invalid JSON' do
      it 'raises an error naming the file' do
        skip_without_age
        Dir.mktmpdir do |dir|
          identity, recipients = generate_age_key(dir)
          File.write(File.join(dir, '001.age'), Sweepers::Crypto.encrypt('not json', recipients))
          expect { described_class.load(dir, identity) }.to raise_error(Sweepers::Crypto::Error, /001\.age: invalid JSON/)
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
