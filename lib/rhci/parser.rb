# frozen_string_literal: true

module Rhci
  # Recursive-descent parser for Haskell 2010 expressions, patterns, types
  # and declarations, GHCi inputs, and module files.
  #
  # Recursion follows syntactic nesting only (guarded by MAX_DEPTH); every
  # construct whose size grows with the input -- operator chains,
  # application spines, lists, blocks -- is a loop.
  #
  # Like GHC, declarations and patterns are first parsed as expressions and
  # then reinterpreted (`f x = ...`, `x : xs <- ...`), which avoids
  # unbounded lookahead. Operator sequences are left flat (AST::OpSeq) for
  # the FixityResolver, because fixities may be declared later.
  class Parser
    include AST

    MAX_DEPTH = 400

    # prelude: allow `foreign import prim` (the Prelude's primitives).
    def initialize(src, source = '<interactive>', prelude: false)
      @source = source
      @prelude = prelude
      @c = Cursor.new(Lexer.tokenize(src, source), source)
      @depth = 0
    end

    # ---- entry points ------------------------------------------------------

    # One GHCi input: an expression, `let` without `in`, `pat <- e`,
    # declarations, or an import.
    def parse_repl
      t = peek
      return ReplEmpty.new(t) if t.kind == :eof

      if at_kw?('import')
        imp = parse_import
        expect_eof
        return ReplImport.new(t, imp)
      end

      items = block { parse_top_item(true) }
      expect_eof
      classify_repl(t, items)
    end

    # A bare expression, as after `:type`.
    def parse_expression
      t = peek
      error_at(t) if t.kind == :eof
      e = parse_exp
      expect_eof
      e
    end

    # A whole source file.
    def parse_module
      t = peek
      name = 'Main'
      if at_kw?('module')
        advance
        name = parse_modid
        skip_export_list if at_special?('(')
        expect_kw('where')
      end
      imports = []
      decls = []
      block do
        if at_kw?('import')
          error_at(peek, 'import declarations must come before other declarations') unless decls.empty?
          imports << parse_import
        else
          item = parse_top_item(false)
          decls << item
        end
        nil
      end
      expect_eof
      ModuleDecl.new(t, name, nil, imports, decls)
    end

    private

    # ---- token helpers -------------------------------------------------------

    def peek
      @c.peek
    end

    def advance
      @c.advance
    end

    def at?(kind, text = nil)
      peek.is?(kind, text)
    end

    def at_special?(text)
      at?(:special, text)
    end

    def at_kw?(word)
      at?(:keyword, word)
    end

    def at_op?(text)
      at?(:reservedop, text)
    end

    def at_minus?
      t = peek
      t.kind == :varsym && t.text == '-'
    end

    def accept_special(text)
      return false unless at_special?(text)

      advance
      true
    end

    def expect_special(text)
      error_at(peek) unless at_special?(text)
      advance
    end

    def expect_kw(word)
      error_at(peek) unless at_kw?(word)
      advance
    end

    def expect_op(text)
      error_at(peek) unless at_op?(text)
      advance
    end

    def expect_eof
      error_at(peek) unless peek.kind == :eof
    end

    def error_at(tok, msg = nil)
      if msg.nil?
        msg = if tok.kind == :eof || tok.kind == :vsemi || tok.kind == :vrbrace
                'parse error (possibly incorrect indentation or mismatched brackets)'
              else
                "parse error on input ‘#{tok.text}’"
              end
      end
      raise ParseError.new(msg, tok.line, tok.col, @source)
    end

    def unsupported(tok, what)
      raise UnsupportedError.new("#{what} are not supported", tok.line, tok.col, @source)
    end

    def nest
      @depth += 1
      error_at(peek, 'expression nested too deeply') if @depth > MAX_DEPTH
      yield
    ensure
      @depth -= 1
    end

    # ---- layout blocks ---------------------------------------------------------

    # Items of a `{ ... }` block, explicit or by layout. The block yields
    # once per item; nil results are dropped.
    def block
      items = []
      case @c.open_block
      when :empty
        return items
      when :explicit
        loop do
          next if accept_special(';')
          break if at_special?('}')

          item = yield
          items << item unless item.nil?
          break unless at_special?(';')
        end
        expect_special('}')
      else
        loop do
          t = peek
          if t.kind == :vsemi || t.is?(:special, ';')
            advance
            next
          end
          if t.kind == :vrbrace
            advance
            break
          end
          if block_closer?(t)
            @c.close_implicit
            break
          end
          item = yield
          items << item unless item.nil?
          t = peek
          if t.kind == :vsemi || t.is?(:special, ';')
            advance
          elsif t.kind == :vrbrace
            advance
            break
          else
            @c.close_implicit # parse-error(t)
            break
          end
        end
      end
      items
    end

    CLOSERS = { 'in' => true, 'then' => true, 'else' => true, 'of' => true }.freeze

    def block_closer?(t)
      (t.kind == :keyword && CLOSERS.key?(t.text)) ||
        (t.kind == :special && (t.text == ')' || t.text == ']' || t.text == ',' || t.text == '}')) ||
        t.kind == :eof
    end

    # ---- REPL / top-level items ----------------------------------------------

    def classify_repl(t, items)
      return ReplEmpty.new(t) if items.empty?

      if items.length == 1
        it = items[0]
        case it
        when ExprStmt then return ReplExpr.new(t, it.expr)
        when LetStmt then return ReplLet.new(t, it.decls)
        when BindStmt then return ReplBind.new(t, it.pat, it.expr)
        when TypeSig
          if it.names.length == 1
            return ReplExpr.new(t, Annot.new(it.tok, Var.new(it.tok, it.names[0]), it.type))
          end
        end
      end
      items.each do |it|
        if it.is_a?(ExprStmt) || it.is_a?(LetStmt) || it.is_a?(BindStmt)
          error_at(it.tok, 'parse error: a statement cannot be combined with other declarations')
        end
      end
      ReplDecls.new(t, items)
    end

    # A top-level declaration; at the REPL also a statement.
    def parse_top_item(repl)
      t = peek
      if t.kind == :keyword
        case t.text
        when 'data' then return parse_data(false)
        when 'newtype' then return parse_data(true)
        when 'type' then return parse_type_syn
        when 'class' then return parse_class
        when 'instance' then return parse_instance
        when 'infix', 'infixl', 'infixr' then return parse_fixity
        when 'default' then unsupported(t, 'default declarations')
        when 'foreign'
          return parse_foreign_prim if @prelude

          unsupported(t, 'foreign declarations')
        when 'deriving' then unsupported(t, 'standalone deriving declarations')
        when 'import' then error_at(t, 'import declarations must come first')
        when 'let'
          return parse_let_item if repl
        end
      end
      repl ? parse_stmt_or_decl : parse_decl
    end

    # `let decls` (a statement) or `let decls in e` (an expression).
    def parse_let_item
      t = advance
      decls = block { parse_decl }
      return LetStmt.new(t, decls) unless at_kw?('in')

      advance
      ExprStmt.new(t, Let.new(t, decls, parse_exp))
    end

    def parse_stmt_or_decl
      t = peek
      e = parse_infixexp
      return parse_sig(e) if at_special?(',') && plain_var?(e)

      if at_op?('::')
        advance
        type = parse_qual_type
        return TypeSig.new(t, [e.name], type) if plain_var?(e)

        return ExprStmt.new(t, Annot.new(t, e, type))
      end
      return binding(e, parse_rhs('=')) if at_op?('=') || at_op?('|')

      if at_op?('<-')
        advance
        return BindStmt.new(t, to_pat(e), parse_exp)
      end
      ExprStmt.new(t, e)
    end

    def parse_foreign_prim
      t = advance # foreign
      error_at(peek) unless at_kw?('import')
      advance
      error_at(peek) unless at?(:varid, 'prim')
      advance
      op = advance
      error_at(op) unless op.kind == :string
      name = advance
      error_at(name) unless name.kind == :varid
      expect_op('::')
      ForeignPrim.new(t, AST.cps_to_s(op.value), name.text, parse_qual_type)
    end

    # A declaration inside let/where/class/instance (no statements).
    def parse_decl
      t = peek
      return parse_fixity if at_kw?('infix') || at_kw?('infixl') || at_kw?('infixr')

      e = parse_infixexp
      return parse_sig(e) if at_special?(',') && plain_var?(e)

      if at_op?('::')
        error_at(peek) unless plain_var?(e)
        advance
        return TypeSig.new(t, [e.name], parse_qual_type)
      end
      return binding(e, parse_rhs('=')) if at_op?('=') || at_op?('|')

      error_at(peek)
    end

    def plain_var?(e)
      e.is_a?(Var) && !e.is_a?(Con) && e.qual.nil?
    end

    # `x, y, z :: type` after the first name has been parsed.
    def parse_sig(first)
      names = [first.name]
      while accept_special(',')
        v = parse_aexp
        error_at(v.tok) unless plain_var?(v)
        names << v.name
      end
      expect_op('::')
      TypeSig.new(first.tok, names, parse_qual_type)
    end

    # Reinterpret the expression on the left of `=` as a function or
    # pattern binding.
    def binding(e, rhs)
      t = e.tok
      case e
      when OpSeq
        ops = varop_indices(e.items)
        return PatBind.new(t, to_pat(e), rhs) if ops.empty?

        error_at(e.items[ops[1]].tok) if ops.length > 1
        k = ops[0]
        pats = [to_pat(seq_of(e.items[0, k], t)), to_pat(seq_of(e.items[(k + 1)..-1], t))]
        FunEq.new(t, e.items[k].name, pats, rhs, true)
      when App
        fn = e.fn
        if plain_var?(fn)
          FunEq.new(t, fn.name, e.args.map { |a| to_pat(a) }, rhs)
        elsif fn.is_a?(Paren) && fn.expr.is_a?(OpSeq) && varop_indices(fn.expr.items).length == 1
          inner = binding(fn.expr, rhs)
          FunEq.new(t, inner.name, inner.pats + e.args.map { |a| to_pat(a) }, rhs, true)
        elsif fn.is_a?(Con)
          PatBind.new(t, to_pat(e), rhs)
        else
          error_at(t, 'parse error in function definition')
        end
      when Var
        return FunEq.new(t, e.name, [], rhs) if plain_var?(e)

        PatBind.new(t, to_pat(e), rhs)
      else
        PatBind.new(t, to_pat(e), rhs)
      end
    end

    def varop_indices(items)
      idx = []
      i = 0
      while i < items.length
        it = items[i]
        idx << i if it.is_a?(OpItem) && !it.con?
        i += 1
      end
      idx
    end

    def seq_of(items, tok)
      items.length == 1 ? items[0] : OpSeq.new(tok, items)
    end

    # ---- expressions ---------------------------------------------------------

    def parse_exp
      nest do
        e = parse_infixexp
        if at_op?('::')
          t = advance
          e = Annot.new(t, e, parse_qual_type)
        end
        e
      end
    end

    def parse_infixexp
      items, = parse_infix_items(false)
      seq_of(items, items[0].tok)
    end

    # Operands, operators and :neg markers. With `trailing`, stop before a
    # `)` that follows an operator and return that operator (a left section).
    def parse_infix_items(trailing)
      items = []
      loop do
        items << NegMark.new(advance) while at_minus?
        operand = parse_lexp
        items << operand
        break if operand.is_a?(Lambda) || operand.is_a?(Let) || operand.is_a?(If)

        op, width = operator_here
        break if op.nil?

        width.times { advance }
        if trailing && at_special?(')')
          return [items, op]
        end

        items << op
      end
      [items, nil]
    end

    # An operator at the cursor: [OpItem, token_count] or nil.
    def operator_here
      t = peek
      case t.kind
      when :varsym, :qvarsym
        [OpItem.new(t, Var.new(t, t.name, t.qual)), 1]
      when :consym, :qconsym
        [OpItem.new(t, Con.new(t, t.name, t.qual)), 1]
      when :special
        return nil unless t.text == '`'

        id = @c.raw(1)
        close = @c.raw(2)
        error_at(id) unless close.is?(:special, '`')
        case id.kind
        when :varid, :qvarid then [OpItem.new(t, Var.new(id, id.name, id.qual), true), 3]
        when :conid, :qconid then [OpItem.new(t, Con.new(id, id.name, id.qual), true), 3]
        else error_at(id)
        end
      end
    end

    def parse_lexp
      t = peek
      if t.kind == :reservedop && t.text == '\\'
        advance
        pats = []
        pats << to_pat(parse_aexp) until at_op?('->')
        error_at(peek) if pats.empty?
        advance
        return Lambda.new(t, pats, parse_exp)
      end
      if t.kind == :keyword
        case t.text
        when 'let'
          advance
          decls = block { parse_decl }
          expect_kw('in')
          return Let.new(t, decls, parse_exp)
        when 'if'
          advance
          c = parse_exp
          skip_semi_before('then')
          expect_kw('then')
          th = parse_exp
          skip_semi_before('else')
          expect_kw('else')
          return If.new(t, c, th, parse_exp)
        when 'case'
          advance
          scrut = parse_exp
          expect_kw('of')
          return Case.new(t, scrut, block { parse_alt })
        when 'do'
          advance
          stmts = block { parse_stmt }
          if stmts.empty? || !stmts.last.is_a?(ExprStmt)
            error_at(t, "the last statement in a 'do' block must be an expression")
          end
          return Do.new(t, stmts)
        end
      end
      parse_fexp
    end

    # DoAndIfThenElse: `if c; then a; else b` inside a layout block.
    def skip_semi_before(word)
      t = peek
      return unless t.kind == :vsemi || t.is?(:special, ';')

      advance if @c.raw.is?(:keyword, word) || (t.is?(:special, ';') && @c.raw(1).is?(:keyword, word))
    end

    def parse_fexp
      f = parse_aexp_rec
      args = []
      loop do
        if at_op?('@') && peek.value == :prefix
          unsupported(peek, 'type applications')
        end
        break unless aexp_start?

        args << parse_aexp_rec
      end
      args.empty? ? f : App.new(f.tok, f, args)
    end

    def aexp_start?
      t = peek
      case t.kind
      when :varid, :qvarid, :conid, :qconid, :integer, :float, :char, :string, :bang then true
      when :special then t.text == '(' || t.text == '['
      when :keyword then t.text == '_'
      when :reservedop then t.text == '~'
      else false
      end
    end

    # An aexp followed by any record construction/update braces.
    def parse_aexp_rec
      a = parse_aexp
      while at_special?('{')
        t = peek
        fields = parse_record_fields
        a = a.is_a?(Con) ? RecCon.new(t, a, fields) : RecUpd.new(t, a, fields)
      end
      a
    end

    def parse_record_fields
      advance # {
      fields = []
      unless at_special?('}')
        loop do
          t = peek
          error_at(t) unless t.kind == :varid || t.kind == :qvarid
          advance
          unsupported(t, 'record puns and wildcards') unless at_op?('=')
          advance
          fields << [t.text, parse_exp]
          break unless accept_special(',')
        end
      end
      expect_special('}')
      fields
    end

    def parse_aexp
      t = peek
      case t.kind
      when :varid, :qvarid
        advance
        if at_op?('@')
          case peek.value
          when :tight
            advance
            return AsPat.new(t, t.name, parse_aexp)
          when :prefix then unsupported(peek, 'type applications')
          else error_at(peek)
          end
        end
        Var.new(t, t.name, t.qual)
      when :conid, :qconid
        advance
        Con.new(t, t.name, t.qual)
      when :integer, :float, :char, :string
        advance
        Lit.new(t, t.kind, t.value)
      when :bang
        advance
        BangPat.new(t, parse_aexp)
      when :keyword
        error_at(t) unless t.text == '_'
        advance
        Wildcard.new(t)
      when :reservedop
        error_at(t) unless t.text == '~'
        advance
        LazyPat.new(t, parse_aexp)
      when :special
        return nest { parse_paren } if t.text == '('
        return nest { parse_bracket } if t.text == '['

        error_at(t)
      else
        error_at(t)
      end
    end

    def parse_paren
      t = advance # (
      if accept_special(')')
        return Con.new(t, '()')
      end
      if at_special?(',')
        commas = 0
        commas += 1 while accept_special(',')
        unsupported(t, 'tuple sections') unless at_special?(')')
        advance
        return TupleCon.new(t, commas + 1)
      end

      op, width = operator_here
      if op && !(op.ref.name == '-' && op.ref.qual.nil? && !op.backtick && !@c.raw(1).is?(:special, ')'))
        width.times { advance }
        if accept_special(')')
          error_at(t) if op.backtick
          return op.ref
        end
        e = parse_infixexp
        expect_special(')')
        return RightSection.new(t, op, e)
      end

      items, trailing = parse_infix_items(true)
      if trailing
        expect_special(')')
        return LeftSection.new(t, seq_of(items, items[0].tok), trailing)
      end
      e = seq_of(items, items[0].tok)
      e = Annot.new(advance, e, parse_qual_type) if at_op?('::')
      if at_special?(',')
        elems = [e]
        while accept_special(',')
          unsupported(t, 'tuple sections') if at_special?(')') || at_special?(',')
          elems << parse_exp
        end
        expect_special(')')
        return Tuple.new(t, elems)
      end
      expect_special(')')
      Paren.new(t, e)
    end

    def parse_bracket
      t = advance # [
      return Con.new(t, '[]') if accept_special(']')

      e1 = parse_exp
      return finish_range(t, e1, nil) if at_op?('..')

      if at_op?('|')
        advance
        quals = [parse_stmt]
        quals << parse_stmt while accept_special(',')
        expect_special(']')
        return Comp.new(t, e1, quals)
      end
      elems = [e1]
      if accept_special(',')
        e2 = parse_exp
        return finish_range(t, e1, e2) if at_op?('..')

        elems << e2
        elems << parse_exp while accept_special(',')
      end
      expect_special(']')
      List.new(t, elems)
    end

    def finish_range(t, from, thn)
      advance # ..
      to = at_special?(']') ? nil : parse_exp
      expect_special(']')
      ArithSeq.new(t, from, thn, to)
    end

    # A do statement or a qualifier (comprehension / guard).
    def parse_stmt
      t = peek
      return parse_let_item if at_kw?('let')

      e = parse_exp
      if at_op?('<-')
        advance
        return BindStmt.new(t, to_pat(e), parse_exp)
      end
      ExprStmt.new(t, e)
    end

    def parse_alt
      t = peek
      pat = to_pat(parse_infixexp)
      Alt.new(t, pat, parse_rhs('->'))
    end

    # `= e` / `-> e`, or guards `| quals = e ...`, then an optional `where`.
    def parse_rhs(sym)
      t = peek
      body = nil
      guards = nil
      if at_op?('|')
        guards = []
        while at_op?('|')
          advance
          quals = [parse_stmt]
          quals << parse_stmt while accept_special(',')
          expect_op(sym)
          guards << [quals, parse_exp]
        end
      else
        expect_op(sym)
        body = parse_exp
      end
      where = nil
      if at_kw?('where')
        advance
        where = block { parse_decl }
      end
      Rhs.new(t, body, guards, where)
    end

    # ---- patterns ----------------------------------------------------------

    def to_pat(e)
      case e
      when Con then PCon.new(e.tok, e, [])
      when Var
        error_at(e.tok, "qualified name in binding position: #{e.sexp}") if e.qual
        PVar.new(e.tok, e.name)
      when Wildcard then PWild.new(e.tok)
      when Lit then PLit.new(e.tok, e)
      when App
        error_at(e.tok, "parse error in pattern: #{e.fn.sexp}") unless e.fn.is_a?(Con)
        PCon.new(e.tok, e.fn, e.args.map { |a| to_pat(a) })
      when OpSeq
        items = e.items.map do |it|
          if it.is_a?(OpItem)
            error_at(it.tok, "parse error in pattern: #{it.sexp}") unless it.con?
            it
          elsif it.is_a?(NegMark)
            it
          else
            to_pat(it)
          end
        end
        POpSeq.new(e.tok, items)
      when Paren then to_pat(e.expr)
      when Tuple then PTuple.new(e.tok, e.elems.map { |x| to_pat(x) })
      when List then PList.new(e.tok, e.elems.map { |x| to_pat(x) })
      when AsPat then PAs.new(e.tok, e.name, to_pat(e.expr))
      when LazyPat then PLazy.new(e.tok, to_pat(e.expr))
      when BangPat then PBang.new(e.tok, to_pat(e.expr))
      when RecCon then PRec.new(e.tok, e.con, e.fields.map { |f, x| [f, to_pat(x)] })
      when Annot then unsupported(e.tok, 'pattern type signatures')
      else error_at(e.tok, 'parse error in pattern')
      end
    end

    # ---- types ---------------------------------------------------------------

    # [forall vs.] [context =>] type
    def parse_qual_type
      t = peek
      vars = []
      if t.is?(:varid, 'forall')
        advance
        vars << advance.text while at?(:varid)
        error_at(peek) unless at?(:varsym, '.')
        advance
      end
      ty = parse_type
      if at_op?('=>')
        advance
        return TQual.new(t, vars, to_context(ty), parse_type)
      end
      vars.empty? ? ty : TQual.new(t, vars, [], ty)
    end

    # btype -> btype -> ... (right-associative), built iteratively.
    def parse_type
      parts = [parse_btype]
      while at_op?('->')
        advance
        parts << parse_btype
      end
      ty = parts.pop
      ty = TFun.new(parts.last.tok, parts.pop, ty) until parts.empty?
      ty
    end

    def parse_btype
      f = parse_atype
      args = []
      args << parse_atype while atype_start?
      args.empty? ? f : TApp.new(f.tok, f, args)
    end

    def atype_start?
      t = peek
      case t.kind
      when :conid, :qconid then true
      when :varid then t.text != 'forall'
      when :special then t.text == '(' || t.text == '['
      else false
      end
    end

    def parse_atype
      t = peek
      case t.kind
      when :conid, :qconid
        advance
        TCon.new(t, t.text)
      when :varid
        advance
        TVar.new(t, t.text)
      when :special
        if t.text == '('
          nest { parse_paren_type }
        elsif t.text == '['
          advance
          return TCon.new(t, '[]') if accept_special(']')

          el = parse_type
          expect_special(']')
          TList.new(t, el)
        else
          error_at(t)
        end
      else
        error_at(t)
      end
    end

    def parse_paren_type
      t = advance # (
      return TCon.new(t, '()') if accept_special(')')

      if at_op?('->')
        advance
        expect_special(')')
        return TCon.new(t, '->')
      end
      if at_special?(',')
        commas = 0
        commas += 1 while accept_special(',')
        expect_special(')')
        return TCon.new(t, "(#{',' * commas})")
      end
      first = parse_qual_type
      if at_special?(',')
        elems = [first]
        elems << parse_type while accept_special(',')
        expect_special(')')
        return TTuple.new(t, elems)
      end
      expect_special(')')
      first
    end

    # A parsed type reinterpreted as a context: C a, (C a, D b), ().
    def to_context(ty)
      return [] if ty.is_a?(TCon) && ty.name == '()'

      list = ty.is_a?(TTuple) ? ty.elems : [ty]
      list.map do |a|
        error_at(a.tok, 'malformed class assertion') unless a.is_a?(TApp) && a.fn.is_a?(TCon)
        unsupported(a.tok, 'multi-parameter class constraints') unless a.args.length == 1
        [a.fn.name, a.args[0]]
      end
    end

    # ---- declarations ------------------------------------------------------

    def parse_fixity
      t = advance
      assoc = { 'infixl' => :left, 'infixr' => :right, 'infix' => :none }[t.text]
      prec = 9
      if at?(:integer)
        p = advance
        error_at(p, 'precedence out of range') if p.value > 9
        prec = p.value
      end
      ops = []
      loop do
        o = peek
        case o.kind
        when :varsym, :consym
          advance
          ops << o.text
        when :special
          error_at(o) unless o.text == '`'
          advance
          id = advance
          error_at(id) unless id.kind == :varid || id.kind == :conid
          expect_special('`')
          ops << id.text
        else
          error_at(o)
        end
        break unless accept_special(',')
      end
      FixityDecl.new(t, assoc, prec, ops)
    end

    # data/newtype T a b = C1 ... | C2 ... deriving (...)
    def parse_data(newtype)
      t = advance
      head = parse_btype
      unsupported(peek, 'datatype contexts') if at_op?('=>')
      name, tyvars = decl_head(head)
      cons = []
      if at_kw?('where')
        unsupported(peek, 'GADT-style declarations')
      elsif accept_op('=')
        cons << parse_constr
        cons << parse_constr while accept_op('|')
      end
      DataDecl.new(t, name, tyvars, cons, parse_deriving, newtype)
    end

    def accept_op(text)
      return false unless at_op?(text)

      advance
      true
    end

    # T a b  ->  ["T", ["a", "b"]]
    def decl_head(ty)
      fn = ty.is_a?(TApp) ? ty.fn : ty
      args = ty.is_a?(TApp) ? ty.args : []
      error_at(ty.tok, 'malformed declaration head') unless fn.is_a?(TCon) && fn.name[0] >= 'A' && fn.name[0] <= 'Z'
      vars = args.map do |a|
        error_at(a.tok, 'malformed declaration head') unless a.is_a?(TVar)
        a.name
      end
      [fn.name, vars]
    end

    def parse_constr
      t = peek
      unsupported(t, 'existential quantification') if t.is?(:varid, 'forall')
      if t.kind == :conid && @c.raw(1).is?(:special, '{')
        advance
        advance # {
        names = []
        fields = []
        unless at_special?('}')
          loop do
            group = [parse_field_name]
            group << parse_field_name while accept_special(',')
            expect_op('::')
            strict = at?(:bang)
            advance if strict
            ty = parse_type
            group.each do |n|
              names << n
              fields << [strict, ty]
            end
            break unless accept_special(',')
          end
        end
        expect_special('}')
        return ConDecl.new(t, t.text, fields, names)
      end

      items = []
      op = nil
      loop do
        if at?(:consym) || (at_special?('`') && @c.raw(1).kind == :conid)
          error_at(peek) if op

          if at?(:consym)
            op = advance.text
          else
            advance # `
            op = advance.text
            expect_special('`')
          end
          items << :op
        elsif at?(:bang)
          advance
          items << [true, parse_atype]
        elsif atype_start?
          items << [false, parse_atype]
        else
          break
        end
      end
      if op
        k = items.index(:op)
        left = field_btype(items[0, k], t)
        right = field_btype(items[(k + 1)..-1], t)
        return ConDecl.new(t, op, [left, right], nil, true)
      end
      first = items.shift
      error_at(t) if first.nil? || first[0] || !first[1].is_a?(TCon)
      ConDecl.new(t, first[1].name, items)
    end

    def parse_field_name
      n = peek
      error_at(n) unless n.kind == :varid
      advance.text
    end

    # The operand of an infix constructor: one (possibly strict) btype.
    def field_btype(items, t)
      error_at(t) if items.empty?
      strict = items[0][0]
      error_at(t) if items.drop(1).any? { |s, _| s }
      types = items.map { |_, ty| ty }
      [strict, types.length == 1 ? types[0] : TApp.new(types[0].tok, types[0], types.drop(1))]
    end

    def parse_deriving
      return [] unless at_kw?('deriving')

      advance
      if accept_special('(')
        classes = []
        unless at_special?(')')
          classes << parse_class_name
          classes << parse_class_name while accept_special(',')
        end
        expect_special(')')
        return classes
      end
      unsupported(peek, 'deriving strategies') if at?(:varid)
      [parse_class_name]
    end

    def parse_class_name
      t = peek
      error_at(t) unless t.kind == :conid || t.kind == :qconid
      advance.text
    end

    def parse_type_syn
      t = advance
      unsupported(peek, 'type families') if at?(:varid, 'family')
      name, tyvars = decl_head(parse_btype)
      expect_op('=')
      TypeSyn.new(t, name, tyvars, parse_type)
    end

    def parse_class
      t = advance
      ctx, head = context_and_head
      unless head.is_a?(TApp) && head.fn.is_a?(TCon) && head.args.length == 1 && head.args[0].is_a?(TVar)
        unsupported(head.tok, 'class declarations other than `class C a`')
      end
      decls = []
      if at_kw?('where')
        advance
        decls = block { parse_decl }
      end
      ClassDecl.new(t, ctx, head.fn.name, head.args[0].name, decls)
    end

    def parse_instance
      t = advance
      ctx, head = context_and_head
      unless head.is_a?(TApp) && head.fn.is_a?(TCon) && head.args.length == 1
        unsupported(head.tok, 'instance heads other than `C type`')
      end
      decls = []
      if at_kw?('where')
        advance
        decls = block { parse_decl }
      end
      InstDecl.new(t, ctx, head.fn.name, head.args[0], decls)
    end

    def context_and_head
      ty = parse_btype
      return [[], ty] unless at_op?('=>')

      advance
      [to_context(ty), parse_btype]
    end

    def parse_modid
      t = peek
      error_at(t) unless t.kind == :conid || t.kind == :qconid
      advance.text
    end

    def skip_export_list
      depth = 0
      loop do
        t = advance
        error_at(t) if t.kind == :eof
        depth += 1 if t.is?(:special, '(')
        depth -= 1 if t.is?(:special, ')')
        break if depth.zero?
      end
    end

    # import [qualified] M [qualified] [as N] [hiding] [(items)]
    def parse_import
      t = advance
      qualified = false
      if at?(:varid, 'qualified')
        advance
        qualified = true
      end
      name = parse_modid
      if at?(:varid, 'qualified')
        advance
        qualified = true
      end
      as = nil
      if at?(:varid, 'as')
        advance
        as = parse_modid
      end
      hiding = false
      if at?(:varid, 'hiding')
        advance
        hiding = true
      end
      items = at_special?('(') ? parse_import_items : nil
      ImportDecl.new(t, name, qualified, as, hiding, items)
    end

    def parse_import_items
      advance # (
      items = []
      until at_special?(')')
        t = peek
        if t.kind == :varid
          advance
          items << [t.text, nil]
        elsif t.is?(:special, '(')
          advance
          op = advance
          error_at(op) unless op.kind == :varsym || op.kind == :consym
          expect_special(')')
          items << [op.text, nil]
        elsif t.kind == :conid
          advance
          subs = nil
          if accept_special('(')
            if accept_op('..')
              subs = :all
            else
              subs = []
              until at_special?(')')
                s = advance
                error_at(s) unless s.kind == :varid || s.kind == :conid
                subs << s.text
                break unless accept_special(',')
              end
            end
            expect_special(')')
          end
          items << [t.text, subs]
        else
          error_at(t)
        end
        break unless accept_special(',')
      end
      expect_special(')')
      items
    end
  end
end
