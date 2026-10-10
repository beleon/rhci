# frozen_string_literal: true

module Rhci
  # Renamed (and type-checked) AST -> Core.
  #
  # Pattern matching: clauses are tried top to bottom, patterns left to
  # right, exactly as the Report specifies, by compiling each clause with a
  # failure continuation -- a lazily bound thunk that tries the remaining
  # clauses. Pattern variables are substituted (no lets); lazy patterns and
  # pattern bindings become selector thunks; newtypes are erased.
  class Desugar
    include AST
    C = Core
    B = VM::Builtins

    def initialize(env, source = '<interactive>')
      @env = env
      @source = source
      @subst = {}
      @n = 0
    end

    # Global definitions ([[core_name, Core], ...]) for a renamed top-level
    # input, plus the Core of its expression (or nil).
    def top(rtop)
      @new_values = rtop.values
      @new_types = rtop.types
      defs = []
      rtop.tyinfos.each { |ti| defs.concat(type_defs(ti)) unless ti.synonym }
      rtop.classes.each { |ci| defs.concat(class_defs(ci)) }
      rtop.groups.each { |scc| defs.concat(scc_defs(scc)) }
      rtop.instances.each { |inst| defs.concat(instance_defs(inst)) }
      [defs, rtop.expr ? expr(rtop.expr) : nil]
    end

    def expression(e)
      expr(e)
    end

    # show applied to arg, with the given Show evidence.
    def show_call(ev, arg)
      C::App.new(method_var('Show', 'show'), [ev_core(ev), arg])
    end

    # Core that matches value `var` against `pat`, then evaluates `success`.
    def match_value(var, pat, success, fail)
      mp([[var, pat]], -> { success }, fail)
    end

    # Match var against pat and return the value pat binds to name n
    # (a `pat <- io` binding at the prompt).
    def match_binding(var, pat, n, fail)
      mp([[var, pat]], -> { var(core_name(n)) }, fail)
    end

    private

    def fresh(hint = 'ds')
      @n += 1
      "#{hint}%d#{@n}"
    end

    def var(name)
      C::Var.new(name)
    end

    # A Prelude-internal name (pending while the Prelude itself compiles).
    def internal(str)
      (@new_values && @new_values[str]) || @env.internal[str] || @env.values[str] ||
        raise("desugar: the Prelude lacks #{str}")
    end

    def core_name(n)
      @subst[n.core] || n.core
    end

    def error_core(tok, msg)
      text = tok ? "#{@source}:#{tok.line}:#{tok.col}: #{msg}" : msg
      v = fresh('msg')
      C::Let.new([[v, C::Str.new(text.codepoints)]], C::Prim.new(:raise, [var(v)]))
    end

    # ---- top-level definitions --------------------------------------------------

    # Field selectors of a data type.
    def type_defs(ti)
      defs = []
      fields = {}
      ti.cons.each { |c| (c.fields || []).each_with_index { |f, i| (fields[f] ||= []) << [c, i] } }
      fields.each do |f, uses|
        r = fresh('r')
        body = if ti.newtype
                 var(r)
               else
                 alts = uses.map do |c, i|
                   vs = Array.new(c.con.arity) { fresh('f') }
                   C::Alt.new(:con, c.con, vs, var(vs[i]))
                 end
                 alts << C::Alt.new(:default, nil, [], error_core(nil, "No match in record selector #{f.str}"))
                 C::Case.new(var(r), nil, alts)
               end
        defs << [f.core, C::Lam.new([r], body)]
      end
      defs
    end

    def bind_defs(b)
      case b.kind
      when :prim
        n = b.name
        ps = Array.new(n.prim_arity) { fresh('p') }
        [[n.core, n.prim_arity.zero? ? prim_call(n.prim, []) : C::Lam.new(ps, prim_call(n.prim, ps.map { |p| var(p) }))]]
      when :fun
        body = fun_body(b)
        [[b.name.core, b.signed && !b.dicts.empty? ? C::Lam.new(b.dicts.map { |_, d| d }, body) : body]]
      else pattern_binding(b)
      end
    end

    # A dependency group. When the checker abstracted it over dictionaries,
    # each binding becomes `\dicts -> letrec <group, monomorphic> in it`:
    # the dictionary lambdas wrap the whole recursive knot, so recursion
    # inside it shares (fibs = 0 : 1 : zipWith (+) fibs (tail fibs)).
    def scc_defs(scc)
      dicts = scc.find { |b| !b.signed }&.dicts || []
      return scc.flat_map { |b| bind_defs(b) } if dicts.empty? || scc.all?(&:signed)

      members = scc.reject(&:signed).flat_map(&:names)
      saved = {}
      members.each do |n|
        saved[n.core] = @subst[n.core]
        @subst[n.core] = "#{n.core}%mono"
      end
      inner = scc.reject(&:signed).flat_map { |b| bind_defs(b) }
      inner = inner.map { |name, core| [@subst[name] || name, core] }
      members.each { |n| saved[n.core].nil? ? @subst.delete(n.core) : @subst[n.core] = saved[n.core] }
      params = dicts.map { |_, d| d }
      out = members.map { |n| [n.core, C::Lam.new(params, C::Let.new(inner, var("#{n.core}%mono")))] }
      out + scc.select(&:signed).flat_map { |b| bind_defs(b) }
    end

    # ---- classes and instances ---------------------------------------------------

    # Method and superclass selectors, and default methods.
    def class_defs(ci)
      defs = []
      con = ci.dict_con
      n = con.arity
      field = lambda do |i|
        d = fresh('d')
        vs = Array.new(n) { fresh('f') }
        C::Lam.new([d], C::Case.new(var(d), nil, [C::Alt.new(:con, con, vs, var(vs[i]))]))
      end
      ci.supers.each_index { |i| defs << [super_selector(ci, i), field.call(i)] }
      ci.methods.each_with_index { |m, i| defs << [m.core, field.call(ci.supers.length + i)] }
      ci.defaults.each_value { |b| defs.concat(bind_defs(b)) }
      defs
    end

    def super_selector(ci, i)
      "sc%#{ci.name.core}%#{i}"
    end

    # Method implementations, and the dictionary: a value, or a function of
    # the instance context's dictionaries.
    def instance_defs(inst)
      ci = inst.klass
      defs = []
      inst.binds.each_value { |b| defs.concat(bind_defs(b)) }
      ctx = inst.context_dicts
      self_name = ctx.empty? ? inst.dict_name.core : fresh('self')
      fields = inst.super_evs.map { |ev| ev_core(ev) }
      ci.methods.each do |m|
        b = inst.binds[m]
        fields << if b
                    ctx.empty? ? var(b.name.core) : C::App.new(var(b.name.core), ctx.map { |c| var(c) })
                  elsif (dm = ci.defaults[m])
                    C::App.new(var(dm.name.core), [var(self_name)])
                  else
                    error_core(inst.tok, "No instance nor default method for class operation #{m.str}")
                  end
      end
      dict = C::Con.new(ci.dict_con, fields)
      defs << if ctx.empty?
                [inst.dict_name.core, dict]
              else
                [inst.dict_name.core, C::Lam.new(ctx, C::Let.new([[self_name, dict]], var(self_name)))]
              end
      defs
    end

    # ---- evidence ----------------------------------------------------------------------

    def ev_core(ev)
      sol = ev.solution
      raise "desugar: unsolved constraint #{ev.klass.name.str}" unless sol

      case sol[0]
      when :param then var(sol[1])
      when :same then ev_core(sol[1])
      when :inst
        inst = sol[1]
        subs = sol[2]
        subs.empty? ? var(inst.dict_name.core) : C::App.new(var(inst.dict_name.core), subs.map { |e| ev_core(e) })
      when :super
        d = ev_core(sol[1])
        k = sol[1].klass
        sol[2].each do |i|
          d = C::App.new(var(super_selector(k, i)), [d])
          k = k.supers[i]
        end
        d
      end
    end

    def evidence(node)
      (node.ev || []).map { |e| ev_core(e) }
    end

    # A method occurrence whose class constraint was solved by an instance
    # that implements the method: [implementation RBind, the dictionaries to
    # pass it (the instance context's, then the method's own)]. The
    # dictionary is then never built or searched at run time.
    def known_method(node)
      m = node.ref
      return nil unless m.is_a?(Name) && m.method_of && node.ev && !node.ev.empty?

      sol = node.ev[0].solution
      sol = sol[1].solution while sol && sol[0] == :same
      return nil unless sol && sol[0] == :inst

      b = sol[1].binds[m]
      return nil unless b

      [b, sol[2].map { |e| ev_core(e) } + node.ev[1..-1].map { |e| ev_core(e) }]
    end

    # The instance an Ev was solved by (following :same), or nil.
    def solved_instance(ev)
      sol = ev.solution
      sol = sol[1].solution while sol && sol[0] == :same
      sol && sol[0] == :inst ? sol[1] : nil
    end

    def method_var(class_str, method_str)
      n = (@new_types && @new_types[class_str]) || @env.types[class_str]
      raise "desugar: the Prelude lacks class #{class_str}" unless n && n.kind == :class

      m = n.klass.methods.find { |x| x.str == method_str }
      raise "desugar: class #{class_str} lacks #{method_str}" unless m

      var(m.core)
    end

    def head_key(inst)
      inst&.head&.key
    end

    # A primitive applied to all its arguments. Arguments are forced first
    # (primitives see evaluated values), except for `raise` (its message is
    # rendered lazily) and `seq` (strict in the first only).
    def prim_call(op, args)
      case op
      when :seq then C::Case.new(args[0], nil, [C::Alt.new(:default, nil, [], args[1])])
      when :raise
        return C::Prim.new(:raise, args) if args[0].is_a?(C::Var)

        v = fresh
        C::Let.new([[v, args[0]]], C::Prim.new(:raise, [var(v)]))
      else
        vs = args.map { fresh('a') }
        body = C::Prim.new(op, vs.map { |v| var(v) })
        (args.length - 1).downto(0) do |i|
          body = C::Case.new(args[i], vs[i], [C::Alt.new(:default, nil, [], body)])
        end
        body
      end
    end

    def fun_body(b)
      eqs = b.eqs
      n = eqs[0].pats.length
      fail = error_core(eqs[0].tok, "Non-exhaustive patterns in function #{b.name.str}")
      return rhs(eqs[0].rhs, fail) if n.zero?

      params = Array.new(n) { fresh('x') }
      clauses = eqs.map { |eq| [eq.pats, eq.rhs] }
      C::Lam.new(params, match_clauses(params, clauses, fail) { |r, f| rhs(r, f) })
    end

    # `p = rhs` binds each variable of p to a selector thunk over the
    # (shared, lazy) value of rhs.
    def pattern_binding(b)
      v = fresh('pb')
      defs = [[v, rhs(b.rhs, error_core(b.tok, 'Non-exhaustive patterns in pattern binding'))]]
      b.names.each do |n|
        defs << [n.core, selector(v, b.pat, n, error_core(b.tok, 'Non-exhaustive patterns in pattern binding'))]
      end
      defs
    end

    # Matches var against pat and returns the value bound to name; the
    # substitutions made inside do not leak out.
    def selector(v, pat, name, fail)
      saved = @subst.dup
      core = mp([[v, pat]], -> { var(core_name(name)) }, fail)
      @subst = saved
      core
    end

    # ---- binding groups -----------------------------------------------------------

    def groups(gs, body)
      (gs || []).reverse_each { |scc| body = C::Let.new(scc_defs(scc), body) }
      body
    end

    def rhs(r, fail)
      inner = if r.body
                expr(r.body)
              else
                bind, call = fail_continuation(fail)
                acc = call
                r.guards.reverse_each { |quals, e| acc = guard(quals, expr_thunk(e), acc) }
                C::Let.new([bind], acc)
              end
      groups(r.groups, inner)
    end

    # Defers desugaring of e until the guard's patterns have set their
    # substitutions (guards can bind variables).
    def expr_thunk(e)
      -> { expr(e) }
    end

    def guard(quals, body, fail)
      return body.call if quals.empty?

      q = quals[0]
      rest = quals[1..-1]
      case q
      when BindStmt
        v = fresh('g')
        C::Let.new([[v, expr(q.expr)]], mp([[v, q.pat]], -> { guard(rest, body, fail) }, fail))
      when LetStmt then groups(q.groups, guard(rest, body, fail))
      else
        C::Case.new(expr(q.expr), nil, [C::Alt.new(:con, B::TRUE, [], guard(rest, body, fail)),
                                        C::Alt.new(:default, nil, [], fail)])
      end
    end

    # ---- pattern matching ------------------------------------------------------------

    # A failure continuation: a function of a dummy argument, not a thunk.
    # Trying the next clause must be a tail call -- as a thunk, every
    # recursive call made from a later clause would run under that thunk's
    # update frame, so `last (_:xs) = last xs` would grow the stack.
    # Returns [let binding, Core that invokes it].
    def fail_continuation(core)
      f = fresh('fail')
      u = fresh('u')
      [[f, C::Lam.new([u], core)], C::App.new(var(f), [C::Con.new(B::UNIT, [])])]
    end

    # clauses: [[pats, payload], ...]; the block turns a payload into Core
    # given the failure Core. Clause k's failure tries clauses k+1...
    def match_clauses(vars, clauses, fail, &body)
      acc = fail
      clauses.reverse_each do |pats, payload|
        bind, call = fail_continuation(acc)
        clause = mp(vars.zip(pats), -> { body.call(payload, call) }, call)
        acc = C::Let.new([bind], clause)
      end
      acc
    end

    # Match each [var, pat] in order; `success` builds the Core to run when
    # all match (after substitutions are set), `fail` is Core.
    def mp(list, success, fail)
      return success.call if list.empty?

      v, pat = list[0]
      rest = list[1..-1]
      case pat
      when PVar
        @subst[pat.ref.core] = v
        mp(rest, success, fail)
      when PWild then mp(rest, success, fail)
      when PAs
        @subst[pat.ref.core] = v
        mp([[v, pat.pat]] + rest, success, fail)
      when PBang
        C::Case.new(var(v), nil, [C::Alt.new(:default, nil, [], mp([[v, pat.pat]] + rest, success, fail))])
      when PLazy then lazy_pattern(v, pat.pat, rest, success, fail)
      when PLit then lit_pattern(v, pat, rest, success, fail)
      when PCon then con_pattern(v, pat.ref, pat.args, rest, success, fail)
      when PTuple then con_pattern(v, @env.tuple_con(pat.elems.length), pat.elems, rest, success, fail)
      when PList then list_pattern(v, pat.elems, rest, success, fail)
      when PRec
        con = pat.con.ref
        args = Array.new(con.con.arity) { PWild.new(pat.tok) }
        pat.fields.each_with_index { |(_, sub), i| args[con.fields.index(pat.ref[i])] = sub }
        con_pattern(v, con, args, rest, success, fail)
      else raise "desugar: unexpected pattern #{pat.class}"
      end
    end

    def con_pattern(v, con, args, rest, success, fail)
      if con.tyinfo && con.tyinfo.newtype
        # A newtype pattern forces nothing: the value is the field.
        return mp([[v, args[0]]] + rest, success, fail)
      end

      fields = args.map { fresh('c') }
      body = mp(fields.zip(args) + rest, success, fail)
      alts = [C::Alt.new(:con, con.con, fields, body)]
      alts << C::Alt.new(:default, nil, [], fail) if con.con.siblings.length > 1
      C::Case.new(var(v), nil, alts)
    end

    def list_pattern(v, elems, rest, success, fail)
      if elems.empty?
        return C::Case.new(var(v), nil, [C::Alt.new(:con, B::NIL, [], mp(rest, success, fail)),
                                         C::Alt.new(:default, nil, [], fail)])
      end
      h = fresh('h')
      t = fresh('t')
      inner = mp([[h, elems[0]]], -> { list_pattern(t, elems[1..-1], rest, success, fail) }, fail)
      C::Case.new(var(v), nil, [C::Alt.new(:con, B::CONS, [h, t], inner), C::Alt.new(:default, nil, [], fail)])
    end

    def lit_pattern(v, pat, rest, success, fail)
      lit = pat.lit
      case lit.kind
      when :char
        C::Case.new(var(v), nil, [C::Alt.new(:lit, lit.value, [], mp(rest, success, fail)),
                                  C::Alt.new(:default, nil, [], fail)])
      when :string
        chars = lit.value.map { |c| PLit.new(pat.tok, Lit.new(pat.tok, :char, c)) }
        list_pattern(v, chars, rest, success, fail)
      else
        eq, num = pat.ev
        kind = known_num(num)
        value = literal(pat.lit, num).value if kind
        if kind && kind != :double
          value = kind == :int ? Num.wrap_int(pat.negative ? -value : value) : (pat.negative ? -value : value)
          return C::Case.new(var(v), nil, [C::Alt.new(:lit, value, [], mp(rest, success, fail)),
                                           C::Alt.new(:default, nil, [], fail)])
        end
        lit_core = literal(pat.lit, num)
        lit_core = C::App.new(method_var('Num', 'negate'), [ev_core(num), lit_core]) if pat.negative
        test = C::App.new(method_var('Eq', '=='), [ev_core(eq), var(v), lit_core])
        C::Case.new(test, nil, [C::Alt.new(:con, B::TRUE, [], mp(rest, success, fail)),
                                C::Alt.new(:default, nil, [], fail)])
      end
    end

    # ~p: each variable of p becomes a selector thunk; nothing is forced here.
    def lazy_pattern(v, pat, rest, success, fail)
      names = {}
      collect_vars(pat, names)
      binds = names.keys.map do |n|
        s = fresh('lz')
        sel = selector(v, pat, n, error_core(pat.tok, 'Irrefutable pattern failed'))
        [n, s, sel]
      end
      binds.each { |n, s, _| @subst[n.core] = s }
      C::Let.new(binds.map { |_, s, sel| [s, sel] }, mp(rest, success, fail))
    end

    def collect_vars(p, acc)
      case p
      when PVar then acc[p.ref] = true
      when PAs
        acc[p.ref] = true
        collect_vars(p.pat, acc)
      when PCon then p.args.each { |a| collect_vars(a, acc) }
      when PTuple, PList then p.elems.each { |a| collect_vars(a, acc) }
      when PLazy, PBang then collect_vars(p.pat, acc)
      when PRec then p.fields.each { |_, a| collect_vars(a, acc) }
      end
    end

    # ---- expressions -------------------------------------------------------------------

    def expr(e)
      case e
      when Con, TupleCon then constructor(e.ref, []) # before Var: Con is a subclass of Var
      when Var
        if (km = known_method(e))
          b, dicts = km
          return dicts.empty? ? var(b.name.core) : C::App.new(var(b.name.core), dicts)
        end

        ev = evidence(e)
        ev.empty? ? reference(e.ref) : C::App.new(reference(e.ref), ev)
      when Lit then literal(e)
      when Neg then negation(e)
      when ArithSeq then arith_seq(e)
      when Do then do_block(e)
      when App then apply(e.fn, e.args.map { |a| expr(a) })
      when BinOp then apply(e.op, [expr(e.left), expr(e.right)])
      when Paren then expr(e.expr)
      when LeftSection then apply(e.op.ref, [expr(e.expr)])
      when RightSection
        x = fresh('x')
        C::Lam.new([x], apply(e.op.ref, [var(x), expr(e.expr)]))
      when Lambda
        params = e.pats.map { fresh('l') }
        fail = error_core(e.tok, 'Non-exhaustive patterns in lambda')
        C::Lam.new(params, match_clauses(params, [[e.pats, e.body]], fail) { |b, _| expr(b) })
      when Let then groups(e.groups, expr(e.body))
      when If
        C::Case.new(expr(e.cond), nil, [C::Alt.new(:con, B::TRUE, [], expr(e.then_e)),
                                        C::Alt.new(:con, B::FALSE, [], expr(e.else_e))])
      when Case
        v = fresh('s')
        fail = error_core(e.tok, 'Non-exhaustive patterns in case')
        C::Let.new([[v, expr(e.scrut)]],
                   match_clauses([v], e.alts.map { |a| [[a.pat], a.rhs] }, fail) { |r, f| rhs(r, f) })
      when Tuple then C::Con.new(B.tuple(e.elems.length), e.elems.map { |x| expr(x) })
      when List then list_literal(e.elems.map { |x| expr(x) })
      when Comp then comprehension(e.quals, e.expr)
      when Annot
        givens = e.groups || []
        return expr(e.expr) if givens.empty?

        C::App.new(C::Lam.new(givens.map { |g| g.solution[1] }, expr(e.expr)), evidence(e))
      when RecCon then record_construction(e)
      when RecUpd then record_update(e)
      else raise "desugar: unexpected #{e.class}"
      end
    end

    # ---- literals, negation, sequences, do --------------------------------------------

    INT_KEYS = { 'Int' => :int, 'Integer' => :integer, 'Double' => :double }.freeze

    # The machine type of a numeric literal's instance: :int, :integer,
    # :double, or nil (go through fromInteger/fromRational).
    def known_num(ev)
      inst = solved_instance(ev)
      inst && INT_KEYS[inst.head.key]
    end

    def literal(e, ev = nil)
      case e.kind
      when :string then return C::Str.new(e.value)
      when :char then return C::Lit.new(e.value)
      end
      ev ||= e.ev[0]
      kind = known_num(ev)
      if e.kind == :integer
        case kind
        when :int then C::Lit.new(Num.wrap_int(e.value))
        when :integer then C::Lit.new(e.value)
        when :double then C::Lit.new(Num.integer_to_double(e.value))
        else C::App.new(method_var('Num', 'fromInteger'), [ev_core(ev), C::Lit.new(e.value)])
        end
      else
        m, x = e.value
        if kind == :double
          C::Lit.new(Num.literal_to_double(m, x))
        else
          C::App.new(method_var('Fractional', 'fromRational'), [ev_core(ev), rational(m, x)])
        end
      end
    end

    # mantissa * 10**exp10 as a reduced Ratio Integer.
    def rational(m, x)
      n = x >= 0 ? m * 10**x : m
      d = x >= 0 ? 1 : 10**-x
      g = n.gcd(d)
      ratio = internal(':%')
      C::Con.new(ratio.con, [C::Lit.new(n / g), C::Lit.new(d / g)])
    end

    def negation(e)
      x = e.expr
      x = x.expr while x.is_a?(Paren)
      if x.is_a?(Lit) && x.kind != :char && x.kind != :string
        kind = known_num(e.ev[0])
        if kind
          v = literal(x, e.ev[0]).value
          neg = case kind
                when :int then Num.wrap_int(-v)
                when :double then Num.negate_double(v)
                else -v
                end
          return C::Lit.new(neg)
        end
      end
      C::App.new(method_var('Num', 'negate'), [ev_core(e.ev[0]), expr(e.expr)])
    end

    def arith_seq(e)
      d = ev_core(e.ev[0])
      args = [e.from, e.thn, e.to].compact.map { |x| expr(x) }
      name = if e.thn
               e.to ? 'enumFromThenTo' : 'enumFromThen'
             else
               e.to ? 'enumFromTo' : 'enumFrom'
             end
      C::App.new(method_var('Enum', name), [d] + args)
    end

    def do_block(e)
      dict = ev_core(e.ev[0])
      do_stmts(e.stmts, dict, e)
    end

    def do_stmts(stmts, dict, node)
      s = stmts[0]
      rest = stmts[1..-1]
      return expr(s.expr) if rest.empty?

      case s
      when BindStmt
        x = fresh('b')
        fail = if s.ev && !s.ev.empty?
                 msg = "Pattern match failure in `do' block at #{@source}:#{s.tok.line}:#{s.tok.col}"
                 C::App.new(method_var('MonadFail', 'fail'), [ev_core(s.ev[0]), C::Str.new(msg.codepoints)])
               else
                 error_core(s.tok, 'Irrefutable pattern failed')
               end
        k = C::Lam.new([x], mp([[x, s.pat]], -> { do_stmts(rest, dict, node) }, fail))
        C::App.new(method_var('Monad', '>>='), [dict, expr(s.expr), k])
      when LetStmt then groups(s.groups, do_stmts(rest, dict, node))
      else
        C::App.new(method_var('Monad', '>>'), [dict, expr(s.expr), do_stmts(rest, dict, node)])
      end
    end

    # A list literal as one flat let group of cons cells (no deep nesting,
    # whatever the length).
    def list_literal(elems)
      return C::Con.new(B::NIL, []) if elems.empty?

      binds = []
      cell = C::Con.new(B::NIL, [])
      elems.reverse_each do |x|
        v = fresh('cell')
        binds << [v, C::Con.new(B::CONS, [x, cell])]
        cell = var(v)
      end
      C::Let.new(binds, cell)
    end

    def reference(n)
      return constructor(n, []) if n.kind == :con
      return C::Var.new(core_name(n)) unless n.prim && n.prim_arity.zero?

      prim_call(n.prim, [])
    end

    # fn (an AST node: Var/Con/other) applied to Core args, saturating
    # constructors and primitives where possible.
    def apply(fn, args)
      ref = fn.respond_to?(:ref) ? fn.ref : nil
      if (fn.is_a?(Var) || fn.is_a?(Con) || fn.is_a?(TupleCon)) && ref.is_a?(Name)
        return constructor(ref, args) if ref.kind == :con

        km = fn.is_a?(Var) ? known_method(fn) : nil
        if km && km[1].empty? && (p = km[0].prim_alias) && args.length >= p.prim_arity
          head = prim_call(p.prim, args[0, p.prim_arity])
          extra = args[p.prim_arity..-1]
          return extra.empty? ? head : C::App.new(head, extra)
        end
        if ref.prim && args.length >= ref.prim_arity
          head = prim_call(ref.prim, args[0, ref.prim_arity])
          extra = args[ref.prim_arity..-1]
          return extra.empty? ? head : C::App.new(head, extra)
        end
      end
      f = fn.is_a?(Node) ? expr(fn) : fn
      args.empty? ? f : C::App.new(f, args)
    end

    # A constructor applied to some arguments (possibly fewer than its
    # arity: then a lambda takes the rest). Strict fields are forced first.
    def constructor(n, args)
      info = n.con
      if n.tyinfo && n.tyinfo.newtype
        return args[0] if args.length == 1

        x = fresh('nt')
        return C::Lam.new([x], var(x))
      end
      arity = info.arity
      return C::Con.new(info, []) if arity.zero?

      extra = args.length > arity ? args[arity..-1] : []
      given = args[0, arity]
      missing = Array.new(arity - given.length) { fresh('k') }
      all = given + missing.map { |m| var(m) }
      body = saturated(n, all)
      body = C::Lam.new(missing, body) unless missing.empty?
      extra.empty? ? body : C::App.new(body, extra)
    end

    def saturated(n, args)
      strict = n.strict || []
      return C::Con.new(n.con, args) unless strict.include?(true)

      vs = args.map { fresh('sf') }
      body = C::Con.new(n.con, vs.map { |v| var(v) })
      (args.length - 1).downto(0) do |i|
        body = if strict[i]
                 C::Case.new(args[i], vs[i], [C::Alt.new(:default, nil, [], body)])
               else
                 C::Let.new([[vs[i], args[i]]], body)
               end
      end
      body
    end

    # Report 3.11: [e | b, Q] = if b then [e | Q] else []
    #              [e | p <- l, Q] = concatMap (\x -> case x of p -> [e | Q]; _ -> []) l
    #              [e | let ds, Q] = let ds in [e | Q]
    def comprehension(quals, head)
      return C::Con.new(B::CONS, [expr(head), C::Con.new(B::NIL, [])]) if quals.empty?

      q = quals[0]
      rest = quals[1..-1]
      empty = C::Con.new(B::NIL, [])
      case q
      when BindStmt
        x = fresh('q')
        ok = C::Lam.new([x], mp([[x, q.pat]], -> { comprehension(rest, head) }, empty))
        cm = internal('rhci_concatMap')
        C::App.new(C::Var.new(cm.core), [ok, expr(q.expr)])
      when LetStmt then groups(q.groups, comprehension(rest, head))
      else
        C::Case.new(expr(q.expr), nil, [C::Alt.new(:con, B::TRUE, [], comprehension(rest, head)),
                                        C::Alt.new(:default, nil, [], empty)])
      end
    end

    def record_construction(e)
      con = e.con.ref
      args = Array.new(con.con.arity)
      e.fields.each_with_index { |(_, x), i| args[con.fields.index(e.ref[i])] = expr(x) }
      args.each_index do |i|
        next if args[i]

        args[i] = error_core(e.tok, "Missing field in record construction #{con.fields[i].str}")
      end
      constructor(con, args)
    end

    def record_update(e)
      fields = e.ref
      ti = fields[0].field_cons[0][0].tyinfo
      v = fresh('ru')
      newvals = e.fields.map { |_, x| expr(x) }
      if ti.newtype
        return C::Let.new([[v, expr(e.expr)]], newvals[0])
      end

      alts = []
      ti.cons.each do |c|
        next unless fields.all? { |f| (c.fields || []).include?(f) }

        vs = Array.new(c.con.arity) { fresh('u') }
        args = vs.map { |x| var(x) }
        fields.each_with_index { |f, i| args[c.fields.index(f)] = newvals[i] }
        alts << C::Alt.new(:con, c.con, vs, saturated(c, args))
      end
      alts << C::Alt.new(:default, nil, [], error_core(e.tok, 'No match in record update'))
      C::Let.new([[v, expr(e.expr)]], C::Case.new(var(v), nil, alts))
    end
  end
end
