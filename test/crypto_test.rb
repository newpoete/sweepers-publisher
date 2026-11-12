# frozen_string_literal: true

require 'test_helper'
require 'open3'

# Needs the age CLI. CI installs it; locally, see README: Local development.
class CryptoTest < Minitest::Test
  include QueueHelpers

  def setup
    skip 'age CLI not installed' unless age_installed?
    @dir = Dir.mktmpdir
    @identity, = Open3.capture2('age-keygen')
    @recipients = File.join(@dir, 'recipients.txt')
    File.write(@recipients, @identity[/age1[0-9a-z]+/])
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_round_trip
    ciphertext = Sweepers::Crypto.encrypt('{"version":1}', @recipients)
    assert ciphertext.start_with?('-----BEGIN AGE ENCRYPTED FILE-----')
    assert_equal '{"version":1}', Sweepers::Crypto.decrypt(ciphertext, @identity)
  end

  def test_wrong_key_fails_loudly
    ciphertext = Sweepers::Crypto.encrypt('secret', @recipients)
    other, = Open3.capture2('age-keygen')
    assert_raises(Sweepers::Crypto::Error) { Sweepers::Crypto.decrypt(ciphertext, other) }
  end

  def test_tampered_file_fails_loudly
    ciphertext = Sweepers::Crypto.encrypt('secret ' * 50, @recipients)
    lines = ciphertext.lines
    body = lines[-2] # last base64 line of the payload
    lines[-2] = (body[0] == 'A' ? 'B' : 'A') + body[1..]
    assert_raises(Sweepers::Crypto::Error) { Sweepers::Crypto.decrypt(lines.join, @identity) }
  end

  def test_missing_identity_fails_before_calling_age
    assert_raises(Sweepers::Crypto::Error) { Sweepers::Crypto.decrypt('x', '') }
  end

  def test_decrypt_leaves_no_identity_file_behind
    before = Dir.glob(File.join(Dir.tmpdir, 'sweepers-age*'))
    Sweepers::Crypto.decrypt(Sweepers::Crypto.encrypt('x', @recipients), @identity)
    assert_equal before, Dir.glob(File.join(Dir.tmpdir, 'sweepers-age*'))
  end
end
