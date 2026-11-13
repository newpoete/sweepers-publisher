# frozen_string_literal: true

# config/recipients.txt holds the real queue's age public key (sweepers-editor#93).
RSpec.describe 'config/recipients.txt' do
  def recipients_path
    File.join(ROOT, 'config', 'recipients.txt')
  end

  def keys(path = recipients_path)
    File.readlines(path, chomp: true).reject { |line| line.empty? || line.start_with?('#') }
  end

  it 'holds exactly one age public key, which is not the fixture key and not a private key' do
    fixture = keys(File.join(ROOT, 'spec', 'fixtures', 'fixture-recipient.txt')).first
    expect(fixture).to start_with('age1')
    expect(keys.size).to eq(1)
    expect(keys.first).to match(/\Aage1[02-9ac-hj-np-z]{58}\z/)
    expect(keys.first).not_to eq(fixture)
    expect(File.read(recipients_path)).not_to include('AGE-SECRET-KEY')
  end

  it 'is a recipients file age can encrypt to' do
    skip_without_age
    ciphertext = Sweepers::Crypto.encrypt('{"version":1}', recipients_path)
    expect(ciphertext).to start_with('-----BEGIN AGE ENCRYPTED FILE-----')
  end
end
