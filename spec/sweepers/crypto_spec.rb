# frozen_string_literal: true

RSpec.describe Sweepers::Crypto do
  describe '.encrypt' do
    it 'writes armored ciphertext that decrypts with the matching identity' do
      skip_without_age
      Dir.mktmpdir do |dir|
        identity, recipients = generate_age_key(dir)
        ciphertext = described_class.encrypt('{"version":1}', recipients)
        expect(ciphertext).to start_with('-----BEGIN AGE ENCRYPTED FILE-----')
        expect(described_class.decrypt(ciphertext, identity)).to eq('{"version":1}')
      end
    end
  end

  describe '.decrypt' do
    context 'when the identity is the wrong key' do
      it 'raises an error' do
        skip_without_age
        Dir.mktmpdir do |dir|
          _identity, recipients = generate_age_key(dir)
          other_identity, = Open3.capture2('age-keygen')
          ciphertext = described_class.encrypt('secret', recipients)
          expect { described_class.decrypt(ciphertext, other_identity) }.to raise_error(described_class::Error, /no identity matched/)
        end
      end
    end

    context 'when the ciphertext was tampered with' do
      it 'raises an error' do
        skip_without_age
        Dir.mktmpdir do |dir|
          identity, recipients = generate_age_key(dir)
          lines = described_class.encrypt('secret ' * 50, recipients).lines
          lines[-2] = (lines[-2][0] == 'A' ? 'B' : 'A') + lines[-2][1..]
          expect { described_class.decrypt(lines.join, identity) }.to raise_error(described_class::Error)
        end
      end
    end

    context 'when no identity is given' do
      it 'raises before calling age' do
        expect { described_class.decrypt('x', '') }.to raise_error(described_class::Error, /no age identity/)
      end
    end

    it 'leaves no identity file behind' do
      skip_without_age
      Dir.mktmpdir do |dir|
        identity, recipients = generate_age_key(dir)
        before = Dir.glob(File.join(Dir.tmpdir, 'sweepers-age*'))
        described_class.decrypt(described_class.encrypt('x', recipients), identity)
        expect(Dir.glob(File.join(Dir.tmpdir, 'sweepers-age*'))).to eq(before)
      end
    end
  end
end
