# frozen_string_literal: true

# Loaded by .rspec (--require spec_helper), so spec files need no requires.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'date'
require 'json'
require 'open3'
require 'tmpdir'
require 'sweepers/calendar'
require 'sweepers/crypto'
require 'sweepers/queue'
require 'sweepers/release'

ROOT = File.expand_path('..', __dir__)
FIXTURES = File.join(ROOT, 'spec', 'fixtures')

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.include LeafHelpers
  config.include AgeHelpers

  # Grouped expectations (Even Better Specs: "Group expectations") report
  # every failure in an example, not just the first.
  config.define_derived_metadata { |meta| meta[:aggregate_failures] = true }

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
