# frozen_string_literal: true

ROOT = __dir__
MRUBY_DIR = File.join(ROOT, 'vendor', 'mruby')
MRUBY_TAG = '4.0.0'
MRUBY = File.join(ROOT, 'build', 'mruby', 'bin', 'mruby')
RHCI = File.join(ROOT, 'build', 'rhci', 'bin', 'rhci')

# Release builds (docs/DEVELOPMENT.md, "Release builds").
COSMOCC_VERSION = '4.0.2'
COSMOCC_DIR = File.join(ROOT, 'build', 'cosmocc')
RHCI_COSMO = File.join(ROOT, 'build', 'rhci-cosmo', 'bin', 'rhci')
RHCI_MUSL = File.join(ROOT, 'build', 'rhci-musl', 'bin', 'rhci')
ALPINE_IMAGE = 'docker.io/library/alpine:3.20'

directory MRUBY_DIR do
  sh "git clone -q --depth 1 --branch #{MRUBY_TAG} https://github.com/mruby/mruby.git #{MRUBY_DIR}"
end

desc 'Generate the mruby bundles from lib/ and test/'
task :bundle do
  ruby 'tools/bundle.rb'
end

desc 'Build build/rhci.rb: the compact CRuby build (library + snapshot in one file)'
task compact: :bundle

desc 'Build build/mruby/bin/mruby and build/rhci/bin/rhci'
task mruby: [MRUBY_DIR, :bundle] do
  log = File.join(ROOT, 'build', 'mruby-build.log')
  env = { 'MRUBY_CONFIG' => File.join(ROOT, 'mruby_build_config.rb') }
  ok = system(env, 'rake', '-f', File.join(MRUBY_DIR, 'Rakefile'), '-j8', 'all', out: log, err: log)
  abort "mruby build failed:\n#{File.readlines(log).last(30).join}" unless ok
  # The binary is what gets copied around: without its symbols it is 40%
  # smaller and carries no build paths. (The mruby interpreter next to it
  # keeps them for debugging the C loop.)
  system('strip', RHCI) if system('strip', '--version', out: File::NULL, err: File::NULL)
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

desc 'Startup budgets: prompt < 10 ms, rhci -c < 200 ms (a desktop-class machine; run before committing startup changes)'
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

task default: %i[test]

# The Cosmopolitan toolchain, pinned: a zip from cosmo.zip (about 1.4 GB
# unpacked), fetched once into build/.
directory COSMOCC_DIR do
  zip = File.join(ROOT, 'build', "cosmocc-#{COSMOCC_VERSION}.zip")
  sh "curl -sSL -o #{zip} https://cosmo.zip/pub/cosmocc/cosmocc-#{COSMOCC_VERSION}.zip"
  mkdir_p COSMOCC_DIR
  sh "unzip -q #{zip} -d #{COSMOCC_DIR}"
  rm zip
end

desc 'Release build: build/rhci-cosmo/bin/rhci, one portable executable (needs curl, unzip)'
task cosmo: [MRUBY_DIR, :bundle, COSMOCC_DIR] do
  log = File.join(ROOT, 'build', 'cosmo-build.log')
  env = { 'MRUBY_CONFIG' => File.join(ROOT, 'tools', 'cosmo_build_config.rb'), 'COSMO_ROOT' => COSMOCC_DIR }
  ok = system(env, 'rake', '-f', File.join(MRUBY_DIR, 'Rakefile'), '-j8', 'all', out: log, err: log)
  abort "cosmopolitan build failed:\n#{File.readlines(log).last(30).join}" unless ok
end

desc 'Release build: build/rhci-musl/bin/rhci, a static x86-64 Linux binary (needs podman)'
task musl: [MRUBY_DIR, :bundle] do
  # Alpine's gcc is musl's; the repo is copied in (without build/) so the
  # builds here are untouched, and the binary copied back out.
  script = <<~SH
    set -e
    apk add -q build-base ruby ruby-rake >/dev/null
    mkdir /work && tar --exclude=./build -C /src -cf - . | tar -C /work -xf -
    cd /work
    LDFLAGS=-static MRUBY_CONFIG=/work/mruby_build_config.rb rake -f vendor/mruby/Rakefile -j8 > build.log 2>&1 \
      || { tail -30 build.log; exit 1; }
    strip build/rhci/bin/rhci
    mkdir -p /src/build/rhci-musl/bin && cp build/rhci/bin/rhci /src/build/rhci-musl/bin/rhci
  SH
  sh 'podman', 'run', '--rm', '--memory', '8g', '-v', "#{ROOT}:/src:Z", ALPINE_IMAGE, 'sh', '-c', script
end

desc 'All release assets into dist/: rhci (portable), rhci-linux-x86_64-musl, rhci.rb'
task release: %i[cosmo musl compact] do
  dist = File.join(ROOT, 'dist')
  mkdir_p dist
  cp RHCI_COSMO, File.join(dist, 'rhci')
  cp RHCI_MUSL, File.join(dist, 'rhci-linux-x86_64-musl')
  cp File.join(ROOT, 'build', 'rhci.rb'), File.join(dist, 'rhci.rb')
  puts "dist/: #{Dir.children(dist).sort.join(', ')}"
end

desc 'Run the exercism Haskell track on rhci and GHC (needs network and podman)'
task :exercism do
  ruby 'test/exercism/run.rb'
end

desc 'Differential fuzzing against GHCi: rake fuzz[seed,count,bottoms] (needs podman)'
task :fuzz, %i[seed count bottoms] do |_, a|
  ruby 'test/fuzz/run.rb', '--seed', (a[:seed] || '1').to_s, '--count', (a[:count] || '1000').to_s,
       '--bottoms', (a[:bottoms] || '0.05').to_s
end

desc 'Differential fuzzing with whole programs vs runghc: rake fuzz_progs[seed,count] (needs podman)'
task :fuzz_progs, %i[seed count] do |_, a|
  ruby 'test/fuzz/progs.rb', '--seed', (a[:seed] || '1').to_s, '--count', (a[:count] || '150').to_s
end
