# frozen_string_literal: true

# CRuby entry point. mruby gets the same files, in the same order, as one
# bundle compiled into the rhci binary (tools/bundle.rb); this is the only
# file allowed to use `require`.
File.read(File.join(__dir__, 'rhci', 'manifest.txt')).split("\n").each do |name|
  require_relative File.join('rhci', name)
end

# The Prelude's Haskell source, and the library modules compiled after it
# (the mruby bundle embeds both instead).
Rhci::PRELUDE_SOURCE = File.read(File.join(__dir__, '..', 'prelude', 'Prelude.hs')).freeze
Rhci::LIBRARY_SOURCES = Rhci::LIBRARY_MODULES.to_h do |m|
  [m, File.read(File.join(__dir__, '..', 'prelude', *m.split('.')) + '.hs').freeze]
end.freeze
