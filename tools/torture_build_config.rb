# frozen_string_literal: true

# mruby_build_config.rb with RHCI_GC_TORTURE defined, into build/torture-*
# (`rake torture`). Every rhci source file is compiled with the define;
# only mrbgems/rhci-native/src/machine.c uses it.
ROOT = File.expand_path('..', __dir__)

module TortureConfig
  def self.dir(conf, name)
    conf.defines << 'RHCI_GC_TORTURE'
    conf.build_dir = File.join(ROOT, 'build', name)
  end
end

src = File.read(File.join(ROOT, 'mruby_build_config.rb')).gsub('__dir__', ROOT.inspect)
src = src.sub("conf.build_dir = File.expand_path('build/mruby', #{ROOT.inspect})",
              "TortureConfig.dir(conf, 'torture-mruby')")
src = src.sub("conf.build_dir = File.expand_path('build/rhci', #{ROOT.inspect})",
              "TortureConfig.dir(conf, 'torture-rhci')")
raise 'torture config: build dirs not found' unless src.include?("'torture-mruby'") && src.include?("'torture-rhci'")

eval(src) # rubocop:disable Security/Eval
