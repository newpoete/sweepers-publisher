# frozen_string_literal: true

# The age CLI is a real dependency of Crypto and Queue, so their specs use it
# rather than mocking it. CI installs it; locally, see README.
module AgeHelpers
  def skip_without_age
    skip 'age CLI not installed' unless system('age', '--version', out: File::NULL, err: File::NULL)
  rescue Errno::ENOENT
    skip 'age CLI not installed'
  end

  # A fresh key pair: [identity (private), recipients file path].
  def generate_age_key(dir)
    identity, = Open3.capture2('age-keygen')
    recipients = File.join(dir, 'recipients.txt')
    File.write(recipients, identity[/age1[0-9a-z]+/])
    [identity, recipients]
  end
end
