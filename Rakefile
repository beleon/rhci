# frozen_string_literal: true

ROOT = __dir__
MRUBY_DIR = File.join(ROOT, 'vendor', 'mruby')
MRUBY_TAG = '4.0.0'
MRUBY = File.join(ROOT, 'build', 'mruby', 'bin', 'mruby')
RHCI = File.join(ROOT, 'build', 'rhci', 'bin', 'rhci')

directory MRUBY_DIR do
  sh "git clone -q --depth 1 --branch #{MRUBY_TAG} https://github.com/mruby/mruby.git #{MRUBY_DIR}"
end

desc 'Generate the mruby bundles from lib/ and test/'
task :bundle do
  ruby 'tools/bundle.rb'
end

desc 'Build build/mruby/bin/mruby and build/rhci/bin/rhci'
task mruby: [MRUBY_DIR, :bundle] do
  log = File.join(ROOT, 'build', 'mruby-build.log')
  env = { 'MRUBY_CONFIG' => File.join(ROOT, 'mruby_build_config.rb') }
  ok = system(env, 'rake', '-f', File.join(MRUBY_DIR, 'Rakefile'), '-j8', 'all', out: log, err: log)
  abort "mruby build failed:\n#{File.readlines(log).last(30).join}" unless ok
end

desc 'Check lib/ and tests for constructs mruby lacks'
task :lint do
  ruby 'tools/lint.rb'
end

desc 'Run the test suite on CRuby and on mruby'
task test: %i[lint mruby] do
  cruby = system(RbConfig.ruby, File.join(ROOT, 'test', 'run.rb'))
  mruby = system(MRUBY, File.join(ROOT, 'build', 'test_bundle.rb'))
  abort 'tests failed' unless cruby && mruby
end

desc 'Startup budgets: prompt < 10 ms, rhci -c < 200 ms'
task bench: :mruby do
  ruby 'tools/bench_startup.rb', RHCI
end

desc 'Runtime benchmarks (bench/programs.txt) on CRuby and the mruby binary'
task bench_runtime: :mruby do
  ruby 'tools/bench_runtime.rb'
end

# The mruby builds with RHCI_GC_TORTURE (full collections inside the C
# evaluation loop), in build/torture-*; run after changing machine.c.
desc 'Run the mruby tests with GC torture in the C evaluation loop (slow)'
task torture: %i[lint bundle] do
  log = File.join(ROOT, 'build', 'torture-build.log')
  env = { 'MRUBY_CONFIG' => File.join(ROOT, 'tools', 'torture_build_config.rb') }
  ok = system(env, 'rake', '-f', File.join(MRUBY_DIR, 'Rakefile'), '-j8', 'all', out: log, err: log)
  abort "torture build failed:\n#{File.readlines(log).last(30).join}" unless ok
  abort 'tests failed under GC torture' unless system(File.join(ROOT, 'build', 'torture-mruby', 'bin', 'mruby'),
                                                      File.join(ROOT, 'build', 'test_bundle.rb'))
end

task default: %i[test bench]

desc 'Run the exercism Haskell track on rhci and GHC (needs network and podman)'
task :exercism do
  ruby 'test/exercism/run.rb'
end
