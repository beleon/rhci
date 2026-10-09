# frozen_string_literal: true

# The simplifier: every round's output must be well scoped (no reference
# to a local binder outside its scope), checked over the whole Prelude and
# a few prompt inputs; and the rules must fire where they should.
class ScopeCheckingSimplify < Rhci::Simplify
  def self.problems
    @problems ||= []
  end

  private

  def dce(e)
    scope(e, {})
    super(e)
  end

  # Fresh local names contain '~'; desugarer locals '%d'. Globals neither.
  def scope(e, bound)
    case e
    when Rhci::Core::Var
      local = e.name.include?('~') || e.name.include?('%d')
      ScopeCheckingSimplify.problems << e.name if local && !bound.key?(e.name)
    when Rhci::Core::App
      scope(e.fn, bound)
      e.args.each { |a| scope(a, bound) }
    when Rhci::Core::Lam
      b = bound.dup
      e.params.each { |p| b[p] = true }
      scope(e.body, b)
    when Rhci::Core::Let
      b = bound.dup
      e.binds.each { |n, _| b[n] = true }
      e.binds.each { |_, r| scope(r, b) }
      scope(e.body, b)
    when Rhci::Core::Case
      scope(e.scrut, bound)
      b = bound.dup
      b[e.binder] = true if e.binder
      e.alts.each do |a|
        bb = b.dup
        a.vars&.each { |v| bb[v] = true if v }
        scope(a.body, bb)
      end
    when Rhci::Core::Con, Rhci::Core::Prim then e.args.each { |a| scope(a, bound) }
    end
  end
end

class ScopeCheckingSession < Rhci::Session
  private

  def simplifier
    ScopeCheckingSimplify.new(@unfoldings, ->(n, d) { specialize(n, d) })
  end
end

RT.suite 'simplifier' do
  RT.test 'every round is well scoped (whole Prelude, some inputs)' do
    ScopeCheckingSimplify.problems.clear
    out = RT::FakeIO.new
    s = ScopeCheckingSession.new(stdout: out, prelude: :source)
    ['let fibs = 0 : 1 : zipWith (+) fibs (tail fibs) in fibs !! 50', 'show (Just "x")',
     'length (filter even (map (*3) [1..100]))', 'f x | x > 0 = 1 | otherwise = 0', 'map f [-1, 1]'].each do |i|
      r = s.eval(i)
      RT.ok r.ok?, "#{i}: #{r.message}"
    end
    RT.eq [], ScopeCheckingSimplify.problems.uniq
    RT.eq "12586269025\n\"Just \\\"x\\\"\"\n50\n[0,1]\n", out.written
  end
end
