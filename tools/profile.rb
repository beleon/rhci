# frozen_string_literal: true

# Machine steps per Prelude/global function for one expression (CRuby).
# A development aid: patches the machine's loop to count steps per code
# node, then attributes nodes to the global whose code contains them.
#   ruby tools/profile.rb 'sum [1..100000]' [TOP]
ROOT = File.expand_path('..', __dir__)
require File.join(ROOT, 'lib', 'rhci')

src = File.read(File.join(ROOT, 'lib', 'rhci', 'vm.rb'))
run_start = src.index('      def run(expr, locals, env, base = @stack.length)')
run_end = src.index("      # Atom values, without a block")
run_src = src[run_start...run_end].sub("              op = expr.op\n", "              PROF[expr] += 1\n              op = expr.op\n")
PROF = Hash.new(0).compare_by_identity
eval("module Rhci\nmodule VM\nclass Machine\n#{run_src}\nprivate :run\nend\nend\nend") # rubocop:disable Security/Eval

owner = {}.compare_by_identity
walk = lambda do |x, name|
  return if x.nil? || owner.key?(x)

  case x
  when Rhci::VM::LamCode, Rhci::VM::ThunkCode then walk.call(x.body, name)
  when Rhci::VM::XLet
    owner[x] = name
    x.binds.each { |_, kind, p| walk.call(p, name) if %i[thunk fun].include?(kind) }
    walk.call(x.body, name)
  when Rhci::VM::XCase
    owner[x] = name
    walk.call(x.scrut, name)
    x.con_alts&.each { |a| walk.call(a[1], name) if a }
    x.lit_alts&.each_value { |b| walk.call(b, name) }
    walk.call(x.default, name)
  when Rhci::VM::XApp
    owner[x] = name
    walk.call(x.fn, name)
  else owner[x] = name
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
