# frozen_string_literal: true

# Runtime benchmarks (bench/programs.txt): wall time of `rhci -c EXPR` on
# the mruby binary, and steps plus in-process time on CRuby. Speed is best
# effort; this exists so that changes are judged by numbers.
#   ruby tools/bench_runtime.rb [NAME...]
ROOT = File.expand_path('..', __dir__)
require File.join(ROOT, 'lib', 'rhci')

MRUBY_EXE = File.join(ROOT, 'build', 'rhci', 'bin', 'rhci')

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

programs = File.readlines(File.join(ROOT, 'bench', 'programs.txt'), chomp: true)
                .reject { |l| l.start_with?('#') || l.strip.empty? }
                .map { |l| l.split('|', 2).map(&:strip) }
programs = programs.select { |n, _| ARGV.include?(n) } unless ARGV.empty?

session = Rhci::Session.new(stdout: File.open(File::NULL, 'w'))
session.eval('1') # load the Prelude outside the measurement
machine = session.instance_variable_get(:@machine)
printf("%-10s %12s %10s %10s  %s\n", 'program', 'steps', 'CRuby s', 'mruby s', 'result') # lint:ok (CRuby-only tool)
programs.each do |name, expr|
  out = Rhci::Session.new(stdout: (buf = +''; o = Object.new; o.define_singleton_method(:write) { |s| buf << s; s.length }; o.define_singleton_method(:flush) { o }; o))
  out.eval('1')
  buf.clear
  m = out.instance_variable_get(:@machine)
  s0 = m.steps
  t0 = now
  r = out.eval(expr)
  ruby_t = now - t0
  steps = m.steps - s0
  t0 = now
  if ENV['NO_MRUBY']
    mres = buf
  else
    mres = IO.popen([MRUBY_EXE, '-c', expr], err: [:child, :out], &:read)
  end
  mruby_t = now - t0
  result = r.ok? ? buf.strip : "#{r.status}: #{r.message}"
  result += " (mruby: #{mres.strip})" if mres.strip != buf.strip
  printf("%-10s %12d %10.2f %10.2f  %s\n", name, steps, ruby_t, mruby_t, result[0, 60]) # lint:ok (CRuby-only tool)
end
