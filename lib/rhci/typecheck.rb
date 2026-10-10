# frozen_string_literal: true

module Rhci
  # A class constraint to be solved, and how it was: the dictionary the
  # desugarer passes for it. solution:
  #   [:param, core name]          a dictionary parameter
  #   [:inst, InstInfo, [Ev, ...]] an instance, applied to the evidence for
  #                                its context
  #   [:super, Ev, [i, ...]]       superclass selections from another Ev
  #   [:same, Ev]                  identical to another Ev
  class Ev
    attr_accessor :klass, :type, :solution, :tok

    def initialize(klass, type, tok)
      @klass = klass
      @type = type
      @tok = tok
    end
  end

  # Hindley-Milner inference with Haskell 98 type classes over the renamed
  # AST: level-based generalisation in the renamer's dependency order,
  # rigid variables for signatures, constraint solving with evidence
  # (dictionary passing), superclasses, defaulting (the Report's rules in
  # files, GHCi's ExtendedDefaultRules at the prompt), and the monomorphism
  # restriction (files only, as in GHCi).
  #
  # Schemes live in a Hash keyed by Name. `tenv` holds the session's
  # committed schemes; this checker adds to an overlay (#pending), and new
  # instances go to #new_instances; the session commits both on success.
  class TypeChecker
    include AST
    T = Types

    NUMERIC = %w[Num Real Integral Fractional Floating RealFrac RealFloat].freeze
    STANDARD = (NUMERIC + %w[Eq Ord Show Read Enum Bounded Ix Functor Monad MonadFail Foldable
                             Traversable Applicative Semigroup Monoid]).freeze
    INTERACTIVE = %w[Show Eq Ord Foldable Traversable].freeze

    attr_reader :pending, :new_instances

    # mode: :prompt (GHCi statements) or :file (loaded modules).
    def initialize(env, tenv, source = '<interactive>', mode: :prompt)
      @env = env
      @tenv = tenv
      @pending = {}
      @new_instances = {}
      @source = source
      @mode = mode
      @level = 0
      @ids = 0
      @wanted = []
      @givens = []
      @dicts = 0
    end

    # Check a renamed top-level input. Returns the expression's type (or
    # nil); new global schemes are in #pending.
    def top(rtop)
      @new_types = rtop.types
      rtop.tyinfos.each { |ti| define_type(ti) }
      rtop.classes.each { |ci| define_class(ci) }
      rtop.instances.each { |inst| register_instance(inst) }
      infer_groups(rtop.groups)
      rtop.classes.each { |ci| check_defaults(ci) }
      rtop.instances.each { |inst| check_instance(inst) }
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
        if rtop.bind_pat
          # `pat <- io` binds monomorphically: default first (GHCi gives
          # `x <- return 1` the type Integer), then close the types.
          solve_top
          rtop.values.each_value { |n| @pending[n] = T::Scheme.new(0, close_with_any(@pending[n].type), []) }
        end
      end
      solve_top
      t
    end

    # t with every open type variable replaced by Any.
    def close_with_any(t)
      t = T.prune(t)
      case t
      when T::TMeta then T::ANY
      when T::TAp then T::TAp.new(close_with_any(t.fn), close_with_any(t.arg))
      else t
      end
    end

    # The generalised type of an expression (what :type shows). Constraints
    # stay quantified; only ambiguous ones are defaulted (GHCi rules).
    def expression_scheme(e)
      outer = @wanted
      @wanted = []
      @level += 1
      t = infer(e)
      @level -= 1
      w = @wanted
      @wanted = outer
      quant, deferred = simplify(w)
      quant = resolve_ambiguity(quant, [t])
      quant = minimize(quant)
      @wanted.concat(deferred)
      solve_top
      generalize(t, quant)
    end

    # How the prompt prints the value of global `name` (GHCi's `print it`,
    # or running it when it is an IO action). Returns a Hash:
    #   node:  a Var node for `name`, with evidence (at defaulted types)
    #   io:    true if it is an IO action to run
    #   show:  the Show evidence for the printed value, or nil (no printing:
    #          an IO result of type (), or one without a Show instance)
    def print_plan(name, tok)
      node = Var.new(tok, name.str)
      node.ref = name
      @level += 1
      t = infer(node)
      @level -= 1
      h, args = T.spine(t)
      io = false
      if h.is_a?(T::TCon) && h.key == io_tcon.key && args.length == 1
        io = true
      elsif h.is_a?(T::TMeta) && args.length == 1 && @wanted.any? { |ev| T.prune(ev.type).equal?(h) && ev.klass.name.str == 'Monad' }
        unify(h, io_tcon, node) # GHCi runs an ambiguous monadic statement in IO
        io = true
      elsif h.is_a?(T::TMeta) && args.empty? && io_instances?(h)
        unify(h, T.app(io_tcon, [fresh]), node) # printf "..."
        io = true
      end
      value_type = io ? T.spine(t)[1][0] : t
      show = nil
      if io
        solve_top
        r = T.prune(value_type)
        unless r.is_a?(T::TCon) && r.equal?(T::UNIT)
          show = Ev.new(named_class('Show'), value_type, tok)
          show = nil unless solvable?(show)
          if show
            @wanted << show
            solve_top
          end
        end
      else
        show = Ev.new(named_class('Show'), value_type, tok)
        @wanted << show
        solve_top
      end
      { node: node, io: io, show: show }
    end

    # GHCi tries an input as an IO statement first: a value of a bare type
    # variable is run when every constraint on it has an instance for IO
    # with no class context (Text.Printf's `(a ~ ()) => PrintfType (IO a)`).
    def io_instances?(meta)
      evs = @wanted.select { |ev| T.prune(ev.type).equal?(meta) }
      return false if evs.empty?

      evs.all? do |ev|
        inst = find_instance(ev.klass, io_tcon)
        inst && inst.context.empty?
      end
    end

    def scheme_of(name)
      @pending[name] || @tenv[name] || builtin_scheme(name)
    end

    def find_instance(klass, tcon)
      @new_instances[[klass, tcon.key]] || klass.instances[tcon.key]
    end

    private

    def err(kind, node, msg)
      tok = node.respond_to?(:tok) ? node.tok : node
      tok = nil unless tok.respond_to?(:line)
      raise Error.new(kind, msg, tok&.line, tok&.col, @source)
    end

    def unsupported(node, what)
      tok = node.respond_to?(:tok) ? node.tok : nil
      raise UnsupportedError.new("#{what} are not supported yet", tok&.line, tok&.col, @source)
    end

    def fresh
      @ids += 1
      T::TMeta.new(@ids, @level)
    end

    def fresh_dict
      @dicts += 1
      "dict%#{@dicts}%#{object_id}"
    end

    def named_type(str)
      n = (@new_types && @new_types[str]) || @env.types[str]
      raise "typechecker: the Prelude does not define #{str}" unless n

      n.tyinfo.tcon
    end

    def named_class(str)
      n = (@new_types && @new_types[str]) || @env.types[str]
      raise "typechecker: the Prelude does not define class #{str}" unless n && n.kind == :class

      n.klass
    end

    def bool_type
      @bool ||= named_type('Bool')
    end

    def io_tcon
      @io ||= named_type('IO')
    end

    def ev_for(klass_name, t, node)
      ev = Ev.new(named_class(klass_name), t, node.tok)
      @wanted << ev
      ev
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

    def same_type?(a, b)
      stack = [[a, b]]
      until stack.empty?
        x, y = stack.pop
        x = T.prune(x)
        y = T.prune(y)
        next if x.equal?(y)
        return false unless x.class == y.class

        case x
        when T::TCon then return false unless x.key == y.key
        when T::TAp
          stack.push([x.fn, y.fn])
          stack.push([x.arg, y.arg])
        else return false
        end
      end
      true
    end

    # ---- schemes -------------------------------------------------------------------

    # Instantiate; evidence for the scheme's constraints is recorded on
    # `node` (in order) and becomes wanted.
    def instantiate(s, node = nil)
      return s.type if s.nvars.zero? && s.preds.empty?

      metas = Array.new(s.nvars) { fresh }
      unless s.preds.empty?
        evs = s.preds.map { |c, t| Ev.new(c, subst(t, metas), node&.tok) }
        @wanted.concat(evs)
        node.ev = evs if node
      end
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

    # Quantify the metas above the current level, with the given evidence
    # as the scheme's constraints (in dictionary-parameter order).
    def generalize(t, evs)
      map = {}
      gen = gen_copy(t, map)
      preds = evs.map { |ev| [ev.klass, gen_copy(ev.type, map)] }
      T::Scheme.new(map.length, gen, preds)
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

    # ---- constraint solving ---------------------------------------------------------

    # Reduce evidence by instances and givens. Returns [quantifiable, deferred]:
    # constraints on variables of the current group, and on outer ones.
    def simplify(evs)
      queue = evs.dup
      quant = []
      deferred = []
      until queue.empty?
        ev = queue.shift
        next if ev.solution

        h, args = T.spine(ev.type)
        case h
        when T::TCon
          inst = find_instance(ev.klass, h)
          no_instance(ev) unless inst && inst.tyvars.length == args.length
          inst.equalities&.each { |i, et| unify(args[i], et, ev.tok) }
          subs = inst.context.map { |c, i| Ev.new(c, args[i], ev.tok) }
          ev.solution = [:inst, inst, subs]
          queue.concat(subs)
        when T::TSkol
          sol = from_givens(ev)
          no_instance(ev, 'Could not deduce') unless sol
          ev.solution = sol
        when T::TMeta
          given = from_givens(ev)
          if given
            ev.solution = given
          elsif h.level > @level
            quant << ev
          else
            deferred << ev
          end
        else
          no_instance(ev)
        end
      end
      [quant, deferred]
    end

    def no_instance(ev, what = 'No instance for')
      p = T::Printer.new
      raise Error.new(:compile, "#{what} ‘#{ev.klass.name.str} #{p.type(ev.type, 2)}’",
                      ev.tok&.line, ev.tok&.col, @source)
    end

    # Evidence from an enclosing signature/instance context, directly or
    # through superclasses.
    def from_givens(ev)
      i = @givens.length - 1
      while i >= 0
        @givens[i].each do |g|
          next unless same_type?(g.type, ev.type)
          return [:same, g] if g.klass.equal?(ev.klass)

          g.klass.ancestors.each do |anc, path|
            return [:super, g, path] if anc.equal?(ev.klass)
          end
        end
        i -= 1
      end
      nil
    end

    # Would this constraint be solvable (by instances alone)?
    def solvable?(ev)
      queue = [[ev.klass, ev.type]]
      until queue.empty?
        k, t = queue.shift
        h, args = T.spine(t)
        return false unless h.is_a?(T::TCon)

        inst = find_instance(k, h)
        return false unless inst && inst.tyvars.length == args.length

        inst.context.each { |c, i| queue << [c, args[i]] }
      end
      true
    end

    # Drop duplicates and constraints implied by a superclass of another;
    # they are solved from the one kept.
    def minimize(quant)
      kept = []
      quant.each do |ev|
        same = kept.find { |k| k.klass.equal?(ev.klass) && same_type?(k.type, ev.type) }
        if same
          ev.solution = [:same, same]
        else
          kept << ev
        end
      end
      final = []
      kept.each do |ev|
        by = nil
        kept.each do |o|
          next if o.equal?(ev) || !same_type?(o.type, ev.type)

          hit = o.klass.ancestors.find { |anc, _| anc.equal?(ev.klass) }
          if hit
            by = [o, hit[1]]
            break
          end
        end
        if by
          ev.solution = [:super, by[0], by[1]]
        else
          final << ev
        end
      end
      final
    end

    # Constraints on variables that occur in none of `types` are ambiguous:
    # default them, or fail.
    def resolve_ambiguity(quant, types)
      seen = {}
      types.each { |t| metas_of(t, seen) }
      remaining = []
      groups = {}
      quant.each do |ev|
        h, = T.spine(ev.type)
        if h.is_a?(T::TMeta) && !seen.key?(h)
          (groups[h] ||= []) << ev
        else
          remaining << ev
        end
      end
      groups.each do |meta, evs|
        default!(meta, evs)
        q, d = simplify(evs)
        raise 'typechecker: defaulting left constraints' unless q.empty? && d.empty?
      end
      remaining
    end

    def metas_of(t, acc)
      t = T.prune(t)
      case t
      when T::TMeta then acc[t] = true
      when T::TAp
        metas_of(t.fn, acc)
        metas_of(t.arg, acc)
      end
    end

    # Haskell 2010 defaulting, or GHCi's ExtendedDefaultRules at the prompt.
    def default!(meta, evs)
      names = evs.map { |ev| ev.klass.name.str }
      higher = evs.any? { |ev| ev.klass.var_arity.to_i > 0 }
      candidates =
        if @mode == :prompt
          ok = names.any? { |n| INTERACTIVE.include?(n) || NUMERIC.include?(n) }
          higher ? [T::LIST] : [T::UNIT, T::INTEGER, T::DOUBLE]
        else
          ok = names.any? { |n| NUMERIC.include?(n) } && names.all? { |n| STANDARD.include?(n) }
          higher ? [] : [T::INTEGER, T::DOUBLE]
        end
      if ok
        candidates.each do |c|
          next unless evs.all? { |ev| solvable?(Ev.new(ev.klass, c, ev.tok)) }

          meta.ref = c
          return
        end
      end
      p = T::Printer.new
      ctx = evs.map { |ev| "#{ev.klass.name.str} #{p.type(ev.type, 2)}" }.join(', ')
      raise Error.new(:compile, "Ambiguous type variable ‘#{p.type(meta)}’ prevents the constraint " \
                                "‘(#{ctx})’ from being solved", evs[0].tok&.line, evs[0].tok&.col, @source)
    end

    # At the top level nothing can be generalised any more: whatever is
    # still wanted is defaulted or an error.
    def solve_top
      w = @wanted
      @wanted = []
      saved = @level
      @level = -1
      quant, deferred = simplify(w)
      @level = saved
      all = quant + deferred
      all = resolve_ambiguity(all, [])
      raise 'typechecker: unsolved top-level constraints' unless all.empty?
    end

    # ---- types from syntax -------------------------------------------------------

    # A signature's scheme: type variables are quantified in order of
    # appearance (vars may be pre-seeded), with its context as constraints.
    def sig_scheme(ast, vars = {}, preds = [])
      t = convert(ast, vars, true)
      collect_context(ast, vars, preds)
      s = T::Scheme.new(vars.length, t, preds)
      s.names = vars.keys
      s
    end

    def collect_context(ast, vars, preds)
      return unless ast.is_a?(TQual) && ast.ref

      ast.ref.each { |klass, ct| preds << [klass, convert(ct, vars, true)] }
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
      when TQual then convert(t.type, vars, extend)
      else raise "typechecker: unexpected type syntax #{t.class}"
      end
    end

    def convert_app(t, vars, extend)
      head = t.is_a?(TApp) ? t.fn : t
      args = t.is_a?(TApp) ? t.args : []
      cargs = args.map { |a| convert(a, vars, extend) }
      return T.app(convert(head, vars, extend), cargs) if head.is_a?(TVar)
      return T.app(convert(head, vars, extend), cargs) unless head.is_a?(TCon)

      ti = head.ref.tyinfo
      if ti.nil?
        err(:compile, head, "‘#{head.name}’ is a class, not a type")
      end
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
      if cargs.length > tcon.arity
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

    # ---- classes and instances --------------------------------------------------------

    def define_class(ci)
      n = ci.supers.length + ci.methods.length
      info = Core::ConInfo.new("D:#{ci.name.str}", 0, n, "D:#{ci.name.str}")
      ci.dict_con = info
      ci.var_arity = class_var_arity(ci)
      ci.methods.each do |m|
        vars = { ci.tyvar => T::TGen.new(0) }
        s = sig_scheme(ci.sigs[m].type, vars, [[ci, T::TGen.new(0)]])
        @pending[m] = s
        ci.method_schemes[m] = s
      end
    end

    # How many type arguments the class variable takes (its kind's arity),
    # from how the method signatures apply it.
    def class_var_arity(ci)
      arity = 0
      ci.sigs.each_value { |sig| arity = [arity, applied_arity(sig.type, ci.tyvar)].max }
      arity
    end

    def applied_arity(t, v)
      case t
      when TApp
        here = t.fn.is_a?(TVar) && t.fn.name == v ? t.args.length : 0
        ([here, applied_arity(t.fn, v)] + t.args.map { |a| applied_arity(a, v) }).max
      when TFun then [applied_arity(t.from, v), applied_arity(t.to, v)].max
      when TList then applied_arity(t.elem, v)
      when TTuple then t.elems.map { |e| applied_arity(e, v) }.max || 0
      when TQual then applied_arity(t.type, v)
      else 0
      end
    end

    def check_defaults(ci)
      ci.defaults.each { |m, b| check_signed(b, ci.method_schemes[m]) }
    end

    def register_instance(inst)
      ci = inst.klass
      t = inst.type_ast
      head, args = instance_head(t)
      vars = args.map do |a|
        err(:compile, a, 'instance heads must be a type constructor applied to distinct type variables') unless a.is_a?(TVar)
        a.name
      end
      err(:compile, t, 'instance heads must use distinct type variables') if vars.uniq.length != vars.length
      want = head.arity - ci.var_arity.to_i
      unless vars.length == want
        err(:compile, t, "Expecting #{want} type argument(s) to ‘#{head.name}’ in an instance of ‘#{ci.name.str}’")
      end
      inst.head = head
      inst.tyvars = vars
      inst.context = []
      inst.context_ast.each do |klass, v, rhs|
        i = vars.index(v)
        err(:compile, t, "Not in scope: type variable ‘#{v}’") unless i
        if klass == :eq
          (inst.equalities ||= {})[i] = convert(rhs, {}, false)
        else
          inst.context << [klass, i]
        end
      end
      key = [ci, head.key]
      if @new_instances.key?(key)
        err(:compile, inst.tok, "Duplicate instance declarations: #{ci.name.str} #{head.name}")
      end
      inst.dict_name = @env.fresh("$f#{ci.name.str}#{head.name}", :var)
      inst.dict_name.global = true
      @new_instances[key] = inst
    end

    def instance_head(t)
      case t
      when TList then [T::LIST, [t.elem]]
      when TTuple then [T.tuple_con(t.elems.length), t.elems]
      when TFun then [T::ARROW, [t.from, t.to]]
      when TCon, TApp
        h = t.is_a?(TApp) ? t.fn : t
        args = t.is_a?(TApp) ? t.args : []
        err(:compile, t, 'instance heads must be a type constructor applied to type variables') unless h.is_a?(TCon)
        ti = h.ref.tyinfo
        err(:compile, t, "‘#{h.name}’ is a class, not a type") unless ti
        err(:compile, t, "instances of type synonyms are not supported: ‘#{h.name}’") if ti.synonym
        [ti.tcon, args]
      else
        err(:compile, t, 'malformed instance head')
      end
    end

    # The scheme a method implementation in `inst` must have.
    def instance_method_scheme(inst, m)
      ms = inst.klass.method_schemes[m]
      k = inst.tyvars.length
      eqs = inst.equalities || {}
      inst_type = T.app(inst.head, (0...k).map { |i| eqs[i] || T::TGen.new(i) })
      remap = lambda do |t|
        t = T.prune(t)
        case t
        when T::TGen then t.index.zero? ? inst_type : T::TGen.new(k + t.index - 1)
        when T::TAp then T::TAp.new(remap.call(t.fn), remap.call(t.arg))
        else t
        end
      end
      preds = inst.context.map { |c, i| [c, T::TGen.new(i)] } + ms.preds[1..-1].map { |c, t| [c, remap.call(t)] }
      s = T::Scheme.new(k + ms.nvars - 1, remap.call(ms.type), preds)
      s.names = inst.tyvars + (ms.names || [])[1..-1].to_a
      s
    end

    def check_instance(inst)
      ci = inst.klass
      inst.binds.each { |m, b| check_signed(b, instance_method_scheme(inst, m)) }
      # Superclass dictionaries, solved under the instance's context.
      @level += 1
      skols = inst.tyvars.map do |v|
        @ids += 1
        T::TSkol.new(v, @ids, @level)
      end
      givens = inst.context.map do |c, i|
        g = Ev.new(c, skols[i], inst.tok)
        g.solution = [:param, fresh_dict]
        g
      end
      @givens.push(givens)
      eqs = inst.equalities || {}
      inst_type = T.app(inst.head, (0...skols.length).map { |i| eqs[i] || skols[i] })
      supers = ci.supers.map { |sc| Ev.new(sc, inst_type, inst.tok) }
      q, d = simplify(supers)
      @givens.pop
      @level -= 1
      unless q.empty? && d.empty?
        no_instance((q + d)[0])
      end
      inst.context_dicts = givens.map { |g| g.solution[1] }
      inst.super_evs = supers
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
      outer = @wanted
      @wanted = []
      @level += 1
      unsigned = []
      binds.each do |b|
        b.names.each do |n|
          next if b.sigs.key?(n)

          bind_mono(n, fresh)
          unsigned << n
        end
      end
      binds.each do |b|
        case b.kind
        when :fun
          if b.sigs.key?(b.name)
            check_signed(b, @pending[b.name])
          else
            unify(@pending[b.name].type, infer_equations(b.eqs), b.eqs[0])
          end
        when :pat
          unless b.sigs.empty?
            unsupported(b.tok, 'type signatures for pattern-bound variables')
          end
          bind_pattern_vars(b.pat, infer_rhs(b.rhs))
        end
      end
      @level -= 1
      w = @wanted
      @wanted = outer
      quant, deferred = simplify(w)
      if restricted?(binds) && !quant.empty?
        # The monomorphism restriction: constrained variables of a pattern
        # or argument-less binding are not generalised.
        quant.each { |ev| lower_levels(ev.type) }
        deferred.concat(quant)
        quant = []
      end
      quant = resolve_ambiguity(quant, unsigned.map { |n| @pending[n].type })
      quant = minimize(quant)
      dicts = quant.map do |ev|
        ev.solution = [:param, fresh_dict]
        [ev, ev.solution[1]]
      end
      binds.each { |b| b.dicts = dicts unless b.kind == :fun && b.sigs.key?(b.name) }
      unsigned.each { |n| @pending[n] = generalize(@pending[n].type, quant) }
      @wanted.concat(deferred)
    end

    def restricted?(binds)
      @mode == :file && binds.any? do |b|
        b.kind == :pat || (b.kind == :fun && b.eqs[0].pats.empty? && !b.sigs.key?(b.name))
      end
    end

    def lower_levels(t)
      t = T.prune(t)
      case t
      when T::TMeta then t.level = @level if t.level > @level
      when T::TAp
        lower_levels(t.fn)
        lower_levels(t.arg)
      end
    end

    # Check a function binding against a signature scheme: its constraints
    # become dictionary parameters (b.dicts) available as givens.
    def check_signed(b, scheme)
      @level += 1
      skols = Array.new(scheme.nvars) do |i|
        @ids += 1
        T::TSkol.new((scheme.names && scheme.names[i]) || "a#{i}", @ids, @level)
      end
      givens = scheme.preds.map do |c, t|
        g = Ev.new(c, subst(t, skols), b.tok)
        g.solution = [:param, fresh_dict]
        g
      end
      b.dicts = givens.map { |g| [g, g.solution[1]] }
      b.signed = true
      outer = @wanted
      @wanted = []
      @givens.push(givens)
      t = infer_equations(b.eqs)
      unify(subst(scheme.type, skols), t, b.eqs[0])
      w = @wanted
      @wanted = outer
      @level -= 1
      quant, deferred = simplify(w)
      resolve_ambiguity(quant, [])
      @givens.pop
      @wanted.concat(deferred)
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
      when PLit
        if p.lit.kind == :integer || p.lit.kind == :float
          eq = ev_for('Eq', t, p)
          num = ev_for(p.lit.kind == :integer ? 'Num' : 'Fractional', t, p)
          p.ev = [eq, num]
        else
          unify(lit_type(p.lit, p), t, p)
        end
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

    # A pattern binding: its variables already have monotypes in the
    # group, which the pattern's types must agree with.
    def bind_pattern_vars(p, t)
      vars = {}
      collect_pat_vars(p, vars)
      before = {}
      vars.each_key { |n| before[n] = @pending[n].type }
      check_pat(p, t)
      vars.each_key do |n|
        unify(before[n], @pending[n].type, p)
        @pending[n] = T.mono(before[n])
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
      else
        a = fresh
        node.ev = [ev_for(lit.kind == :integer ? 'Num' : 'Fractional', a, node)]
        a
      end
    end

    # Whether a pattern can fail (then a `do` binding needs MonadFail).
    def failable?(p)
      case p
      when PVar, PWild, PLazy then false
      when PBang, PAs then failable?(p.pat)
      when PTuple then p.elems.any? { |e| failable?(e) }
      when PCon
        con = p.ref
        return failable?(p.args[0]) if con.tyinfo&.newtype

        con.con.siblings.length > 1 || p.args.any? { |a| failable?(a) }
      when PRec then p.con.ref.con.siblings.length > 1 || p.fields.any? { |_, a| failable?(a) }
      else true
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
      when Con, TupleCon then con_type(e, e.ref) # before Var: Con is a subclass of Var
      when Var then var_type(e, e.ref)
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
      when Neg
        t = infer(e.expr)
        e.ev = [ev_for('Num', t, e)]
        t
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
      when Do then infer_do(e)
      when ArithSeq
        a = fresh
        [e.from, e.thn, e.to].each { |x| unify(a, infer(x), x) if x }
        e.ev = [ev_for('Enum', a, e)]
        T.list(a)
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
        check_annotation(e, s)
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

    # e :: T. The expression must be at least as general as T; the result
    # is an instance of T (whose constraints become wanted).
    def check_annotation(e, scheme)
      @level += 1
      skols = Array.new(scheme.nvars) do |i|
        @ids += 1
        T::TSkol.new((scheme.names && scheme.names[i]) || "a#{i}", @ids, @level)
      end
      givens = scheme.preds.map do |c, t|
        g = Ev.new(c, subst(t, skols), e.tok)
        g.solution = [:param, fresh_dict]
        g
      end
      outer = @wanted
      @wanted = []
      @givens.push(givens)
      unify(subst(scheme.type, skols), infer(e.expr), e)
      w = @wanted
      @wanted = outer
      @level -= 1
      quant, deferred = simplify(w)
      resolve_ambiguity(quant, [])
      @givens.pop
      @wanted.concat(deferred)
      # The annotated expression abstracts over the annotation's
      # constraints (`groups` carries those givens to the desugarer); its
      # use instantiates them (`ev`).
      e.groups = givens
      instantiate(scheme, e)
    end

    # do { stmts }: Monad m; a refutable binding also needs MonadFail m.
    def infer_do(e)
      m = fresh
      e.ev = [ev_for('Monad', m, e)]
      result = nil
      e.stmts.each_with_index do |s, i|
        last = i == e.stmts.length - 1
        case s
        when BindStmt
          a = fresh
          unify(T.app(m, [a]), infer(s.expr), s.expr)
          check_pat(s.pat, a)
          s.ev = failable?(s.pat) ? [ev_for('MonadFail', m, s)] : []
        when LetStmt then infer_groups(s.groups)
        else
          t = infer(s.expr)
          b = fresh
          unify(T.app(m, [b]), t, s.expr)
          result = t if last
        end
      end
      result
    end

    def var_type(node, name)
      s = scheme_of(name)
      raise "typechecker: no type for #{name.str}" unless s

      instantiate(s, node)
    end

    def op_type(item)
      r = item.ref
      t = r.is_a?(Con) ? con_type(r, r.ref) : var_type(r, r.ref)
      r.ty = t
      t
    end
  end
end
