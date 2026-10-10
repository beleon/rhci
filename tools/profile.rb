# frozen_string_literal: true

# Machine steps per Prelude/global function for one expression (CRuby).
# A development aid: patches the machine's loop to count steps per code
# node, then attributes nodes to the global whose code contains them.
#   ruby tools/profile.rb 'sum [1..100000]' [TOP]
ROOT = File.expand_path('..', __dir__)
require File.join(ROOT, 'lib', 'rhci')

src = File.read(File.join(ROOT, 'lib', 'rhci', 'vm.rb'))
run_start = src.index('      def run_ruby(expr, locals, env, base)')
run_end = src.index("      # Atom values, without a block")
run_src = src[run_start...run_end].sub("              op = expr[0]\n", "              PROF[expr] += 1\n              op = expr[0]\n")
PROF = Hash.new(0).compare_by_identity
eval("module Rhci\nmodule VM\nclass Machine\n#{run_src}\nprivate :run_ruby\nend\nend\nend") # rubocop:disable Security/Eval

owner = {}.compare_by_identity
# Code is plain Arrays (see vm.rb): bodies [arity, captures, nlocals,
# body, name] and nodes [op, ...].
walk = lambda do |x, name|
  return unless x.is_a?(Array) && !owner.key?(x)

  owner[x] = name
  if x.length == 5 && x[1].is_a?(Array) && x[2].is_a?(Integer)
    walk.call(x[Rhci::VM::CODE_BODY], name) # a code body
  else
    case x[0]
    when Rhci::VM::OP_APP then walk.call(x[1], name)
    when Rhci::VM::OP_LET
      x[1].each { |_, kind, p| walk.call(p[Rhci::VM::CODE_BODY], name) if %i[thunk fun].include?(kind) }
      walk.call(x[2], name)
    when Rhci::VM::OP_CASE
      walk.call(x[1], name)
      x[3]&.each { |a| walk.call(a[1], name) if a }
      x[4]&.each_value { |b| walk.call(b, name) }
      walk.call(x[5], name)
    end
  end
end

s = Rhci::Session.new(stdout: File.open(File::NULL, 'w'))
s.eval('1')
s.instance_variable_get(:@globals).each do |name, cell|
  v = cell.value
  if v.is_a?(Rhci::VM::Fun) then walk.call(v[0], name)
  elsif v.is_a?(Rhci::VM::Thunk) && v[0] == :pending then walk.call(v[1], name)
  end
end
PROF.clear
r = s.eval(ARGV[0])
abort "#{r.status}: #{r.message}" unless r.ok?
total = PROF.values.sum
by = Hash.new(0)
PROF.each { |node, n| by[owner[node] || '(expression)'] += n }
puts "#{total} steps"
by.sort_by { |_, n| -n }.first((ARGV[1] || 25).to_i).each do |name, n|
  printf("%10d %5.1f%%  %s\n", n, 100.0 * n / total, name) # lint:ok (CRuby-only tool)
end
