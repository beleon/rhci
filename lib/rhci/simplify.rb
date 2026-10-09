# frozen_string_literal: true

module Rhci
  # Core-to-Core simplification between the desugarer and Lower. Every rule
  # preserves call-by-need semantics: only lambdas, atoms and constructor
  # applications are ever duplicated or moved, so no work is repeated or
  # lost, and a `case` that forces an unevaluated scrutinee is never
  # removed.
  #
  # - dead let bindings are dropped;
  # - let-bound lambdas used once, or small, are inlined at calls, and
  #   applied lambdas are beta-reduced (arguments are let-bound, lazily);
  # - case of a known constructor or literal selects the alternative;
  # - a case on a variable that an enclosing case already evaluated (in a
  #   default branch) is merged into that case, which turns the
  #   desugarer's clause-by-clause matching into one case per variable;
  # - a default that the constructor alternatives make unreachable goes.
  #
  # Across definitions, `unfoldings` (name => VM::Cell holding Core) gives
  # the simplified Core of small global functions and of constants
  # (dictionaries are constructor applications), so class methods called
  # at a known instance reduce to that instance's code, and small
  # functions are inlined at saturated calls.
  #
  # Core binder names are unique within a definition (the renamer and the
  # desugarer make them so); inlined copies get fresh names.
  class Simplify
    C = Core

    SMALL = 12          # local lambdas at most this big are inlined at every call
    GLOBAL_SMALL = 24   # global functions at most this big get an unfolding
    ROUNDS = 4

    # specializer: called with (global name, [dictionary Core]); returns
    # the name of that global's specialisation, or nil.
    def initialize(unfoldings = nil, specializer = nil)
      @fresh = 0
      @unfoldings = unfoldings || {}
      @specializer = specializer
      @inlining = {}
    end

    # The printed form of a closed dictionary expression (a memo key).
    def self.key(e)
      e.is_a?(C::Var) ? e.name : "(#{key(e.fn)} #{e.args.map { |a| key(a) }.join(' ')})"
    end

    # The unfolding to record for a global definition's simplified Core,
    # or nil: a small non-recursive function, or a constant.
    def self.unfolding(name, core)
      case core
      when C::Lit then core
      when C::Var then core.name == name ? nil : core
      when C::Con then core.args.all? { |a| a.is_a?(C::Var) || a.is_a?(C::Lit) } ? core : nil
      when C::Lam then new.small_closed?(name, core) ? core : nil
      end
    end

    # Small enough to inline, and not recursive.
    def small_closed?(name, core)
      size(core) <= GLOBAL_SMALL && !occurs?(name, core)
    end

    def run(e)
      ROUNDS.times do
        @changed = false
        @count = Hash.new(0)
        count(e, @count)
        @subst = {}
        @unfold = {}
        @known = {}
        @excluded = {}
        e = simp(e)
        e = dce(e)
        break unless @changed
      end
      e
    end

    private

    def fresh(name)
      @fresh += 1
      base = name.split('~').first
      "#{base}~#{@fresh}"
    end

    # ---- occurrences -------------------------------------------------------

    def count(e, acc)
      case e
      when C::Var then acc[e.name] += 1
      when C::App
        count(e.fn, acc)
        e.args.each { |a| count(a, acc) }
      when C::Lam then count(e.body, acc)
      when C::Let
        e.binds.each { |_, r| count(r, acc) }
        count(e.body, acc)
      when C::Case
        count(e.scrut, acc)
        e.alts.each { |a| count(a.body, acc) }
      when C::Con, C::Prim then e.args.each { |a| count(a, acc) }
      end
    end

    def occurs?(name, e)
      acc = Hash.new(0)
      count(e, acc)
      acc[name].positive?
    end

    def size(e)
      case e
      when C::App then 1 + size(e.fn) + e.args.sum { |a| size(a) }
      when C::Lam then 1 + size(e.body)
      when C::Let then 1 + e.binds.sum { |_, r| size(r) } + size(e.body)
      when C::Case then 1 + size(e.scrut) + e.alts.sum { |a| size(a.body) }
      when C::Con, C::Prim then 1 + e.args.length
      else 1
      end
    end

    # ---- the simplifier ----------------------------------------------------------

    # What may be substituted for a variable (primitive operands must stay
    # variables or literals).
    def atom?(e)
      e.is_a?(C::Var) || e.is_a?(C::Lit)
    end

    def simp(e)
      case e
      when C::Var then resolve(e)
      when C::Lit, C::Str then e
      when C::Lam then C::Lam.new(e.params, simp(e.body))
      when C::App then simp_app(e)
      when C::Let then simp_let(e)
      when C::Case then simp_case(e)
      when C::Con then C::Con.new(e.con, e.args.map { |a| simp(a) })
      when C::Prim then simp_prim(e)
      else raise "simplify: unexpected #{e.class}"
      end
    end

    B = VM::Builtins

    # Integer primitives on literals, computed now (exactly as the machine
    # would; division is left alone, it may raise).
    FOLD = {
      integerAdd: ->(a, b) { a + b }, integerSub: ->(a, b) { a - b }, integerMul: ->(a, b) { a * b },
      intAdd: ->(a, b) { Num.wrap_int(a + b) }, intSub: ->(a, b) { Num.wrap_int(a - b) },
      intMul: ->(a, b) { Num.wrap_int(a * b) },
      integerEq: ->(a, b) { a == b }, integerLt: ->(a, b) { a < b }, integerLe: ->(a, b) { a <= b },
      integerGt: ->(a, b) { a > b }, integerGe: ->(a, b) { a >= b }, charEq: ->(a, b) { a == b },
      integerToInt: ->(a) { Num.wrap_int(a) }, intToInteger: ->(a) { a }, ord: ->(a) { a }
    }.freeze

    def simp_prim(e)
      args = e.args.map { |a| simp(a) }
      f = FOLD[e.op]
      if f && args.all? { |a| a.is_a?(C::Lit) && a.value.is_a?(Integer) }
        @changed = true
        r = f.call(*args.map(&:value))
        return C::Lit.new(r) if r.is_a?(Integer)

        return C::Con.new(r ? B::TRUE : B::FALSE, [])
      end
      C::Prim.new(e.op, args)
    end

    def resolve(v)
      seen = 0
      while v.is_a?(C::Var)
        if @subst.key?(v.name)
          v = @subst[v.name]
        else
          u = global(v.name)
          break unless u.is_a?(C::Lit) || u.is_a?(C::Var)

          v = u
        end
        seen += 1
        raise 'simplify: substitution cycle' if seen > 1000
      end
      v
    end

    def global(name)
      cell = @unfoldings[name]
      cell&.value
    end

    def simp_app(e)
      raw_fn = e.fn
      raw_args = e.args
      while raw_fn.is_a?(C::App)
        raw_args = raw_fn.args + raw_args
        raw_fn = raw_fn.fn
      end
      fn = simp(raw_fn)
      fn, raw_args = specialize(fn, raw_args) if fn.is_a?(C::Var) && @specializer
      args = raw_args.map { |a| simp(a) }
      if fn.is_a?(C::App)
        args = fn.args + args
        fn = fn.fn
      end
      return push_app(fn, args) if fn.is_a?(C::Case) || fn.is_a?(C::Let)
      if fn.is_a?(C::Var) && !@inlining[fn.name]
        lam = global(fn.name)
        if lam.is_a?(C::Lam) && args.length >= lam.params.length && worth_inlining?(lam, args)
          @changed = true
          @inlining[fn.name] = true
          begin
            return simp(beta(copy_fresh(lam), args))
          ensure
            @inlining.delete(fn.name)
          end
        end
      end
      if fn.is_a?(C::Var) && @unfold.key?(fn.name)
        @changed = true
        # Always a fresh copy: the original binding stays until the dead
        # code pass, and its binders must not be shared with the copy.
        return simp(beta(copy_fresh(@unfold[fn.name]), args))
      end
      if fn.is_a?(C::Lam)
        @changed = true
        return simp(beta(fn, args))
      end
      return fn if args.empty?

      C::App.new(fn, args)
    end

    # A field selector (a class method or superclass selector) gains
    # nothing from inlining unless its argument is known: the inlined case
    # would just replace the call.
    def worth_inlining?(lam, args)
      body = lam.body
      return true unless body.is_a?(C::Case) && body.scrut.is_a?(C::Var) && body.alts.length == 1

      alt = body.alts[0]
      return true unless alt.kind == :con && alt.body.is_a?(C::Var) && alt.vars.include?(alt.body.name)

      i = lam.params.index(body.scrut.name)
      i.nil? || known_value?(args[i])
    end

    def known_value?(a)
      case a
      when C::Lit, C::Con, C::Lam then true
      when C::Var then @known.key?(a.name) || global(a.name).is_a?(C::Con)
      else false
      end
    end

    # f d1 .. dk args, where the d's are known dictionaries and f is not
    # small enough to inline: call f's specialisation to those dictionaries
    # instead (made, once per session, by the specializer).
    def specialize(fn, raw_args)
      return [fn, raw_args] if global(fn.name)

      dicts = []
      while dicts.length < raw_args.length
        d = dict_expr(raw_args[dicts.length])
        break unless d

        dicts << d
      end
      return [fn, raw_args] if dicts.empty?

      spec = @specializer.call(fn.name, dicts)
      return [fn, raw_args] unless spec

      @changed = true
      [C::Var.new(spec), raw_args[dicts.length..-1]]
    end

    # A closed expression for a known dictionary: an instance constant, or
    # an instance function applied to known dictionaries; else nil.
    def dict_expr(a, depth = 0)
      return nil if depth > 3

      case a
      when C::Var
        r = resolve(a)
        return nil unless r.is_a?(C::Var)

        g = global(r.name)
        g.is_a?(C::Con) && g.con.name.start_with?('D:') ? r : nil
      when C::App
        f = a.fn.is_a?(C::Var) ? resolve(a.fn) : nil
        return nil unless f.is_a?(C::Var) && f.name.start_with?('$f')

        args = a.args.map { |x| dict_expr(x, depth + 1) }
        args.all? ? C::App.new(f, args) : nil
      end
    end

    # (case s of alts) args => case s of { p -> body args }, and
    # (let bs in e) args => let bs in e args: evaluating the application
    # evaluates the function first, so strictness is unchanged; non-atomic
    # arguments are let-bound once, outside, so no work is duplicated.
    def push_app(fn, args)
      @changed = true
      binds = []
      args = args.map do |a|
        next a if atom?(a)

        t = fresh('arg')
        binds << [t, a]
        C::Var.new(t)
      end
      inner = into(fn, args)
      binds.empty? ? inner : C::Let.new(binds, inner)
    end

    def into(fn, args)
      case fn
      when C::Case
        alts = fn.alts.map { |a| C::Alt.new(a.kind, a.key, a.vars, into(a.body, args)) }
        C::Case.new(fn.scrut, fn.binder, alts)
      when C::Let then C::Let.new(fn.binds, into(fn.body, args))
      when C::App then C::App.new(fn.fn, fn.args + args)
      else C::App.new(fn, args)
      end
    end

    # (\ps -> body) args, with arguments let-bound so they stay lazy.
    def beta(lam, args)
      ps = lam.params
      n = [ps.length, args.length].min
      binds = []
      n.times do |i|
        if atom?(args[i])
          @subst[ps[i]] = args[i]
        else
          binds << [ps[i], args[i]]
        end
      end
      body = lam.body
      body = C::Lam.new(ps[n..-1], body) if ps.length > n
      body = C::Let.new(binds, body) unless binds.empty?
      body = C::App.new(body, args[n..-1]) if args.length > n
      body
    end

    def simp_let(e)
      keep = []
      e.binds.each do |name, rhs|
        if atom?(rhs) && !(rhs.is_a?(C::Var) && rhs.name == name)
          r = simp(rhs)
          unless r.is_a?(C::Var) && r.name == name
            @subst[name] = r
            @changed = true
            next
          end
        end
        if rhs.is_a?(C::Lam) && (@count[name] == 1 || size(rhs) <= SMALL) && !occurs?(name, rhs)
          @unfold[name] = rhs
        end
        keep << [name, rhs]
      end
      binds = []
      keep.each do |name, rhs|
        if rhs.is_a?(C::Con) && !rhs.args.empty?
          args = rhs.args.map do |a|
            a = simp(a)
            next a if atom?(a)

            t = fresh("#{name}f")
            binds << [t, a]
            C::Var.new(t)
          end
          @known[name] = [:con, rhs.con, args]
          binds << [name, C::Con.new(rhs.con, args)]
        else
          binds << [name, simp(rhs)]
        end
      end
      body = simp(e.body)
      return body if binds.empty?

      strict_let(binds, body) || C::Let.new(binds, body)
    end

    # let x = rhs in case x of b -> alts, with x used nowhere else: the case
    # forces x at once, so rhs can be evaluated directly (no thunk).
    def strict_let(binds, body)
      return nil unless binds.length == 1 && body.is_a?(C::Case) && body.scrut.is_a?(C::Var)

      name, rhs = binds[0]
      return nil unless body.scrut.name == name && !rhs.is_a?(C::Lam) && !rhs.is_a?(C::Con)

      acc = Hash.new(0)
      count(body, acc)
      count(rhs, acc)
      return nil unless acc[name] == 1

      @changed = true
      C::Case.new(rhs, body.binder, body.alts)
    end

    def con_alt(alts, con)
      alts.find { |a| a.kind == :con && a.key.equal?(con) } || alts.find { |a| a.kind == :default }
    end

    def lit_alt(alts, value)
      alts.find { |a| a.kind == :lit && a.key == value } || alts.find { |a| a.kind == :default }
    end

    def simp_case(e)
      simp_case_of(e, simp(e.scrut))
    end

    def simp_case_of(e, s)
      if s.is_a?(C::Let)
        # case (let bs in x) of alts => let bs in case x of alts
        @changed = true
        return C::Let.new(s.binds, simp_case_of(e, s.body))
      end
      if s.is_a?(C::Case) && s.alts.length == 1
        # case (case x of p -> y) of alts => case x of p -> case y of alts
        # (one inner alternative, so nothing is duplicated).
        @changed = true
        a = s.alts[0]
        inner = simp_case_of(e, a.body)
        return C::Case.new(s.scrut, s.binder, [C::Alt.new(a.kind, a.key, a.vars, inner)])
      end
      if s.is_a?(C::Con) && !s.args.empty?
        # Bind the fields, then it is a case of a known variable.
        @changed = true
        t = fresh('scrut')
        return simp(C::Let.new([[t, s]], C::Case.new(C::Var.new(t), e.binder, e.alts)))
      end
      fact = case s
             when C::Lit then [:lit, s.value]
             when C::Con then [:con, s.con, []]
             when C::Lam then [:whnf]
             when C::Var then @known[s.name]
             end
      chosen = select(e, s, fact)
      return chosen if chosen

      if fact.nil? && s.is_a?(C::Var) && (g = global(s.name)).is_a?(C::Con)
        # A global constant (a dictionary, `otherwise`): the alternative is
        # known, but the binder must still be bound by evaluating it (a
        # global constant is a top-level thunk, never a primitive operand).
        alt = con_alt(e.alts, g.con)
        if alt
          @changed = true
          alt.vars.each_with_index { |v, i| @subst[v] = g.args[i] if v && v != '_' }
          body = simp(alt.body)
          return body unless e.binder

          return C::Case.new(s, e.binder, [C::Alt.new(:default, nil, [], body)])
        end
      end

      general_case(e, s, fact)
    end

    # The alternative a known scrutinee selects, simplified; nil if unknown.
    def select(e, s, fact)
      return nil if fact.nil?

      alt = case fact[0]
            when :lit then lit_alt(e.alts, fact[1])
            when :con then con_alt(e.alts, fact[1])
            else
              d = e.alts.find { |a| a.kind == :default }
              e.alts.length == 1 && d ? d : nil
            end
      return nil if alt.nil?

      @changed = true
      bind = nil
      if e.binder
        # A value that is not an atom (a nullary constructor, a lambda) is
        # let-bound: primitive operands must stay atoms.
        atom?(s) ? @subst[e.binder] = s : bind = [e.binder, s]
      end
      if alt.kind == :con
        alt.vars.each_with_index { |v, i| @subst[v] = fact[2][i] if v && v != '_' }
      end
      body = simp(alt.body)
      bind ? C::Let.new([bind], body) : body
    end

    def general_case(e, s, fact)
      sv = s.is_a?(C::Var) ? s.name : nil
      binder = e.binder
      swap = nil
      if sv && fact
        # Already evaluated, and sv holds the value itself (a case binder
        # or a let-bound constructor): no binder needed.
        @subst[binder] = s if binder
        binder = nil
        key = sv
      elsif sv
        # Binder swap: inside the alternatives the scrutinee is referred to
        # through the binder, which holds the evaluated value (sv may be a
        # thunk, which primitives must not see).
        binder ||= fresh('wild')
        swap = sv
        key = binder
      end
      excluded = key ? (@excluded[key] || []) : []
      alts = []
      e.alts.each do |a|
        next if a.kind == :con && excluded.include?(a.key.tag)

        alts << simp_alt(a, key, swap, e.alts)
      end
      alts = merge_default(alts, key)
      cons = alts.select { |a| a.kind == :con }
      unless cons.empty?
        covered = cons.map { |a| a.key.tag } + excluded
        if cons[0].key.siblings.all? { |c| covered.include?(c.tag) }
          alts = alts.reject { |a| a.kind == :default }
        end
      end
      C::Case.new(s, binder, alts)
    end

    # key: the variable facts are recorded under; swap: a scrutinee variable
    # that the alternative refers to through key instead.
    def simp_alt(a, key, swap, all)
      facts = []
      case a.kind
      when :con
        vars = a.vars.map { |v| v.nil? || v == '_' ? fresh('fld') : v }
        fact = [:con, a.key, vars.map { |v| C::Var.new(v) }]
        a = C::Alt.new(:con, a.key, vars, a.body)
      when :lit then fact = [:lit, a.key]
      else
        fact = [:whnf]
        tags = all.select { |x| x.kind == :con }.map { |x| x.key.tag }
        facts << [:excluded, key, tags] if key
      end
      facts << [:known, key, fact] if key
      saved = facts.map { |kind, name, _| [kind, name, kind == :known ? @known[name] : @excluded[name]] }
      facts.each do |kind, name, f|
        if kind == :known then @known[name] = f
        else @excluded[name] = (@excluded[name] || []) + f
        end
      end
      @subst[swap] = C::Var.new(key) if swap
      body = simp(a.body)
      @subst.delete(swap) if swap
      saved.each do |kind, name, old|
        table = kind == :known ? @known : @excluded
        old.nil? ? table.delete(name) : table[name] = old
      end
      C::Alt.new(a.kind, a.key, a.vars, body)
    end

    # case x of { alts; _ -> case x of { alts2 } } => case x of { alts; alts2 }
    def merge_default(alts, sv)
      return alts unless sv

      d = alts.find { |a| a.kind == :default }
      return alts unless d && d.body.is_a?(C::Case) && d.body.scrut.is_a?(C::Var) &&
                         d.body.scrut.name == sv && d.body.binder.nil?

      @changed = true
      out = alts.reject { |a| a.kind == :default }
      d.body.alts.each do |a|
        dup = out.any? do |b|
          b.kind == a.kind && (a.kind == :default || (a.kind == :con ? b.key.equal?(a.key) : b.key == a.key))
        end
        out << a unless dup
      end
      out
    end

    # ---- copies with fresh binders ----------------------------------------------

    def copy_fresh(e, ren = {})
      case e
      when C::Var then ren.key?(e.name) ? C::Var.new(ren[e.name]) : e
      when C::Lit, C::Str then e
      when C::App then C::App.new(copy_fresh(e.fn, ren), e.args.map { |a| copy_fresh(a, ren) })
      when C::Lam
        ps = e.params.map { |p| ren[p] = fresh(p) }
        C::Lam.new(ps, copy_fresh(e.body, ren))
      when C::Let
        e.binds.each { |n, _| ren[n] = fresh(n) }
        binds = e.binds.map { |n, r| [ren[n], copy_fresh(r, ren)] }
        C::Let.new(binds, copy_fresh(e.body, ren))
      when C::Case
        scrut = copy_fresh(e.scrut, ren)
        b = e.binder ? (ren[e.binder] = fresh(e.binder)) : nil
        alts = e.alts.map do |a|
          vars = a.kind == :con ? a.vars.map { |v| v.nil? || v == '_' ? v : (ren[v] = fresh(v)) } : a.vars
          C::Alt.new(a.kind, a.key, vars, copy_fresh(a.body, ren))
        end
        C::Case.new(scrut, b, alts)
      when C::Con then C::Con.new(e.con, e.args.map { |a| copy_fresh(a, ren) })
      when C::Prim then C::Prim.new(e.op, e.args.map { |a| copy_fresh(a, ren) })
      else raise "simplify: unexpected #{e.class}"
      end
    end

    # ---- dead code ----------------------------------------------------------------

    # Drops unused let bindings, case binders and field variables.
    def dce(e)
      loop do
        acc = Hash.new(0)
        count(e, acc)
        @dropped = false
        e = prune(e, acc)
        return e unless @dropped
      end
    end

    def prune(e, acc)
      case e
      when C::App then C::App.new(prune(e.fn, acc), e.args.map { |a| prune(a, acc) })
      when C::Lam then C::Lam.new(e.params, prune(e.body, acc))
      when C::Let
        binds = []
        e.binds.each do |n, r|
          if acc[n].zero?
            @dropped = true
            @changed = true
          else
            binds << [n, prune(r, acc)]
          end
        end
        body = prune(e.body, acc)
        binds.empty? ? body : C::Let.new(binds, body)
      when C::Case
        b = e.binder && acc[e.binder].positive? ? e.binder : nil
        if b.nil? && e.alts.length == 1 && e.alts[0].kind == :default && e.scrut.is_a?(C::Var) &&
           global(e.scrut.name).is_a?(C::Con)
          @dropped = true # forcing a global constant has no effect
          return prune(e.alts[0].body, acc)
        end
        alts = e.alts.map do |a|
          vars = a.kind == :con ? a.vars.map { |v| v && acc[v].positive? ? v : nil } : a.vars
          C::Alt.new(a.kind, a.key, vars, prune(a.body, acc))
        end
        C::Case.new(prune(e.scrut, acc), b, alts)
      when C::Con then C::Con.new(e.con, e.args.map { |a| prune(a, acc) })
      when C::Prim then C::Prim.new(e.op, e.args.map { |a| prune(a, acc) })
      else e
      end
    end
  end
end
