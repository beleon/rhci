# frozen_string_literal: true

# Differential fuzzing: random expressions (test/fuzz/gen.rb) evaluated by
# real GHCi (the oracle's podman image) and by rhci, compared under the
# oracle's rules -- values exactly, errors by kind, and the output printed
# before an exception exactly.
#
#   ruby test/fuzz/run.rb [--seed N] [--count N] [--bottoms P] [--mruby] [--sessions]
#
# --sessions generates GHCi sessions instead (session_gen.rb): COUNT inputs
# in sessions of SESSION_LENGTH, each section one session.
#
# --mruby evaluates in the mruby test interpreter (build/mruby/bin/mruby,
# with the C loop and rhci-native, as the binary) instead of in-process
# CRuby: the binary's bundle plus a small runner, all sections in one run.
#
# --bottoms P makes a leaf a tagged error with probability P; when both
# sides raise, the same tag must come out (the same subexpression was
# evaluated first).
#
# GHCi's answers are cached per seed and count in build/fuzz.
require 'fileutils'
require 'open3'
require_relative '../../lib/rhci'
require_relative '../oracle'
require_relative 'gen'
require_relative 'session_gen'

module Fuzz
  ROOT = File.expand_path('../..', __dir__)
  WORK = File.join(ROOT, 'build', 'fuzz')
  PER_SECTION = 100
  IMPORTS = ['import Data.List', 'import Data.Char', 'import Data.Maybe', 'import qualified Data.Map as M',
             'import qualified Data.Set as S', 'import Text.Printf'].freeze

  STATUS = { ok: :ok, parse_error: :parse, scope_error: :scope, compile_error: :compile,
             exception: :runtime }.freeze

  module_function

  SESSION_LENGTH = 40

  def probes(seed, count, bottoms, sessions)
    if sessions
      gen = SessionGen.new(seed, bottoms: bottoms)
      return Array.new((count + SESSION_LENGTH - 1) / SESSION_LENGTH) { gen.session(SESSION_LENGTH) }
    end
    gen = Gen.new(seed, bottoms: bottoms)
    Array.new(count) { gen.probe }.each_slice(PER_SECTION).to_a
  end

  def write_probes(path, list, sessions = false)
    out = []
    list.each_with_index do |chunk, i|
      out << "## fuzz #{i + 1}" << ''
      # Sessions use what programs use (Data.Bits, Data.Ratio, ...).
      out.concat(sessions ? ProgGen::IMPORTS : IMPORTS)
      out.concat(Gen::DECLS)
      out.concat(chunk)
      out << ''
    end
    File.write(path, out.join("\n"))
  end

  def golden(seed, count, bottoms, sessions = false)
    FileUtils.mkdir_p(WORK)
    base = File.join(WORK, "#{sessions ? 'r' : 's'}#{seed}-n#{count}#{bottoms.positive? ? "-b#{bottoms}" : ''}")
    unless File.exist?("#{base}.golden")
      write_probes("#{base}.probes", probes(seed, count, bottoms, sessions), sessions)
      out, err, st = Open3.capture3('uv', 'run', '--no-project', 'python',
                                    File.join(ROOT, 'oracle', 'run_oracle.py'), "#{base}.probes")
      raise "oracle failed: #{err}" unless st.success?

      File.write("#{base}.golden", out)
    end
    Oracle.load("#{base}.golden")
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

  Result = Struct.new(:status, :message) do
    def ok?
      status == :ok
    end
  end

  def input_of(p)
    p.input.start_with?(":{\n") ? p.input.split("\n")[1..-2].join("\n") : p.input
  end

  # [[Result, output], ...] for one section, in a CRuby session.
  def cruby_results(probes)
    out = Sink.new
    s = Rhci::Session.new(stdout: out, stderr: out, limits: { steps: 5_000_000 })
    probes.map do |p|
      before = out.text.length
      r = s.eval(input_of(p))
      [Result.new(r.status, r.message), out.text[before..-1]]
    rescue StandardError => e
      [Result.new(:internal, "#{e.class}: #{e.message.lines.first}"), '']
    end
  end

  MRUBY_RUNNER = <<~'RUBY'
    class FuzzSink
      def initialize
        @t = ''.dup
      end

      def write(s)
        @t << s
        s.length
      end

      def flush; end

      def take
        t = @t
        @t = ''.dup
        t
      end
    end
    text = File.open(ARGV[0]) { |f| f.read }
    text.split("\x1c").each do |sec|
      out = FuzzSink.new
      s = Rhci::Session.new(stdout: out, stderr: out, limits: { steps: 5_000_000 })
      sec.split("\x1d").each do |input|
        begin
          r = s.eval(input)
          $stdout.write("#{r.status}\x1e#{r.message}\x1e#{out.take}\x1f")
        rescue StandardError => e
          $stdout.write("internal\x1e#{e.class}: #{e.message}\x1e\x1f")
        end
      end
    end
  RUBY

  # Section title => [[Result, output], ...], from one mruby run.
  def mruby_results(probes)
    sections = probes.map(&:section).uniq
    FileUtils.mkdir_p(WORK)
    runner = File.join(WORK, 'mruby_runner.rb')
    File.write(runner, File.read(File.join(ROOT, 'mrbgems', 'rhci', 'mrblib', 'rhci.rb')) + MRUBY_RUNNER)
    inputs = File.join(WORK, 'mruby_inputs.txt')
    File.write(inputs, sections.map { |s| probes.select { |p| p.section == s }.map { |p| input_of(p) }.join("\x1d") }.join("\x1c"))
    out, err, st = Open3.capture3(File.join(ROOT, 'build', 'mruby', 'bin', 'mruby'), runner, inputs)
    raise "mruby runner failed: #{err[0, 500]}" unless st.success?

    records = out.split("\x1f", -1)
    results = {}
    sections.each do |s|
      results[s] = probes.select { |p| p.section == s }.map do
        status, message, got = records.shift.to_s.split("\x1e", -1)
        [Result.new(status.to_s.to_sym, message.to_s.empty? ? nil : message), got.to_s]
      end
    end
    results
  end

  # [kind, detail] for each disagreement in one section.
  def compare_section(probes, results, sessions: false)
    problems = []
    imprecise = []
    stats = Hash.new(0)
    probes.each_with_index do |p, i|
      r, got = results[i]
      if r.status == :internal
        problems << "#{p.input}\n    rhci internal error: #{r.message}"
        next
      end
      if p.input.start_with?('import ', 'data ', 'infixl ', 'instance ', ':{')
        if !r.ok? && Oracle.outcome(p.text) == :ok
          problems << "#{p.input}\n    rhci rejected a declaration GHCi accepts: #{r.message}"
        end
        next stats[:import] += 1
      end
      # Every expression prints something; no answer means GHCi's session
      # ended (its two-minute limit), so the rest of the section is unknown.
      next stats[:ghci_lost] += 1 if !sessions && Rhci::Text.strip(p.text).empty?
      next stats[:unsupported] += 1 if r.status == :unsupported
      next stats[:limit] += 1 if r.status == :limit

      want = Oracle.outcome(p.text)
      ours = STATUS[r.status] || r.status
      if want == :ok && ours == :ok && p.input.start_with?(':t ')
        # Types up to renaming and constraint order (the oracle's rule).
        arg = p.input[3..-1]
        g = p.text.split(' ').join(' ').sub("#{arg} :: ", '')
        o = Rhci::Text.strip(got).split(' ').join(' ').sub("#{arg} :: ", '')
        problems << "#{p.input}\n    GHCi #{g}\n    rhci #{o}" unless Oracle.normalize_type(g) == Oracle.normalize_type(o)
        stats[:types] += 1
      elsif want != ours
        problems << "#{p.input}\n    GHCi #{want}: #{p.text.lines.first.to_s.strip[0, 200]}\n    rhci #{ours}: #{(r.message || got).to_s.lines.first.to_s.strip[0, 200]}"
      elsif want == :ok && Rhci::Text.strip(got) != Rhci::Text.strip(p.text)
        problems << "#{p.input}\n    GHCi: #{p.text.strip[0, 300]}\n    rhci: #{got.strip[0, 300]}"
      elsif want == :runtime
        prefix = p.text[0, p.text.index('*** Exception').to_i]
        problems << "#{p.input}\n    output before the exception: GHCi #{prefix.inspect}, rhci #{got.inspect}" if prefix != got
        g = Oracle.exception_message(p.text)
        o = Oracle.strip_locations(r.message.to_s.lines.first.to_s.strip)
        # Several pending errors: Haskell lets an implementation raise any
        # of them (imprecise exceptions), and GHC's choice comes from its
        # optimiser. Reported, not counted.
        unless Oracle.same_exception?(g, o)
          imprecise << "#{p.input}\n    GHCi raised #{g.inspect}, rhci #{o.inspect}"
        end
      end
      stats[:compared] += 1
    rescue StandardError => e
      problems << "#{p.input}\n    rhci internal error: #{e.class}: #{e.message.lines.first}"
    end
    [problems, stats, imprecise]
  end

  def main(argv)
    seed = (argv[argv.index('--seed') + 1] if argv.include?('--seed')).to_i
    seed = 1 if seed.zero?
    count = (argv.include?('--count') ? argv[argv.index('--count') + 1] : 1000).to_i
    bottoms = (argv.include?('--bottoms') ? argv[argv.index('--bottoms') + 1] : 0).to_f
    sessions = argv.include?('--sessions')
    probes = golden(seed, count, bottoms, sessions)
    sections = probes.map(&:section).uniq
    mruby = argv.include?('--mruby') ? mruby_results(probes) : nil
    total = Hash.new(0)
    all = []
    loose = []
    sections.each do |sec|
      in_sec = probes.select { |p| p.section == sec }
      # A session whose last input got no answer ended early (GHCi's time
      # limit): nothing in it is known.
      next total[:ghci_lost] += in_sec.length if sessions && Rhci::Text.strip(in_sec.last.text).empty?

      problems, stats, imprecise = compare_section(in_sec, mruby ? mruby[sec] : cruby_results(in_sec), sessions: sessions)
      stats.each { |k, v| total[k] += v }
      all.concat(problems)
      loose.concat(imprecise)
    end
    all.each { |p| puts p }
    unless loose.empty?
      puts "-- a different one of several pending exceptions (allowed):"
      loose.each { |p| puts p }
    end
    puts "seed #{seed}: #{total[:compared]} compared, #{all.length} disagreements, #{loose.length} imprecise, " \
         "#{total[:unsupported]} unsupported, #{total[:limit]} over the step budget"
    all.empty?
  end
end

exit(Fuzz.main(ARGV) ? 0 : 1) if __FILE__ == $PROGRAM_NAME
