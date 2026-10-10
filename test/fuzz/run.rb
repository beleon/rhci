# frozen_string_literal: true

# Differential fuzzing: random expressions (test/fuzz/gen.rb) evaluated by
# real GHCi (the oracle's podman image) and by rhci, compared under the
# oracle's rules -- values exactly, errors by kind, and the output printed
# before an exception exactly.
#
#   ruby test/fuzz/run.rb [--seed N] [--count N] [--bottoms P]
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

module Fuzz
  ROOT = File.expand_path('../..', __dir__)
  WORK = File.join(ROOT, 'build', 'fuzz')
  PER_SECTION = 100
  IMPORTS = ['import Data.List', 'import Data.Char', 'import Data.Maybe', 'import qualified Data.Map as M',
             'import qualified Data.Set as S'].freeze

  STATUS = { ok: :ok, parse_error: :parse, scope_error: :scope, compile_error: :compile,
             exception: :runtime }.freeze

  module_function

  def probes(seed, count, bottoms)
    gen = Gen.new(seed, bottoms: bottoms)
    Array.new(count) { gen.probe }
  end

  def write_probes(path, list)
    out = []
    list.each_slice(PER_SECTION).with_index do |chunk, i|
      out << "## fuzz #{i + 1}" << ''
      out.concat(IMPORTS)
      out.concat(Gen::DECLS)
      out.concat(chunk)
      out << ''
    end
    File.write(path, out.join("\n"))
  end

  def golden(seed, count, bottoms)
    FileUtils.mkdir_p(WORK)
    base = File.join(WORK, "s#{seed}-n#{count}#{bottoms.positive? ? "-b#{bottoms}" : ''}")
    unless File.exist?("#{base}.golden")
      write_probes("#{base}.probes", probes(seed, count, bottoms))
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

  # [kind, detail] for each disagreement in one section.
  def compare_section(probes)
    out = Sink.new
    s = Rhci::Session.new(stdout: out, stderr: out, limits: { steps: 5_000_000 })
    problems = []
    imprecise = []
    stats = Hash.new(0)
    probes.each do |p|
      before = out.text.length
      r = s.eval(p.input)
      got = out.text[before..-1]
      next stats[:import] += 1 if p.input.start_with?('import ', 'data ', 'infixl ')
      # Every expression prints something; no answer means GHCi's session
      # ended (its two-minute limit), so the rest of the section is unknown.
      next stats[:ghci_lost] += 1 if Rhci::Text.strip(p.text).empty?
      next stats[:unsupported] += 1 if r.status == :unsupported
      next stats[:limit] += 1 if r.status == :limit

      want = Oracle.outcome(p.text)
      ours = STATUS[r.status] || r.status
      if want != ours
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
    probes = golden(seed, count, bottoms)
    sections = probes.map(&:section).uniq
    total = Hash.new(0)
    all = []
    loose = []
    sections.each do |sec|
      problems, stats, imprecise = compare_section(probes.select { |p| p.section == sec })
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
