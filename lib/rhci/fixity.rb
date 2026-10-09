# frozen_string_literal: true

module Rhci
  # Resolves AST::OpSeq / AST::POpSeq into BinOp / Neg / infix PCon using
  # operator fixities (Report 10.6), checks sections, and rejects
  # pattern-only syntax left in expression position.
  #
  # Fixities are lexically scoped: a binding shadows the fixity of the name
  # it shadows (to infixl 9) unless the same declaration group declares
  # one. Resolution is an iterative operator-precedence loop that makes
  # the Report's decisions, including its rule for prefix negation.
  class FixityResolver
    include AST

    DEFAULT = [:left, 9].freeze

    # Prelude and the default-scope modules. Replaced by the Prelude's own
    # fixity declarations once the Prelude is written in Haskell.
    BASE = {}
    [
      [:right, 9, %w[.]], [:left, 9, %w[!!]],
      [:right, 8, %w[^ ^^ **]],
      [:left, 7, %w[* / quot rem div mod]],
      [:left, 6, %w[+ -]], [:right, 6, %w[<>]],
      [:right, 5, %w[: ++]], [:none, 5, %w[\\\\]],
      [:none, 4, %w[== /= < <= >= > elem notElem]],
      [:left, 4, %w[<$> <$ $> <*> *> <*]],
      [:left, 3, %w[<|>]], [:right, 3, %w[&&]], [:right, 2, %w[||]],
      [:left, 1, %w[>> >>= & <&>]], [:right, 1, %w[=<< >=> <=<]],
      [:right, 0, %w[$ $! seq]], [:left, 0, %w[on]] # lint:ok (the Haskell operator $!)
    ].each do |assoc, prec, ops|
      ops.each { |o| BASE[o] = [assoc, prec].freeze }
    end
    BASE.freeze

    # `outer` is the session's table for names defined at earlier prompts.
    def initialize(outer = nil, source = '<interactive>')
      @scopes = [BASE]
      @scopes << outer if outer
      @source = source
    end

    # Returns [resolved_node, layer], where `layer` maps the names this input
    # binds at top level to their fixities (nil for expressions).
    def repl(node)
      case node
      when ReplExpr then [ReplExpr.new(node.tok, expr(node.expr)), nil]
      when ReplBind
        e = expr(node.expr)
        p = pat(node.pat)
        layer = {}
        pat_vars(node.pat).each { |n| layer[n] = DEFAULT }
        [ReplBind.new(node.tok, p, e), layer]
      when ReplLet, ReplDecls
        layer = group_layer(node.decls)
        decls = within(layer) { node.decls.map { |d| decl(d) } }
        [node.is_a?(ReplLet) ? ReplLet.new(node.tok, decls) : ReplDecls.new(node.tok, decls), layer]
      else
        [node, nil]
      end
    end

    def module_decl(m)
      layer = group_layer(m.decls)
      decls = within(layer) { m.decls.map { |d| decl(d) } }
      ModuleDecl.new(m.tok, m.name, m.exports, m.imports, decls)
    end

    def expr(e)
      case e
      when Var, Con, Lit, TupleCon, Wildcard, Hole then e
      when OpSeq then resolve_seq(e.items, false)
      when App then App.new(e.tok, expr(e.fn), e.args.map { |a| expr(a) })
      when Paren then Paren.new(e.tok, expr(e.expr))
      when LeftSection then left_section(e)
      when RightSection then right_section(e)
      when Lambda
        within(fresh(pats_vars(e.pats))) do
          Lambda.new(e.tok, e.pats.map { |p| pat(p) }, expr(e.body))
        end
      when Let
        layer = group_layer(e.decls)
        within(layer) { Let.new(e.tok, e.decls.map { |d| decl(d) }, expr(e.body)) }
      when If then If.new(e.tok, expr(e.cond), expr(e.then_e), expr(e.else_e))
      when Case then Case.new(e.tok, expr(e.scrut), e.alts.map { |a| alt(a) })
      when Do then Do.new(e.tok, stmts(e.stmts) { nil }[0])
      when Tuple then Tuple.new(e.tok, e.elems.map { |x| expr(x) })
      when List then List.new(e.tok, e.elems.map { |x| expr(x) })
      when ArithSeq
        ArithSeq.new(e.tok, expr(e.from), e.thn && expr(e.thn), e.to && expr(e.to))
      when Comp
        quals, head = stmts(e.quals) { expr(e.expr) }
        Comp.new(e.tok, head, quals)
      when Annot then Annot.new(e.tok, expr(e.expr), e.type)
      when RecCon then RecCon.new(e.tok, e.con, e.fields.map { |f, x| [f, expr(x)] })
      when RecUpd then RecUpd.new(e.tok, expr(e.expr), e.fields.map { |f, x| [f, expr(x)] })
      when AsPat then error(e.tok, "as-pattern in expression context: #{e.name}@")
      when LazyPat then error(e.tok, 'lazy pattern in expression context: ~')
      when BangPat then error(e.tok, 'bang pattern in expression context: !')
      else raise "FixityResolver: unexpected #{e.class}"
      end
    end

    def pat(p)
      case p
      when PVar, PWild, PLit then p
      when PCon then PCon.new(p.tok, p.con, p.args.map { |a| pat(a) })
      when PTuple then PTuple.new(p.tok, p.elems.map { |a| pat(a) })
      when PList then PList.new(p.tok, p.elems.map { |a| pat(a) })
      when PAs then PAs.new(p.tok, p.name, pat(p.pat))
      when PLazy then PLazy.new(p.tok, pat(p.pat))
      when PBang then PBang.new(p.tok, pat(p.pat))
      when PRec then PRec.new(p.tok, p.con, p.fields.map { |f, x| [f, pat(x)] })
      when POpSeq then resolve_seq(p.items, true)
      else raise "FixityResolver: unexpected pattern #{p.class}"
      end
    end

    private

    def error(tok, msg)
      raise ParseError.new(msg, tok.line, tok.col, @source)
    end

    def within(layer)
      @scopes.push(layer)
      yield
    ensure
      @scopes.pop
    end

    def fresh(names)
      layer = {}
      names.each { |n| layer[n] = DEFAULT }
      layer
    end

    def fixity(item)
      name = item.name
      return BASE[name] || DEFAULT if item.ref.qual

      i = @scopes.length - 1
      while i >= 0
        f = @scopes[i][name]
        return f if f

        i -= 1
      end
      DEFAULT
    end

    def describe(item, f)
      kw = { left: 'infixl', right: 'infixr', none: 'infix' }[f[0]]
      name = item.backtick ? "`#{item.name}`" : item.name
      "‘#{name}’ [#{kw} #{f[1]}]"
    end

    # ---- the operator-precedence loop ---------------------------------------

    def resolve_seq(items, pattern)
      operands = []
      ops = [] # entries: [item, assoc, prec]; item is a NegMark or OpItem
      items.each do |it|
        if it.is_a?(NegMark)
          top = ops.last
          if top && top[2] >= 6
            error(it.tok, "Precedence parsing error: cannot mix #{describe_entry(top)} and prefix `-' [infixl 6] " \
                          'in the same infix expression')
          end
          ops << [it, :left, 6]
        elsif it.is_a?(OpItem)
          f = fixity(it)
          while (top = ops.last)
            if top[2] == f[1] && (top[1] != f[0] || f[0] == :none)
              error(it.tok, "Precedence parsing error: cannot mix #{describe_entry(top)} and #{describe(it, f)} " \
                            'in the same infix expression')
            end
            break unless top[2] > f[1] || (top[2] == f[1] && top[1] == :left)

            reduce(ops, operands, pattern)
          end
          ops << [it, f[0], f[1]]
        else
          operands << (pattern ? pat(it) : expr(it))
        end
      end
      reduce(ops, operands, pattern) until ops.empty?
      operands[0]
    end

    def describe_entry(entry)
      item = entry[0]
      return "prefix `-' [infixl 6]" if item.is_a?(NegMark)

      describe(item, [entry[1], entry[2]])
    end

    def reduce(ops, operands, pattern)
      item, = ops.pop
      if item.is_a?(NegMark)
        x = operands.pop
        if pattern
          unless x.is_a?(PLit) && !x.negative && (x.lit.kind == :integer || x.lit.kind == :float)
            error(item.tok, 'parse error in pattern: only numeric literals may be negated')
          end
          operands << PLit.new(item.tok, x.lit, true)
        else
          operands << Neg.new(item.tok, x)
        end
      else
        r = operands.pop
        l = operands.pop
        operands << (pattern ? PCon.new(item.tok, item.ref, [l, r]) : BinOp.new(item.tok, item.ref, l, r))
      end
    end

    # (op e): resolving `<hole> op e` must group as `<hole> op (e)`.
    def right_section(e)
      hole = Hole.new(e.tok)
      inner = e.expr.is_a?(OpSeq) ? e.expr.items : [e.expr]
      r = resolve_seq([hole, e.op] + inner, false)
      section_error(e.op) unless r.is_a?(BinOp) && r.op.equal?(e.op.ref) && r.left.equal?(hole)
      RightSection.new(e.tok, e.op, r.right)
    end

    # (e op): resolving `e op <hole>` must group as `(e) op <hole>`.
    def left_section(e)
      hole = Hole.new(e.tok)
      inner = e.expr.is_a?(OpSeq) ? e.expr.items : [e.expr]
      r = resolve_seq(inner + [e.op, hole], false)
      section_error(e.op) unless r.is_a?(BinOp) && r.op.equal?(e.op.ref) && r.right.equal?(hole)
      LeftSection.new(e.tok, r.left, e.op)
    end

    def section_error(op)
      error(op.tok, "The operator #{describe(op, fixity(op))} of a section must have lower precedence " \
                    'than that of the operand')
    end

    # ---- scopes ----------------------------------------------------------------

    def alt(a)
      within(fresh(pat_vars(a.pat))) { Alt.new(a.tok, pat(a.pat), rhs(a.rhs)) }
    end

    def decl(d)
      case d
      when FunEq
        within(fresh(pats_vars(d.pats))) do
          FunEq.new(d.tok, d.name, d.pats.map { |p| pat(p) }, rhs(d.rhs), d.infix)
        end
      when PatBind then PatBind.new(d.tok, pat(d.pat), rhs(d.rhs))
      when ClassDecl then ClassDecl.new(d.tok, d.context, d.name, d.tyvar, d.decls.map { |x| decl(x) })
      when InstDecl then InstDecl.new(d.tok, d.context, d.name, d.type, d.decls.map { |x| decl(x) })
      else d
      end
    end

    def rhs(r)
      return rhs_body(r, nil) unless r.where

      layer = group_layer(r.where)
      within(layer) { rhs_body(r, r.where.map { |d| decl(d) }) }
    end

    def rhs_body(r, where)
      if r.body
        Rhs.new(r.tok, expr(r.body), nil, where)
      else
        guards = r.guards.map do |quals, e|
          qs, body = stmts(quals) { expr(e) }
          [qs, body]
        end
        Rhs.new(r.tok, nil, guards, where)
      end
    end

    # Statements/qualifiers scope sequentially; the block resolves whatever
    # they scope over. Returns [resolved_stmts, block_result].
    def stmts(list)
      pushed = 0
      out = []
      list.each do |s|
        case s
        when BindStmt
          e = expr(s.expr)
          p = pat(s.pat)
          @scopes.push(fresh(pat_vars(s.pat)))
          pushed += 1
          out << BindStmt.new(s.tok, p, e)
        when LetStmt
          layer = group_layer(s.decls)
          @scopes.push(layer)
          pushed += 1
          out << LetStmt.new(s.tok, s.decls.map { |d| decl(d) })
        else
          out << ExprStmt.new(s.tok, expr(s.expr))
        end
      end
      result = yield
      [out, result]
    ensure
      pushed.times { @scopes.pop } if pushed
    end

    # Fixities of the names one declaration group binds.
    def group_layer(decls)
      bound = {}
      fix = {}
      decls.each do |d|
        case d
        when FunEq then bound[d.name] = true
        when PatBind then pat_vars(d.pat).each { |n| bound[n] = true }
        when FixityDecl then d.ops.each { |o| fix[o] = [d.assoc, d.prec] }
        when DataDecl
          d.cons.each do |c|
            bound[c.name] = true
            c.field_names&.each { |f| bound[f] = true }
          end
        when ClassDecl
          d.decls.each do |x|
            x.names.each { |n| bound[n] = true } if x.is_a?(TypeSig)
            x.ops.each { |o| fix[o] = [x.assoc, x.prec] } if x.is_a?(FixityDecl)
          end
        end
      end
      layer = {}
      bound.each_key { |n| layer[n] = fix[n] || DEFAULT }
      fix.each_key do |n|
        next if bound.key?(n)

        tok = decls.find { |d| d.is_a?(FixityDecl) && d.ops.include?(n) }&.tok
        raise Error.new(:compile, "The fixity signature for ‘#{n}’ lacks an accompanying binding",
                        tok&.line, tok&.col, @source)
      end
      layer
    end

    def pats_vars(pats)
      names = []
      pats.each { |p| names.concat(pat_vars(p)) }
      names
    end

    def pat_vars(p)
      case p
      when PVar then [p.name]
      when PAs then [p.name] + pat_vars(p.pat)
      when PCon then pats_vars(p.args)
      when PTuple, PList then pats_vars(p.elems)
      when PLazy, PBang then pat_vars(p.pat)
      when PRec then pats_vars(p.fields.map { |_, x| x })
      when POpSeq then pats_vars(p.items.select { |i| !i.is_a?(OpItem) && !i.is_a?(NegMark) })
      else []
      end
    end
  end
end
