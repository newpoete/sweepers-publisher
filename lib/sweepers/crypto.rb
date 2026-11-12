# frozen_string_literal: true

require 'open3'
require 'tmpdir'

module Sweepers
  # Thin wrapper around the `age` CLI (https://age-encryption.org).
  #
  # The queue is encrypted to an X25519 public key (a recipient, "age1...").
  # Only the release holds the private key (an identity, "AGE-SECRET-KEY-1...").
  # The editor needs nothing but `encrypt` and the public key.
  module Crypto
    class Error < StandardError; end

    module_function

    # Encrypts plaintext to the recipients in recipients_file, ASCII-armored.
    def encrypt(plaintext, recipients_file)
      run(['age', '--encrypt', '--armor', '--recipients-file', recipients_file], plaintext)
    end

    # Decrypts ciphertext with an identity given as a string (from a secret).
    #
    # age reads identities from a file, so the identity is written to a private
    # temp directory (mode 0700, file 0600) and removed before returning. It's
    # never passed on the command line, where other processes could see it.
    def decrypt(ciphertext, identity)
      raise Error, 'no age identity given' if identity.to_s.strip.empty?

      Dir.mktmpdir('sweepers-age') do |dir|
        path = File.join(dir, 'identity')
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(identity) }
        run(['age', '--decrypt', '--identity', path], ciphertext)
      end
    end

    def run(command, input)
      out, err, status = Open3.capture3(*command, stdin_data: input, binmode: true)
      # age's own messages never echo key material; pass them on for diagnosis.
      raise Error, "#{command[0..1].join(' ')} failed: #{err.strip}" unless status.success?

      out
    rescue Errno::ENOENT
      raise Error, 'the age CLI is not installed (see README: Local development)'
    end
  end
end
