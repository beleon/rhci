# frozen_string_literal: true

module Rhci
  # A resolved identifier. Every binder gets its own Name (unique `uid`),
  # so shadowing never confuses later passes.
  #   kind :var (incl. primitives), :con, :field, :tycon
  class Name
    attr_reader :str, :uid, :kind
    # con: Core::ConInfo (constructors). tyinfo: TyInfo (type constructors,
    # and a constructor's own type). prim: primitive op (Symbol) for
    # `foreign import prim`. fields: a constructor's field Names (or nil).
    # strict: a constructor's strictness flags. field_cons: for a field,
    # [[constructor Name, index], ...]. global: top-level binding.
    attr_accessor :con, :tyinfo, :prim, :fields, :strict, :field_cons, :global
    # field_types: a constructor's field types as (renamed) AST types.
    # prim_arity: number of arguments of a primitive.
    # klass: the ClassInfo of a class Name; method_of: the ClassInfo a
    # method belongs to.
    attr_accessor :field_types, :prim_arity, :klass, :method_of

    def initialize(str, uid, kind)
      @str = str
      @uid = uid
      @kind = kind
    end

    def core
      "#{@str}%#{@uid}"
    end

    def inspect
      "#<Name #{@str}/#{@uid} #{@kind}>"
    end
  end

  # What a type constructor is. `synonym` is [params, AST type] for `type`.
  class TyInfo
    attr_reader :name, :tcon, :params, :cons, :newtype
    attr_accessor :synonym

    def initialize(name, tcon, params, cons, newtype = false)
      @name = name
      @tcon = tcon
      @params = params
      @cons = cons
      @newtype = newtype
    end
  end

  # A type class (Haskell 98: one parameter, superclasses, defaults).
  class ClassInfo
    attr_reader :name, :tyvar, :methods, :tok
    # supers: superclass ClassInfos, in declaration order. sigs: method
    # Name => TypeSig. defaults: method Name => RBind (the default's own
    # Name is the RBind's name). context_ast: [[class str, tyvar str]].
    # Filled by the checker: dict_con (the dictionary's ConInfo),
    # var_arity (number of type arguments the class variable takes),
    # instances (head key => InstInfo), method_schemes.
    attr_accessor :supers, :sigs, :defaults, :context_ast, :dict_con, :var_arity, :instances,
                  :method_schemes, :super_names

    def initialize(name, tyvar, tok)
      @name = name
      @tyvar = tyvar
      @tok = tok
      @methods = []
      @supers = []
      @sigs = {}
      @defaults = {}
      @instances = {}
      @method_schemes = {}
    end

    # All superclasses, transitively, as [ClassInfo, path of indices].
    def ancestors
      out = []
      work = []
      @supers.each_with_index { |c, i| work << [c, [i]] }
      until work.empty?
        c, path = work.shift
        next if out.any? { |o, _| o.equal?(c) }

        out << [c, path]
        c.supers.each_with_index { |sc, i| work << [sc, path + [i]] }
      end
      out
    end
  end

  # An instance declaration. type_ast: the instance head type; context_ast:
  # [[class str, tyvar str]]; binds: method Name => RBind of the
  # implementation. Filled by the checker: head (TCon), tyvars, context
  # ([[ClassInfo, tyvar index]]), dict_name (the global holding the
  # dictionary, or the function building it from context dictionaries).
  class InstInfo
    attr_reader :klass, :tok, :binds
    attr_accessor :type_ast, :context_ast, :head, :tyvars, :context, :dict_name, :derived
    # context_dicts: parameter names of the dictionary function (one per
    # context constraint); super_evs: evidence for the superclass fields.
    attr_accessor :context_dicts, :super_evs

    def initialize(klass, tok, type_ast, context_ast)
      @klass = klass
      @tok = tok
      @type_ast = type_ast
      @context_ast = context_ast
      @binds = {}
    end
  end

  # One binding of a declaration group. kind :fun (name, eqs) or :pat
  # (pat, rhs, names). sigs: Name => TypeSig. deps: Names of the group it
  # refers to.
  class RBind
    attr_reader :kind, :name, :eqs, :pat, :rhs, :names, :sigs, :tok
    # dicts: [[Ev, core name], ...] -- dictionary parameters the checker
    # abstracted the binding over: shared by an unsigned group, or the
    # binding's own when checked against a signature (signed: true).
    # prim_alias: for a method implementation that is just `m = prim`, the
    # primitive's Name (the desugarer then inlines saturated calls).
    attr_accessor :deps, :dicts, :signed, :prim_alias

    def initialize(kind, tok, name: nil, eqs: nil, pat: nil, rhs: nil, names: [])
      @kind = kind
      @tok = tok
      @name = name
      @eqs = eqs
      @pat = pat
      @rhs = rhs
      @names = names
      @sigs = {}
      @deps = {}
    end
  end

  # A renamed top-level input (REPL entry or module).
  class RTop
    attr_accessor :expr, :bind_pat, :groups, :tyinfos, :values, :types, :prims, :import, :classes, :instances

    def initialize
      @groups = []
      @tyinfos = []
      @classes = []
      @instances = []
      @values = {}
      @types = {}
      @prims = []
    end
  end

  # Session-wide names. Only committed after an input checks completely,
  # so a failed input changes nothing (as in GHCi).
  class NameEnv
    attr_reader :values, :types, :internal
    # Names whose definition the session refused as unsupported: using one
    # is unsupported too (GHCi would have defined it), not "not in scope".
    attr_reader :refused

    BUILTIN_TYPES = { '[]' => Types::LIST, '()' => Types::UNIT, '->' => Types::ARROW,
                      'Char' => Types::CHAR, 'Int' => Types::INT, 'Integer' => Types::INTEGER,
                      'Double' => Types::DOUBLE }.freeze

    def initialize
      @values = {}
      @types = {}
      @internal = {}
      @refused = {}
      @uid = 0
      BUILTIN_TYPES.each do |n, tcon|
        name = fresh(n, :tycon)
        name.tyinfo = TyInfo.new(name, tcon, [], [])
        @types[n] = name
      end
      unit = builtin_con('()', VM::Builtins::UNIT, @types['()'].tyinfo)
      nil_ = builtin_con('[]', VM::Builtins::NIL, @types['[]'].tyinfo)
      cons = builtin_con(':', VM::Builtins::CONS, @types['[]'].tyinfo)
      @types['()'].tyinfo.cons.push(unit)
      @types['[]'].tyinfo.cons.push(nil_, cons)
      @tuples = {}
    end

    def fresh(str, kind)
      @uid += 1
      Name.new(str, @uid, kind)
    end

    # The constructor Name of the n-tuple (shared).
    def tuple_con(n)
      @tuples[n] ||= begin
        tcon = Types.tuple_con(n)
        tname = fresh(tcon.name, :tycon)
        tname.tyinfo = TyInfo.new(tname, tcon, (1..n).map { |i| "t#{i}" }, [])
        c = builtin_con(tcon.name, VM::Builtins.tuple(n), tname.tyinfo)
        tname.tyinfo.cons.push(c)
        c
      end
    end

    # prelude: names GHC's default-scope modules do not export stay internal.
    def commit(top, prelude: false)
      top.types.each do |s, n|
        if prelude && !BASE_TYPES.key?(s)
          @internal["type:#{s}"] = n
          next
        end
        @types[s] = n
        @refused.delete(s)
      end
      top.values.each do |s, n|
        @refused.delete(s)
        if s.start_with?('rhci_') || (prelude && !BASE_VALUES.key?(s))
          @internal[s] = n
        else
          @values[s] = n
        end
      end
    end

    private

    def builtin_con(str, coninfo, tyinfo)
      n = fresh(str, :con)
      n.con = coninfo
      n.tyinfo = tyinfo
      n.strict = Array.new(coninfo.arity, false)
      n.global = true
      @values[str] = n
      n
    end
  end

  # Resolves names, groups equations into bindings, attaches signatures,
  # registers data types, and orders binding groups by dependency.
  class Renamer
    include AST

    # Constructors the machine itself produces, reused when the Prelude
    # declares their types.
    MACHINE_CONS = {
      'Bool' => [VM::Builtins::FALSE, VM::Builtins::TRUE],
      'Ordering' => [VM::Builtins::LT, VM::Builtins::EQ, VM::Builtins::GT],
      'IORes' => [VM::Builtins::IORES]
    }.freeze

    # fixity: lookup of an operator's [assoc, prec] (for derived Show).
    def initialize(env, source = '<interactive>', prelude: false, fixity: nil)
      @env = env
      @fixity = fixity
      @source = source
      @prelude = prelude
      @scopes = []
      @top = RTop.new
      @collectors = []
    end

    # ---- entry points ----------------------------------------------------------

    def repl(node)
      case node
      when ReplExpr
        expr(node.expr)
        @top.expr = node.expr
      when ReplBind
        expr(node.expr)
        @top.expr = node.expr
        names = bind_pattern_names(node.pat, {})
        names.each { |s, n| n.global = true; @top.values[s] = n } # rubocop:disable Style/Semicolon
        @top.bind_pat = node.pat
      when ReplLet then top_decls(node.decls)
      when ReplDecls then top_decls(node.decls)
      when ReplImport then @top.import = node.import
      end
      @top
    end

    def expression(e)
      expr(e)
      e
    end

    def module_decls(m)
      m.imports.each { |i| check_import(i) }
      top_decls(m.decls)
      @top
    end

    def check_import(imp)
      return if KNOWN_MODULES.key?(imp.module_name)

      raise Error.new(:scope, "Could not find module ‘#{imp.module_name}’", imp.tok.line, imp.tok.col, @source)
    end

    KNOWN_MODULES = {}
    %w[Prelude Data.List Data.Maybe Data.Char Data.Tuple Data.Function Data.Ord Data.Either
       Control.Monad].each { |m| KNOWN_MODULES[m] = true }

    private

    def err(kind, tok, msg)
      raise Error.new(kind, msg, tok&.line, tok&.col, @source)
    end

    def unsupported(tok, what)
      raise UnsupportedError.new("#{what} are not supported yet", tok&.line, tok&.col, @source)
    end

    # ---- lookup -----------------------------------------------------------------

    def lookup_value(str)
      i = @scopes.length - 1
      while i >= 0
        n = @scopes[i][str]
        return n if n

        i -= 1
      end
      @top.values[str] || @env.values[str] || (@allow_internal && str.start_with?('rhci_') ? @env.internal[str] : nil)
    end

    def resolve_value(node, str, qual, what)
      unsupported(node.tok, 'qualified names') if qual
      n = lookup_value(str)
      if n.nil?
        not_yet(node.tok, str, BASE_VALUES[str])
        msg = what == :con ? "Data constructor not in scope: #{str}" : "Variable not in scope: #{str}"
        err(:scope, node.tok, msg)
      end
      note_reference(n)
      n
    end

    def lookup_type(tok, str)
      return @env.tuple_con(str.length - 1).tyinfo.name if str.start_with?('(,')

      n = @top.types[str] || @env.types[str]
      unless n
        not_yet(tok, str, BASE_TYPES[str])
        err(:scope, tok, "Not in scope: type constructor or class ‘#{str}’")
      end
      n
    end

    # GHCi has this name in scope by default; rhci does not define it yet.
    def not_yet(tok, str, mod)
      if (why = @env.refused[str])
        raise UnsupportedError.new("‘#{str}’ could not be defined: #{why}", tok&.line, tok&.col, @source)
      end
      return unless mod && !@prelude

      raise UnsupportedError.new("‘#{str}’ (from #{mod}) is not implemented yet", tok&.line, tok&.col, @source)
    end

    def note_reference(n)
      @collectors.each { |set, deps| deps[n] = true if set.key?(n) }
    end

    def with_scope(names)
      @scopes.push(names)
      yield
    ensure
      @scopes.pop
    end

    # ---- top-level declarations ----------------------------------------------------

    def top_decls(decls)
      derived = []
      decls.each do |d|
        case d
        when ClassDecl then register_class(d)
        when DataDecl then derived.concat(register_data(d))
        when TypeSyn then register_synonym(d)
        end
      end
      @top.classes.each { |ci| resolve_class(ci) }
      @top.tyinfos.each { |ti| resolve_tyinfo(ti) }
      instances = decls.select { |d| d.is_a?(InstDecl) }
      value_decls = decls.reject do |d|
        d.is_a?(DataDecl) || d.is_a?(TypeSyn) || d.is_a?(ClassDecl) || d.is_a?(InstDecl)
      end
      binds = collect_binds(value_decls, true)
      binds.each { |b| b.names.each { |n| n.global = true; @top.values[n.str] = n } } # rubocop:disable Style/Semicolon
      @top.groups = rename_group(binds, @top.values)
      @top.classes.each { |ci| rename_defaults(ci) }
      instances.each { |d| register_instance(d, false) }
      derived.each { |d| register_instance(d, true) }
    end

    # ---- classes and instances ------------------------------------------------------

    def register_class(d)
      err(:compile, d.tok, "Multiple declarations of ‘#{d.name}’") if @top.types.key?(d.name)
      cname = @env.fresh(d.name, :class)
      ci = ClassInfo.new(cname, d.tyvar, d.tok)
      cname.klass = ci
      ci.context_ast = d.context.map do |c, t|
        unsupported(t.tok, 'superclass constraints other than `C a`') unless t.is_a?(TVar) && t.name == d.tyvar
        [c, t]
      end
      @top.types[d.name] = cname
      @top.classes << ci
      d.decls.each do |x|
        next unless x.is_a?(TypeSig)

        x.names.each do |m|
          err(:compile, x.tok, "Multiple declarations of ‘#{m}’") if @top.values.key?(m) || ci.methods.any? { |n| n.str == m }
          mn = @env.fresh(m, :var)
          mn.global = true
          mn.method_of = ci
          ci.methods << mn
          ci.sigs[mn] = x
          @top.values[m] = mn
        end
      end
      @class_decls ||= {}
      @class_decls[ci] = d
    end

    def resolve_class(ci)
      ci.supers = ci.context_ast.map do |c, t|
        n = lookup_type(t.tok, c)
        err(:compile, t.tok, "‘#{c}’ is not a class") unless n.kind == :class
        n.klass
      end
      ci.sigs.each_value { |sig| type(sig.type) }
    end

    # Default method implementations in a class body.
    def rename_defaults(ci)
      d = @class_decls[ci]
      eqs = d.decls.select { |x| x.is_a?(FunEq) || x.is_a?(PatBind) }
      method_binds(eqs, ci, d.tok).each { |m, b| ci.defaults[m] = b }
    end

    # Group a class/instance body's equations by method; each gets a fresh
    # implementation Name. Returns {method Name => RBind}.
    def method_binds(decls, ci, tok)
      out = {}
      decls.each do |x|
        err(:parse, x.tok, 'pattern bindings are not allowed in class or instance declarations') unless x.is_a?(FunEq)
        m = ci.methods.find { |n| n.str == x.name }
        err(:compile, x.tok, "‘#{x.name}’ is not a (visible) method of class ‘#{ci.name.str}’") unless m
        b = out[m]
        if b
          if b.eqs[0].pats.length != x.pats.length
            err(:compile, x.tok, "Equations for ‘#{x.name}’ have different numbers of arguments")
          end
          b.eqs << x
        else
          impl = @env.fresh(x.name, :var)
          impl.global = true
          out[m] = RBind.new(:fun, x.tok, name: impl, eqs: [x], names: [impl])
        end
      end
      out.each_value do |b|
        b.eqs.each { |eq| equation(eq, b.name) }
        eq = b.eqs[0]
        body = eq.rhs.body
        if b.eqs.length == 1 && eq.pats.empty? && body.is_a?(Var) && !eq.rhs.where && body.ref&.prim
          b.prim_alias = body.ref
        end
      end
      out
    end

    def register_instance(d, derived)
      cn = lookup_type(d.tok, d.name)
      err(:compile, d.tok, "‘#{d.name}’ is not a class") unless cn.kind == :class
      ci = cn.klass
      type(d.type)
      ctx = d.context.map do |c, t|
        unsupported(t.tok, 'instance contexts other than `C a`') unless t.is_a?(TVar)
        n = lookup_type(t.tok, c)
        err(:compile, t.tok, "‘#{c}’ is not a class") unless n.kind == :class
        [n.klass, t.name]
      end
      inst = InstInfo.new(ci, d.tok, d.type, ctx)
      inst.derived = derived
      @allow_internal = derived
      begin
        method_binds(d.decls, ci, d.tok).each { |m, b| inst.binds[m] = b }
      ensure
        @allow_internal = false
      end
      @top.instances << inst
    end

    def register_data(d)
      err(:compile, d.tok, "Multiple declarations of ‘#{d.name}’") if @top.types.key?(d.name)
      tname = @env.fresh(d.name, :tycon)
      tcon = Types::TCon.new(d.name, d.tyvars.length, "#{d.name}%#{tname.uid}")
      ti = TyInfo.new(tname, tcon, d.tyvars, [], d.newtype)
      tname.tyinfo = ti
      @top.types[d.name] = tname
      @top.tyinfos << ti
      if d.newtype && (d.cons.length != 1 || d.cons[0].fields.length != 1)
        err(:compile, d.tok, 'A newtype must have exactly one constructor with exactly one field')
      end
      machine = @prelude ? MACHINE_CONS[d.name] : nil
      infos = machine || Core.data_type(d.name, d.cons.map { |c| [c.name, c.fields.length] })
      d.cons.each_with_index do |c, i|
        err(:compile, c.tok, "Multiple declarations of ‘#{c.name}’") if @top.values.key?(c.name)
        cn = @env.fresh(c.name, :con)
        cn.con = infos[i]
        cn.tyinfo = ti
        cn.strict = c.fields.map { |strict, _| strict }
        cn.field_types = c.fields.map { |_, t| t }
        cn.global = true
        @top.values[c.name] = cn
        ti.cons << cn
        next unless c.field_names

        cn.fields = []
        c.field_names.each_with_index do |f, j|
          fn = @top.values[f]
          if fn.nil? || fn.kind != :field
            err(:compile, c.tok, "Multiple declarations of ‘#{f}’") if fn
            fn = @env.fresh(f, :field)
            fn.field_cons = []
            fn.global = true
            @top.values[f] = fn
          end
          fn.field_cons << [cn, j]
          cn.fields << fn
        end
      end
      @data_decls ||= {}
      @data_decls[ti] = d
      Derive.instances(d, @source, @fixity)
    end

    def register_synonym(d)
      err(:compile, d.tok, "Multiple declarations of ‘#{d.name}’") if @top.types.key?(d.name)
      tname = @env.fresh(d.name, :tycon)
      ti = TyInfo.new(tname, nil, d.tyvars, [])
      ti.synonym = [d.tyvars, d.type]
      tname.tyinfo = ti
      @top.types[d.name] = tname
      @top.tyinfos << ti
    end

    # Resolve the type names inside constructor fields and synonyms.
    def resolve_tyinfo(ti)
      if ti.synonym
        type(ti.synonym[1], ti.params)
        return
      end
      d = @data_decls[ti]
      d.cons.each { |c| c.fields.each { |_, t| type(t, ti.params) } }
    end

    # ---- types -------------------------------------------------------------------------

    # Resolve type constructor names (sets `ref`). `scoped` lists type
    # variables in scope (data parameters); nil means any variable is fine.
    def type(t, scoped = nil)
      case t
      when TCon then t.ref = lookup_type(t.tok, t.name)
      when TVar
        if scoped && !scoped.include?(t.name)
          err(:scope, t.tok, "Not in scope: type variable ‘#{t.name}’")
        end
      when TApp
        type(t.fn, scoped)
        t.args.each { |a| type(a, scoped) }
      when TFun
        type(t.from, scoped)
        type(t.to, scoped)
      when TList then type(t.elem, scoped)
      when TTuple then t.elems.each { |e| type(e, scoped) }
      when TQual
        t.ref = t.context.map do |c, ct|
          n = lookup_type(ct.tok, c)
          err(:compile, ct.tok, "‘#{c}’ is not a class") unless n.kind == :class
          type(ct, scoped)
          [n.klass, ct]
        end
        type(t.type, scoped)
      end
    end

    # ---- binding groups -------------------------------------------------------------

    # Group equations into bindings and attach signatures. Names are fresh.
    def collect_binds(decls, top)
      binds = []
      by_str = {}
      sigs = []
      decls.each do |d|
        case d
        when FunEq
          last = binds.last
          if last && last.kind == :fun && last.name.str == d.name && !d.pats.empty?
            if last.eqs[0].pats.length != d.pats.length
              err(:compile, d.tok, "Equations for ‘#{d.name}’ have different numbers of arguments")
            end
            last.eqs << d
            next
          end
          conflict(by_str, d.name, d.tok)
          n = @env.fresh(d.name, :var)
          b = RBind.new(:fun, d.tok, name: n, eqs: [d], names: [n])
          by_str[d.name] = n
          binds << b
        when PatBind
          names = bind_pattern_names(d.pat, {})
          names.each_key { |s| conflict(by_str, s, d.tok) }
          names.each { |s, n| by_str[s] = n }
          binds << RBind.new(:pat, d.tok, pat: d.pat, rhs: d.rhs, names: names.values)
        when TypeSig then sigs << d
        when FixityDecl then nil
        when ForeignPrim
          err(:parse, d.tok, 'foreign declarations are not supported') unless @prelude && top
          conflict(by_str, d.name, d.tok)
          n = @env.fresh(d.name, :var)
          n.prim = d.op.to_sym
          n.prim_arity = fn_arity(d.type)
          by_str[d.name] = n
          b = RBind.new(:prim, d.tok, name: n, names: [n])
          b.sigs[n] = TypeSig.new(d.tok, [d.name], d.type)
          binds << b
        else
          err(:parse, d.tok, 'parse error: declaration not allowed here')
        end
      end
      owner = {}
      binds.each { |b| b.names.each { |n| owner[n] = b } }
      sigs.each do |s|
        s.names.each do |str|
          n = by_str[str]
          err(:compile, s.tok, "The type signature for ‘#{str}’ lacks an accompanying binding") unless n
          b = owner[n]
          err(:compile, s.tok, "Duplicate type signatures for ‘#{str}’") if b.sigs.key?(n)
          b.sigs[n] = s
        end
      end
      binds
    end

    def fn_arity(t)
      t = t.type if t.is_a?(TQual)
      n = 0
      while t.is_a?(TFun)
        n += 1
        t = t.to
      end
      n
    end

    def conflict(by_str, str, tok)
      err(:compile, tok, "Conflicting definitions for ‘#{str}’") if by_str.key?(str)
    end

    # Rename the bodies of a group whose names are already in scope, then
    # order it into strongly connected components (dependencies first).
    def rename_group(binds, _scope)
      group_set = {}
      binds.each { |b| b.names.each { |n| group_set[n] = b } }
      binds.each do |b|
        b.sigs.each_value { |s| type(s.type) }
        next if b.kind == :prim

        deps = {}
        @collectors.push([group_set, deps])
        begin
          if b.kind == :fun
            b.eqs.each { |eq| equation(eq, b.name) }
          else
            rhs(b.rhs)
            vars = {}
            b.names.each { |n| vars[n.str] = n }
            pattern(b.pat, vars)
          end
        ensure
          @collectors.pop
        end
        # References to names with a signature do not constrain inference
        # order (Report 4.5.2).
        deps.each_key do |n|
          owner = group_set[n]
          b.deps[owner] = true unless owner.sigs.key?(n)
        end
      end
      sccs(binds)
    end

    def equation(eq, name)
      eq.ref = name
      vars = {}
      eq.pats.each { |p| bind_pattern_names(p, vars) }
      with_scope(vars) do
        eq.pats.each { |p| pattern(p, vars) }
        rhs(eq.rhs)
      end
    end

    # Iterative Tarjan; components come out dependencies-first.
    def sccs(binds)
      index = {}
      low = {}
      on = {}
      stack = []
      out = []
      counter = 0
      binds.each do |root|
        next if index.key?(root)

        work = [[root, root.deps.keys, 0]]
        index[root] = low[root] = counter
        counter += 1
        stack.push(root)
        on[root] = true
        until work.empty?
          frame = work.last
          v, succ, i = frame
          if i < succ.length
            frame[2] += 1
            w = succ[i]
            if !index.key?(w)
              index[w] = low[w] = counter
              counter += 1
              stack.push(w)
              on[w] = true
              work.push([w, w.deps.keys, 0])
            elsif on[w]
              low[v] = index[w] if index[w] < low[v]
            end
          else
            work.pop
            unless work.empty?
              parent = work.last[0]
              low[parent] = low[v] if low[v] < low[parent]
            end
            if low[v] == index[v]
              comp = []
              loop do
                w = stack.pop
                on[w] = false
                comp << w
                break if w.equal?(v)
              end
              out << comp.reverse
            end
          end
        end
      end
      out
    end

    # ---- right-hand sides, expressions, statements ---------------------------------

    def rhs(r)
      if r.where
        binds = collect_binds(r.where, false)
        scope = {}
        binds.each { |b| b.names.each { |n| scope[n.str] = n } }
        with_scope(scope) do
          r.groups = rename_group(binds, scope)
          rhs_body(r)
        end
      else
        rhs_body(r)
      end
    end

    def rhs_body(r)
      if r.body
        expr(r.body)
      else
        r.guards.each { |quals, e| stmts(quals) { expr(e) } }
      end
    end

    # Statements/qualifiers scope sequentially over the rest and the block.
    def stmts(list)
      pushed = 0
      list.each do |s|
        case s
        when BindStmt
          expr(s.expr)
          vars = bind_pattern_names(s.pat, {})
          pattern(s.pat, vars)
          @scopes.push(vars)
          pushed += 1
        when LetStmt
          binds = collect_binds(s.decls, false)
          scope = {}
          binds.each { |b| b.names.each { |n| scope[n.str] = n } }
          @scopes.push(scope)
          pushed += 1
          s.groups = rename_group(binds, scope)
        else
          expr(s.expr)
        end
      end
      yield
    ensure
      pushed.times { @scopes.pop } if pushed
    end

    def expr(e)
      case e
      when Var then e.ref = resolve_value(e, e.name, e.qual, :var)
      when Con then e.ref = con_ref(e)
      when TupleCon then e.ref = @env.tuple_con(e.arity)
      when Lit, Hole then nil
      when Wildcard then err(:compile, e.tok, 'Found hole: _')
      when App
        expr(e.fn)
        e.args.each { |a| expr(a) }
      when BinOp
        e.op.is_a?(Con) ? (e.op.ref = con_ref(e.op)) : expr(e.op)
        expr(e.left)
        expr(e.right)
      when Neg, Paren then expr(e.expr)
      when LeftSection, RightSection
        r = e.op.ref
        r.is_a?(Con) ? (r.ref = con_ref(r)) : expr(r)
        expr(e.expr)
      when Lambda
        vars = {}
        e.pats.each { |p| bind_pattern_names(p, vars) }
        with_scope(vars) do
          e.pats.each { |p| pattern(p, vars) }
          expr(e.body)
        end
      when Let
        binds = collect_binds(e.decls, false)
        scope = {}
        binds.each { |b| b.names.each { |n| scope[n.str] = n } }
        with_scope(scope) do
          e.groups = rename_group(binds, scope)
          expr(e.body)
        end
      when If
        expr(e.cond)
        expr(e.then_e)
        expr(e.else_e)
      when Case
        expr(e.scrut)
        e.alts.each do |a|
          vars = bind_pattern_names(a.pat, {})
          with_scope(vars) do
            pattern(a.pat, vars)
            rhs(a.rhs)
          end
        end
      when Do then stmts(e.stmts) { nil }
      when Tuple, List then e.elems.each { |x| expr(x) }
      when ArithSeq
        expr(e.from)
        expr(e.thn) if e.thn
        expr(e.to) if e.to
      when Comp then stmts(e.quals) { expr(e.expr) }
      when Annot
        expr(e.expr)
        type(e.type)
      when RecCon
        e.con.ref = con_ref(e.con)
        e.ref = record_fields(e, e.fields, e.con.ref)
        e.fields.each { |_, x| expr(x) }
      when RecUpd
        expr(e.expr)
        e.ref = record_fields(e, e.fields, nil)
        e.fields.each { |_, x| expr(x) }
      else
        raise "renamer: unexpected #{e.class}"
      end
    end

    def con_ref(c)
      return @env.values[c.name] if c.qual.nil? && ['()', '[]', ':'].include?(c.name)

      resolve_value(c, c.name, c.qual, :con)
    end

    # Field Names of a record construction/update, in source order.
    def record_fields(node, fields, con)
      seen = {}
      fields.map do |f, _|
        err(:compile, node.tok, "duplicate field name ‘#{f}’ in record construction") if seen.key?(f)
        seen[f] = true
        n = lookup_value(f)
        err(:scope, node.tok, "Not in scope: field ‘#{f}’") unless n && n.kind == :field
        if con && !(con.fields || []).include?(n)
          err(:compile, node.tok, "Constructor ‘#{con.str}’ does not have field ‘#{f}’")
        end
        n
      end
    end

    # ---- patterns -------------------------------------------------------------------

    # Fresh Names for the variables a pattern binds (str => Name), added to
    # `acc`; a repeated variable is an error.
    def bind_pattern_names(p, acc)
      case p
      when PVar
        err(:compile, p.tok, "Conflicting definitions for ‘#{p.name}’") if acc.key?(p.name)
        acc[p.name] = @env.fresh(p.name, :var)
      when PAs
        err(:compile, p.tok, "Conflicting definitions for ‘#{p.name}’") if acc.key?(p.name)
        acc[p.name] = @env.fresh(p.name, :var)
        bind_pattern_names(p.pat, acc)
      when PCon then p.args.each { |a| bind_pattern_names(a, acc) }
      when PTuple, PList then p.elems.each { |a| bind_pattern_names(a, acc) }
      when PLazy, PBang then bind_pattern_names(p.pat, acc)
      when PRec then p.fields.each { |_, a| bind_pattern_names(a, acc) }
      end
      acc
    end

    # Resolve constructors in a pattern and attach the binders' Names.
    def pattern(p, vars)
      case p
      when PVar then p.ref = vars && vars[p.name]
      when PAs
        p.ref = vars && vars[p.name]
        pattern(p.pat, vars)
      when PCon
        c = con_ref(p.con)
        p.ref = c
        if p.args.length != c.con.arity
          err(:compile, p.tok, "The constructor ‘#{c.str}’ should have #{c.con.arity} argument" \
                               "#{c.con.arity == 1 ? '' : 's'}, but has been given #{p.args.length}")
        end
        p.args.each { |a| pattern(a, vars) }
      when PTuple
        p.ref = @env.tuple_con(p.elems.length)
        p.elems.each { |a| pattern(a, vars) }
      when PList then p.elems.each { |a| pattern(a, vars) }
      when PLazy, PBang then pattern(p.pat, vars)
      when PRec
        c = con_ref(p.con)
        p.con.ref = c
        p.ref = record_fields(p, p.fields, c)
        p.fields.each { |_, a| pattern(a, vars) }
      end
    end
  end
end
