# A Cosmopolitan Libc build of the rhci binary: one "actually portable
# executable" for Linux, macOS, Windows and the BSDs, x86-64 and ARM64,
# needing no libc. Experimental; the normal build is mruby_build_config.rb.
#
#   COSMO_ROOT=/path/to/cosmocc MRUBY_CONFIG=tools/cosmo_build_config.rb \
#     rake -f vendor/mruby/Rakefile
#
# The toolchain (bin/cosmocc, bin/cosmoar) is a zip from
# https://cosmo.zip/pub/cosmocc/ (built with cosmocc-4.0.2). A cross build:
# the host build only provides mrbc, so nothing portable has to run here.
COSMO_ROOT = ENV.fetch('COSMO_ROOT') { raise 'set COSMO_ROOT to the unpacked cosmocc directory' }

load File.expand_path('../mruby_build_config.rb', __dir__)

MRuby::CrossBuild.new('rhci-cosmo') do |conf|
  # rhci_common selects the gcc toolchain (flags, defines, gems); the
  # commands are replaced afterwards, since selecting a toolchain resets them.
  rhci_common(conf)
  conf.cc.command = "#{COSMO_ROOT}/bin/cosmocc"
  conf.cxx.command = "#{COSMO_ROOT}/bin/cosmoc++"
  conf.linker.command = "#{COSMO_ROOT}/bin/cosmocc"
  conf.linker.flags << '-static'
  conf.archiver.command = "#{COSMO_ROOT}/bin/cosmoar"
  conf.gem core: 'hal-posix-io'
  conf.gem File.expand_path('../mrbgems/rhci', __dir__)
  conf.build_dir = File.expand_path('../build/rhci-cosmo', __dir__)
end
