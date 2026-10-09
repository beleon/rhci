# The mruby rghci targets. Kept deliberately lean: the core may only use
# what is listed here, so anything missing fails loudly in the mruby tests.
#
# Build (from the repo root):
#   MRUBY_CONFIG=$PWD/mruby_build_config.rb rake -f vendor/mruby/Rakefile -j8
MRuby::Build.new do |conf|
  conf.toolchain :gcc

  # Haskell Strings are code-point sequences: String#length/[] must count
  # characters, not bytes.
  conf.defines << 'MRB_UTF8_STRING'
  # Int is 64-bit on GHC; keep mrb_int the same width everywhere.
  conf.defines << 'MRB_INT64'
  # Stock mruby allows ~500 nested Ruby calls (~100 through blocks); the
  # parser and type checker recurse along syntactic nesting. The evaluator
  # never recurses regardless.
  conf.defines << 'MRB_CALL_LEVEL_MAX=100000'

  conf.gem core: 'mruby-bigint'      # Integer is unbounded
  conf.gem core: 'mruby-math'        # sqrt, exp, log, trig for Floating
  conf.gem core: 'mruby-io'          # $stdin for the REPL, File for :load
  conf.gem core: 'mruby-string-ext'
  conf.gem core: 'mruby-array-ext'
  conf.gem core: 'mruby-hash-ext'
  conf.gem core: 'mruby-numeric-ext'
  conf.gem core: 'mruby-enum-ext'
  conf.gem core: 'mruby-kernel-ext'
  conf.gem core: 'mruby-error'
  conf.gem core: 'mruby-exit'
  conf.gem core: 'mruby-compiler'
  conf.gem core: 'mruby-bin-mruby'

  conf.build_dir = File.expand_path('build/mruby', __dir__)
end
