# frozen_string_literal: true

# CRuby test entry. mruby runs the same unit tests from build/test_bundle.rb
# (tools/bundle.rb); the e2e tests spawn processes and are CRuby-only.
RHCI_ROOT = File.expand_path('..', __dir__)
require_relative '../lib/rhci'
require_relative 'harness'
require_relative 'oracle'
require_relative 'core_sexp'
Dir[File.join(__dir__, 'unit', '*_test.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'e2e', '*_test.rb')].sort.each { |f| require f }
exit(RT.run ? 0 : 1)
