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

task default: %i[test bench]
