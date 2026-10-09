# frozen_string_literal: true

module Rhci
  # Hindley-Milner inference over the renamed AST, with level-based
  # generalisation (binding groups in the renamer's dependency order),
  # rigid variables for signatures, and synonym expansion. Classes arrive
  # in build step 5; until then anything needing one is refused.
  #
  # Schemes live in a Hash keyed by Name (unique, so locals and globals
  # share it). `tenv` holds the session's committed schemes; this checker
  # adds to an overlay that the session commits only on success.
  class TypeChecker
    include AST
    T = Types

    attr_reader :pending

    def initialize(env, tenv, source = '<interactive>')
      @env = env
      @tenv = tenv
      @pending = {}
      @source = source
      @level = 0
      @ids = 0
    end

    # Check a renamed top-level input. Returns the expression's type (or
    # nil); new global schemes are in #pending.
    def top(rtop)
      @new_types = rtop.types
      rtop.tyinfos.each { |ti| define_type(ti) }
      infer_groups(rtop.groups)
      t = nil
      if rtop.expr
        @level += 1
        t = infer(rtop.expr)
        if rtop.bind_pat
          a = fresh
          unify(t, T.app(io_tcon, [a]), rtop.expr)
          check_pat(rtop.bind_pat, a)
        end
        @level -= 1
        rtop.values.each_value { |n| @pending[n] = generalize(@pending[n].type) } if rtop.bind_pat
      end
      t
    end

    # The generalised type of an expression (what :type shows).
    def expression_scheme(e)
      @level += 1
      t = infer(e)
      @level -= 1
      generalize(t)
    end

    def scheme_of(name)
      @pending[name] || @tenv[name] || builtin_scheme(name)
    end

    private

    def err(kind, node, msg)
      tok = node.respond_to?(:tok) ? node.tok : nil
      raise Error.new(kind, msg, tok&.line, tok&.col, @source)
    end

    def unsupported(node, what)
      tok = node.respond_to?(:tok) ? node.tok : nil
      raise UnsupportedError.new("#{what} need type classes, which are not implemented yet",
                                 tok&.line, tok&.col, @source)
    end

    def fresh
      @ids += 1
      T::TMeta.new(@ids, @level)
    end

    def show(t)
      T::Printer.new.type(t)
    end

    def named_type(str)
      n = (@new_types && @new_types[str]) || @env.types[str]
      raise "typechecker: the Prelude does not define #{str}" unless n

      n.tyinfo.tcon
    end

    def bool_type
      @bool ||= named_type('Bool')
    end

    def io_tcon
      @io ||= named_type('IO')
    end

    # ---- unification -------------------------------------------------------------

    def unify(a, b, node)
      stack = [[a, b]]
      until stack.empty?
        x, y = stack.pop
        x = T.prune(x)
        y = T.prune(y)
        next if x.equal?(y)

        if x.is_a?(T::TMeta)
          bind_meta(x, y, node, a, b)
        elsif y.is_a?(T::TMeta)
          bind_meta(y, x, node, a, b)
        elsif x.is_a?(T::TCon) && y.is_a?(T::TCon)
          mismatch(a, b, node) unless x.key == y.key
        elsif x.is_a?(T::TAp) && y.is_a?(T::TAp)
          stack.push([x.arg, y.arg])
          stack.push([x.fn, y.fn])
        else
          mismatch(a, b, node)
        end
      end
    end

    def mismatch(expected, actual, node)
      p = T::Printer.new
      err(:compile, node, "Couldn't match expected type ‘#{p.type(expected)}’ with actual type ‘#{p.type(actual)}’")
    end

    # m := t, with the occurs check, level adjustment, and skolem escape.
    def bind_meta(m, t, node, a, b)
      walk = [t]
      until walk.empty?
        x = T.prune(walk.pop)
        case x
        when T::TMeta
          if x.equal?(m)
            p = T::Printer.new
            err(:compile, node, "Occurs check: cannot construct the infinite type: #{p.type(m)} ~ #{p.type(t)}")
          end
          x.level = m.level if x.level > m.level
        when T::TSkol
          if x.level > m.level
            p = T::Printer.new
            err(:compile, node, "Couldn't match expected type ‘#{p.type(a)}’ with actual type ‘#{p.type(b)}’ " \
                                "(the rigid type variable ‘#{x.name}’ would escape its scope)")
          end
        when T::TAp
          walk.push(x.fn)
          walk.push(x.arg)
        end
      end
      m.ref = t
    end

    # ---- schemes -------------------------------------------------------------------

    def instantiate(s)
      return s.type if s.nvars.zero?

      metas = Array.new(s.nvars) { fresh }
      subst(s.type, metas)
    end

    def subst(t, args)
      t = T.prune(t)
      case t
      when T::TGen then args[t.index]
      when T::TAp then T::TAp.new(subst(t.fn, args), subst(t.arg, args))
      else t
      end
    end

    def skolemize(s)
      return s.type if s.nvars.zero?

      sks = Array.new(s.nvars) do |i|
        @ids += 1
        T::TSkol.new((s.names && s.names[i]) || "a#{i}", @ids, @level)
      end
      subst(s.type, sks)
    end

    # Quantify the metas whose level is above the current one.
    def generalize(t)
      map = {}
      gen = gen_copy(t, map)
      T::Scheme.new(map.length, gen)
    end

    def gen_copy(t, map)
      t = T.prune(t)
      case t
      when T::TMeta
        return t unless t.level > @level

        map[t] ||= T::TGen.new(map.length)
      when T::TAp then T::TAp.new(gen_copy(t.fn, map), gen_copy(t.arg, map))
      else t
      end
    end

    def bind_mono(name, t)
      @pending[name] = T.mono(t)
    end

    # ---- types from syntax -------------------------------------------------------

    # A signature's scheme: its type variables are quantified in order of
    # appearance.
    def sig_scheme(ast)
      vars = {}
      t = convert(ast, vars, true)
      s = T::Scheme.new(vars.length, t)
      s.names = vars.keys
      s
    end

    # AST type -> Types. vars maps type variable names to TGen (or other
    # types); with `extend`, unseen variables become new TGens.
    def convert(t, vars, extend)
      case t
      when TVar
        v = vars[t.name]
        return v if v
        err(:scope, t, "Not in scope: type variable ‘#{t.name}’") unless extend

        vars[t.name] = T::TGen.new(vars.length)
      when TCon, TApp then convert_app(t, vars, extend)
      when TFun then T.fn(convert(t.from, vars, extend), convert(t.to, vars, extend))
      when TList then T.list(convert(t.elem, vars, extend))
      when TTuple then T.tuple(t.elems.map { |e| convert(e, vars, extend) })
      when TQual
        unsupported(t, 'class constraints') unless t.context.empty?
        convert(t.type, vars, extend)
      else raise "typechecker: unexpected type syntax #{t.class}"
      end
    end

    def convert_app(t, vars, extend)
      head = t.is_a?(TApp) ? t.fn : t
      args = t.is_a?(TApp) ? t.args : []
      if head.is_a?(TVar)
        raise UnsupportedError.new('higher-kinded type variables are not supported yet',
                                   head.tok.line, head.tok.col, @source) unless args.empty?

        return convert(head, vars, extend)
      end
      return convert(head, vars, extend) unless head.is_a?(TCon)

      ti = head.ref.tyinfo
      cargs = args.map { |a| convert(a, vars, extend) }
      if ti.synonym
        params, body = ti.synonym
        if cargs.length < params.length
          err(:compile, head, "The type synonym ‘#{head.name}’ should have #{params.length} arguments, " \
                              "but has been given #{cargs.length}")
        end
        sub = {}
        params.each_with_index { |p, i| sub[p] = cargs[i] }
        expanded = convert(body, sub, false)
        return T.app(expanded, cargs[params.length..-1])
      end
      tcon = ti.tcon
      if cargs.length != tcon.arity
        err(:compile, head, "Expecting #{tcon.arity - cargs.length} more argument#{tcon.arity - cargs.length == 1 ? '' : 's'} " \
                            "to ‘#{head.name}’") if cargs.length < tcon.arity
        err(:compile, head, "‘#{head.name}’ is applied to too many type arguments")
      end
      T.app(tcon, cargs)
    end

    # ---- data types ----------------------------------------------------------------

    def define_type(ti)
      return if ti.synonym

      params = {}
      ti.params.each_with_index { |p, i| params[p] = T::TGen.new(i) }
      result = T.app(ti.tcon, (0...ti.params.length).map { |i| params[ti.params[i]] })
      field_types = {}
      ti.cons.each do |c|
        fts = c.field_types.map { |ft| convert(ft, params, false) }
        @pending[c] = T::Scheme.new(ti.params.length, fts.reverse.inject(result) { |acc, f| T.fn(f, acc) })
        (c.fields || []).each_with_index do |f, i|
          if field_types.key?(f)
            same = T::Printer.new.type(field_types[f]) == T::Printer.new.type(fts[i])
            err(:compile, f, "Constructors with the field ‘#{f.str}’ give it different types") unless same
          else
            field_types[f] = fts[i]
            @pending[f] = T::Scheme.new(ti.params.length, T.fn(result, fts[i]))
          end
        end
      end
    end

    # Schemes of the machine-level constructors: (), [], (:), tuples.
    def builtin_scheme(name)
      return nil unless name.kind == :con

      a = T::TGen.new(0)
      case name.con
      when VM::Builtins::UNIT then T.mono(T::UNIT)
      when VM::Builtins::NIL then T::Scheme.new(1, T.list(a))
      when VM::Builtins::CONS then T::Scheme.new(1, T.fn(a, T.fn(T.list(a), T.list(a))))
      else
        n = name.con.arity
        gens = (0...n).map { |i| T::TGen.new(i) }
        T::Scheme.new(n, gens.reverse.inject(T.tuple(gens)) { |acc, g| T.fn(g, acc) })
      end
    end

    def con_type(node, name)
      s = scheme_of(name)
      raise "typechecker: no type for constructor #{name.str}" unless s

      instantiate(s)
    end

    # ---- binding groups --------------------------------------------------------------

    # Signatures are installed for the whole block first: references to a
    # signed name create no dependency edge (Report 4.5.2), so its group
    # may be checked after its users.
    def infer_groups(groups)
      return unless groups

      groups.each do |scc|
        scc.each { |b| b.sigs.each { |n, sig| @pending[n] = sig_scheme(sig.type) } }
      end
      groups.each { |scc| infer_scc(scc) }
    end

    def infer_scc(binds)
      @level += 1
      sigs = {}
      binds.each do |b|
        b.names.each do |n|
          if b.sigs.key?(n)
            sigs[n] = @pending[n]
          else
            bind_mono(n, fresh)
          end
        end
      end
      binds.each do |b|
        case b.kind
        when :fun
          t = infer_equations(b.eqs)
          if sigs.key?(b.name)
            unify(skolemize(sigs[b.name]), t, b.eqs[0])
          else
            unify(@pending[b.name].type, t, b.eqs[0])
          end
        when :pat
          t = infer_rhs(b.rhs)
          bind_pattern_vars(b.pat, t, sigs)
        end
      end
      @level -= 1
      binds.each do |b|
        b.names.each { |n| @pending[n] = generalize(@pending[n].type) unless sigs.key?(n) }
      end
    end

    def infer_equations(eqs)
      n = eqs[0].pats.length
      args = Array.new(n) { fresh }
      res = fresh
      eqs.each do |eq|
        eq.pats.each_with_index { |p, i| check_pat(p, args[i]) }
        unify(res, infer_rhs(eq.rhs), eq)
      end
      args.reverse.inject(res) { |acc, a| T.fn(a, acc) }
    end

    def infer_rhs(r)
      infer_groups(r.groups) if r.where
      return infer(r.body) if r.body

      res = fresh
      r.guards.each do |quals, e|
        quals.each { |q| infer_qual(q) }
        unify(res, infer(e), e)
      end
      res
    end

    # A guard qualifier or comprehension qualifier (list: true).
    def infer_qual(q, list: false)
      case q
      when BindStmt
        t = infer(q.expr)
        elem = fresh
        if list
          unify(T.list(elem), t, q.expr)
          check_pat(q.pat, elem)
        else
          check_pat(q.pat, t)
        end
      when LetStmt then infer_groups(q.groups)
      else unify(bool_type, infer(q.expr), q.expr)
      end
    end

    # ---- patterns -------------------------------------------------------------------

    # Check `p` against type t, binding its variables monomorphically.
    def check_pat(p, t)
      case p
      when PVar then bind_mono(p.ref, t)
      when PWild then nil
      when PLit then unify(lit_type(p.lit, p), t, p)
      when PCon
        ct = con_type(p, p.ref)
        p.args.each do |a|
          arg, rest = T.split_fn(ct)
          check_pat(a, arg)
          ct = rest
        end
        unify(t, ct, p)
      when PTuple
        ts = p.elems.map { fresh }
        unify(t, T.tuple(ts), p)
        p.elems.each_with_index { |e, i| check_pat(e, ts[i]) }
      when PList
        a = fresh
        unify(t, T.list(a), p)
        p.elems.each { |e| check_pat(e, a) }
      when PAs
        bind_mono(p.ref, t)
        check_pat(p.pat, t)
      when PLazy, PBang then check_pat(p.pat, t)
      when PRec
        con = p.con.ref
        ct = con_type(p, con)
        args = []
        while (fa = T.split_fn(ct)) && args.length < con.con.arity
          args << fa[0]
          ct = fa[1]
        end
        unify(t, ct, p)
        p.fields.each_with_index { |(_, sub), i| check_pat(sub, args[con.fields.index(p.ref[i])]) }
      else raise "typechecker: unexpected pattern #{p.class}"
      end
    end

    # A pattern binding: its variables already have monotypes (or
    # signatures) in the group, which the pattern's types must agree with.
    def bind_pattern_vars(p, t, sigs)
      vars = {}
      collect_pat_vars(p, vars)
      before = {}
      vars.each_key { |n| before[n] = @pending[n].type unless sigs.key?(n) }
      check_pat(p, t)
      vars.each_key do |n|
        if sigs.key?(n)
          unify(skolemize(sigs[n]), @pending[n].type, p)
          @pending[n] = sigs[n]
        else
          unify(before[n], @pending[n].type, p)
          @pending[n] = T.mono(before[n])
        end
      end
    end

    def collect_pat_vars(p, acc)
      case p
      when PVar then acc[p.ref] = true
      when PAs
        acc[p.ref] = true
        collect_pat_vars(p.pat, acc)
      when PCon then p.args.each { |a| collect_pat_vars(a, acc) }
      when PTuple, PList then p.elems.each { |a| collect_pat_vars(a, acc) }
      when PLazy, PBang then collect_pat_vars(p.pat, acc)
      when PRec then p.fields.each { |_, a| collect_pat_vars(a, acc) }
      end
    end

    def lit_type(lit, node)
      case lit.kind
      when :char then T::CHAR
      when :string then T.list(T::CHAR)
      else unsupported(node, 'numeric literals')
      end
    end

    # ---- expressions ----------------------------------------------------------------

    def infer(e)
      t = infer_inner(e)
      e.ty = t
      t
    end

    def infer_inner(e)
      case e
      when Var then var_type(e, e.ref)
      when Con, TupleCon then con_type(e, e.ref)
      when Lit then lit_type(e, e)
      when App
        f = infer(e.fn)
        e.args.each do |a|
          at = infer(a)
          r = fresh
          unify(f, T.fn(at, r), a)
          f = r
        end
        f
      when BinOp
        ot = e.op.is_a?(Con) ? con_type(e.op, e.op.ref) : var_type(e.op, e.op.ref)
        lt = infer(e.left)
        rt = infer(e.right)
        r = fresh
        unify(ot, T.fn(lt, T.fn(rt, r)), e)
        r
      when Neg then unsupported(e, 'negation')
      when Paren then infer(e.expr)
      when LeftSection
        ot = op_type(e.op)
        r = fresh
        unify(ot, T.fn(infer(e.expr), r), e)
        r
      when RightSection
        ot = op_type(e.op)
        a = fresh
        r = fresh
        unify(ot, T.fn(a, T.fn(infer(e.expr), r)), e)
        T.fn(a, r)
      when Lambda
        ts = e.pats.map { fresh }
        e.pats.each_with_index { |p, i| check_pat(p, ts[i]) }
        ts.reverse.inject(infer(e.body)) { |acc, a| T.fn(a, acc) }
      when Let
        infer_groups(e.groups)
        infer(e.body)
      when If
        unify(bool_type, infer(e.cond), e.cond)
        t = infer(e.then_e)
        unify(t, infer(e.else_e), e.else_e)
        t
      when Case
        st = infer(e.scrut)
        r = fresh
        e.alts.each do |alt|
          check_pat(alt.pat, st)
          unify(r, infer_rhs(alt.rhs), alt)
        end
        r
      when Do then unsupported(e, 'do blocks')
      when ArithSeq then unsupported(e, 'arithmetic sequences')
      when Tuple then T.tuple(e.elems.map { |x| infer(x) })
      when List
        a = fresh
        e.elems.each { |x| unify(a, infer(x), x) }
        T.list(a)
      when Comp
        e.quals.each { |q| infer_qual(q, list: true) }
        T.list(infer(e.expr))
      when Annot
        s = sig_scheme(e.type)
        unify(skolemize(s), infer(e.expr), e)
        instantiate(s)
      when RecCon
        con = e.con.ref
        ct = con_type(e, con)
        args = []
        while args.length < con.con.arity
          a, ct = T.split_fn(ct)
          args << a
        end
        e.fields.each_with_index do |(_, x), i|
          unify(args[con.fields.index(e.ref[i])], infer(x), x)
        end
        ct
      when RecUpd
        t = infer(e.expr)
        e.fields.each_with_index do |(_, x), i|
          sel = instantiate(scheme_of(e.ref[i]))
          unify(sel, T.fn(t, infer(x)), x)
        end
        t
      else raise "typechecker: unexpected #{e.class}"
      end
    end

    def var_type(node, name)
      s = scheme_of(name)
      raise "typechecker: no type for #{name.str}" unless s

      instantiate(s)
    end

    def op_type(item)
      r = item.ref
      t = r.is_a?(Con) ? con_type(r, r.ref) : var_type(r, r.ref)
      r.ty = t
      t
    end
  end
end
