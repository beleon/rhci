# frozen_string_literal: true

# CRuby entry point. mruby gets the same files, in the same order, as one
# bundle compiled into the rhci binary (tools/bundle.rb); this is the only
# file allowed to use `require`.
File.read(File.join(__dir__, 'rhci', 'manifest.txt')).split("\n").each do |name|
  require_relative File.join('rhci', name)
end
