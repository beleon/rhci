# frozen_string_literal: true

# Differential fuzzing with whole programs (prog_gen.rb): each is run as
# `runghc Main.hs < input` by GHC (the oracle's podman image; cached in
# build/fuzz-progs) and as `:load Main` + `main`, with the same stdin, by
# rhci. They must agree: same stdout, same exception (if any) after it, and
# a program GHC rejects must be rejected.
#
#   ruby test/fuzz/progs.rb [--seed N] [--count N] [--bottoms P] [--mruby]
#
# --mruby runs the mruby binary instead of an in-process CRuby session: its
# stdin is ":load Main", "main", then the program's input (the REPL and the
# program share stdin, as in GHCi).
require 'fileutils'
require 'open3'
require_relative '../../lib/rhci'
require_relative '../oracle'
require_relative 'prog_gen'

module Fuzz
  module Progs
    ROOT = File.expand_path('../..', __dir__)
    IMAGE = 'docker.io/library/haskell:9.6'

    module_function

    def prepare(seed, count, bottoms)
      dir = File.join(ROOT, 'build', 'fuzz-progs', "s#{seed}-n#{count}#{bottoms.positive? ? "-b#{bottoms}" : ''}")
      return dir if File.exist?(File.join(dir, 'done'))

      FileUtils.rm_rf(dir)
      gen = ProgGen.new(seed, bottoms: bottoms)
      names = Array.new(count) do |i|
        name = format('p%03d', i)
        FileUtils.mkdir_p(File.join(dir, name))
        files, input = gen.program
        files.each { |f, src| File.write(File.join(dir, name, f), src) }
        File.write(File.join(dir, name, 'input.txt'), input)
        name
      end
      script = names.map do |n|
        "cd /w/#{n} && (timeout -s KILL 30 runghc Main.hs < input.txt > ghc.out 2> ghc.err; echo $? > ghc.status); cd /w"
      end.join("\n")
      FileUtils.chmod_R('a+rwX', dir)
      _, err, st = Open3.capture3('podman', 'run', '--rm', '-i', '--memory', '8g', '-v', "#{dir}:/w:Z", '-w', '/w', IMAGE, 'sh', '-c', script)
      raise "GHC run failed: #{err}" unless st.success?

      File.write(File.join(dir, 'done'), '')
      dir
    end

    class Sink
      attr_reader :text

      def initialize
        @text = +''
      end

      def write(s)
        @text << s
        s.length
      end

      def flush; end
    end

    # The mruby binary's answer, shaped like a session's: [load ok?, load
    # message, main status, stdout of main, exception message].
    def run_binary(dir)
      exe = File.join(ROOT, 'build', 'rhci', 'bin', 'rhci')
      stdin = ":load Main\nmain\n" + File.read(File.join(dir, 'input.txt'))
      out, err, st = Open3.capture3('timeout', '120', exe, stdin_data: stdin, chdir: dir)
      return [true, '', :limit, '', 'timeout'] if st.exitstatus == 124

      prompt = Rhci::CLI::PROMPT
      rest = out.delete_prefix(prompt)
      loaded = rest.start_with?('Ok, ')
      return [false, err.lines.first.to_s, nil, '', ''] unless loaded

      rest = rest.sub(/\AOk, [^\n]*\n/, '').delete_prefix(prompt)
      # main's output ends where the REPL prompts again (it then reads any
      # input main left as further inputs, as GHCi would).
      i = rest.index(prompt)
      rest = rest[0, i] if i
      exc = err[/\*\*\* Exception: (.*)/, 1].to_s
      [true, '', exc.empty? ? :ok : :exception, rest, exc]
    end

    # [kind, detail]: kind :agree, :disagree, :skip, :slow.
    def compare(dir, mruby: false)
      status = File.read(File.join(dir, 'ghc.status')).to_i
      g_out = File.read(File.join(dir, 'ghc.out'))
      g_err = File.read(File.join(dir, 'ghc.err'))
      return [:skip, 'GHC timed out'] if status == 124
      return compare_binary(dir, status, g_out, g_err) if mruby

      out = Sink.new
      err = Sink.new
      input = RT::FakeIO.new(File.read(File.join(dir, 'input.txt')))
      s = Rhci::Session.new(stdout: out, stderr: err, stdin: input, cwd: dir, limits: { steps: 30_000_000 })
      r = s.eval(':load Main')
      compile_error = g_err.include?('error:') && status != 0 && g_out.empty?
      if compile_error
        return [:agree, ''] if !r.ok? && r.status != :unsupported
        return [:skip, "unsupported: #{r.message}"] if r.status == :unsupported

        return [:disagree, "GHC rejects the program (#{first_error(g_err)}), rhci loads it"]
      end
      return [:skip, "unsupported: #{r.message}"] if r.status == :unsupported
      return [:disagree, "rhci rejects the program: #{r.message}"] unless r.ok?

      before = out.text.length
      r = s.eval('main')
      got = out.text[before..-1]
      return [:slow, r.message] if r.status == :limit
      return [:skip, "unsupported: #{r.message}"] if r.status == :unsupported

      if status.zero?
        return [:disagree, "rhci raised #{r.message.inspect}"] unless r.ok?
        return [:disagree, "stdout differs: #{first_difference(g_out, got)}"] unless got == g_out

        return [:agree, '']
      end
      return [:disagree, "GHC raised #{runtime_message(g_err).inspect}, rhci finished"] if r.ok?
      return [:disagree, "stdout before the exception differs: #{first_difference(g_out, got)}"] unless got == g_out

      g = runtime_message(g_err)
      o = Oracle.strip_locations(Rhci::Text.strip(r.message.to_s.lines.first.to_s))
      return [:imprecise, "GHC raised #{g.inspect}, rhci #{o.inspect}"] unless Oracle.same_exception?(g, o)

      [:agree, '']
    rescue StandardError => e
      [:disagree, "rhci internal error: #{e.class}: #{e.message.lines.first}"]
    end

    def compare_binary(dir, status, g_out, g_err)
      loaded, load_msg, st, got, exc = run_binary(dir)
      compile_error = g_err.include?('error:') && status != 0 && g_out.empty?
      return(loaded ? [:disagree, 'GHC rejects the program, rhci loads it'] : [:agree, '']) if compile_error
      return [:skip, "unsupported: #{load_msg}"] if !loaded && load_msg.include?('unsupported')
      return [:disagree, "rhci rejects the program: #{load_msg}"] unless loaded
      return [:slow, exc] if st == :limit
      return [:disagree, "stdout differs: #{first_difference(g_out, got)}"] unless got == g_out
      return(st == :ok ? [:agree, ''] : [:disagree, "rhci raised #{exc.inspect}"]) if status.zero?
      return [:disagree, "GHC raised #{runtime_message(g_err).inspect}, rhci finished"] if st == :ok

      g = runtime_message(g_err)
      o = Oracle.strip_locations(Rhci::Text.strip(exc))
      Oracle.same_exception?(g, o) ? [:agree, ''] : [:imprecise, "GHC raised #{g.inspect}, rhci #{o.inspect}"]
    end

    # runghc prints "Main.hs: message" (after any warnings).
    def runtime_message(err)
      line = err.lines.find { |l| l.start_with?('Main.hs: ', 'Main: ') }.to_s
      line = line.sub(/\A[^:]*: /, '')
      Oracle.strip_locations(Rhci::Text.strip(line))
    end

    def first_error(err)
      err.lines.find { |l| l.include?('error') }.to_s.strip[0, 120]
    end

    def first_difference(want, got)
      w = want.lines
      g = got.lines
      i = 0
      i += 1 while i < w.length && w[i] == g[i]
      "line #{i + 1}: GHC #{w[i].inspect}, rhci #{g[i].inspect}"
    end

    def main(argv)
      seed = (argv.include?('--seed') ? argv[argv.index('--seed') + 1] : 1).to_i
      count = (argv.include?('--count') ? argv[argv.index('--count') + 1] : 100).to_i
      bottoms = (argv.include?('--bottoms') ? argv[argv.index('--bottoms') + 1] : 0).to_f
      mruby = argv.include?('--mruby')
      dir = prepare(seed, count, bottoms)
      counts = Hash.new(0)
      Dir.children(dir).sort.each do |p|
        next unless File.directory?(File.join(dir, p))

        kind, detail = compare(File.join(dir, p), mruby: mruby)
        counts[kind] += 1
        puts "#{kind} #{p}: #{detail[0, 400]}" unless kind == :agree
      end
      puts "seed #{seed}: #{counts.map { |k, v| "#{v} #{k}" }.join(', ')}"
      counts[:disagree].zero?
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require_relative '../harness'
  exit(Fuzz::Progs.main(ARGV) ? 0 : 1)
end
