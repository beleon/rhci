# frozen_string_literal: true

module Rhci
  # Surface syntax tree. Plain data only (no Procs), so later stages can
  # snapshot what is built from it. Every node keeps the token it starts
  # at (`tok`) for error positions. `sexp` renders a compact
  # S-expression used by the tests.
  module AST
    def self.sexp(x)
      case x
      when nil then '_'
      when Array then "(#{x.map { |e| sexp(e) }.join(' ')})"
      when String then x
      when Integer then x.to_s
      when Symbol then x.to_s
      else x.sexp
      end
    end

    def self.s(*parts)
      "(#{parts.map { |p| sexp(p) }.join(' ')})"
    end

    def self.op_name(name)
      c = name[0]
      ident_start?(c) || c == '(' || c == '[' ? name : "(#{name})"
    end

    def self.ident_start?(c)
      c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    end

    class Node
      attr_reader :tok

      def line
        @tok&.line
      end

      def col
        @tok&.col
      end
    end

    # ---- expressions -------------------------------------------------

    class Var < Node
      attr_reader :name, :qual

      def initialize(tok, name, qual = nil)
        @tok = tok
        @name = name
        @qual = qual
      end

      def operator?
        !AST.ident_start?(@name[0])
      end

      def sexp
        n = AST.op_name(@name)
        @qual ? "#{@qual}.#{n}" : n
      end
    end

    # A data constructor, including the specials (), [], and `:`.
    class Con < Var
    end

    # (,) (,,) ... as a function.
    class TupleCon < Node
      attr_reader :arity

      def initialize(tok, arity)
        @tok = tok
        @arity = arity
      end

      def sexp
        "(#{',' * (@arity - 1)})"
      end
    end

    # kind: :integer (Integer), :float ([mantissa, exp10] exact),
    #       :char (code point), :string (Array of code points)
    class Lit < Node
      attr_reader :kind, :value

      def initialize(tok, kind, value)
        @tok = tok
        @kind = kind
        @value = value
      end

      def sexp
        case @kind
        when :integer then @value.to_s
        when :float then "#{@value[0]}e#{@value[1]}"
        when :char then "'#{AST.cps_to_s([@value])}'"
        else "\"#{AST.cps_to_s(@value)}\""
        end
      end
    end

    def self.cps_to_s(cps)
      s = ''.dup
      cps.each do |c|
        if c == 10 then s << '\\n'
        elsif c < 32 || c == 127 then s << "\\#{c}"
        else s << c
        end
      end
      s
    end

    # f a1 ... an, kept flat.
    class App < Node
      attr_reader :fn, :args

      def initialize(tok, fn, args)
        @tok = tok
        @fn = fn
        @args = args
      end

      def sexp
        AST.s('app', @fn, *@args)
      end
    end

    # An unresolved infix expression: operands and operators alternate,
    # with :neg markers (prefix minus) before operands. Fixity resolution
    # turns it into BinOp/Neg.
    class OpSeq < Node
      attr_reader :items

      def initialize(tok, items)
        @tok = tok
        @items = items
      end

      def sexp
        AST.s('opseq', *@items.map { |i| i.is_a?(NegMark) ? 'neg' : i })
      end
    end

    # An operator inside an OpSeq/POpSeq; `ref` is the Var or Con named.
    # `backtick` records the `op` form.
    class OpItem < Node
      attr_reader :ref, :backtick

      def initialize(tok, ref, backtick = false)
        @tok = tok
        @ref = ref
        @backtick = backtick
      end

      def con?
        @ref.is_a?(Con)
      end

      def name
        @ref.name
      end

      def sexp
        @ref.sexp
      end
    end

    # Stands for the missing operand while a section is checked.
    class Hole < Node
      def initialize(tok)
        @tok = tok
      end

      def sexp
        '<hole>'
      end
    end

    class NegMark < Node
      def initialize(tok)
        @tok = tok
      end

      def sexp
        'neg'
      end
    end

    # op is a Var or Con.
    class BinOp < Node
      attr_reader :op, :left, :right

      def initialize(tok, op, left, right)
        @tok = tok
        @op = op
        @left = left
        @right = right
      end

      def sexp
        AST.s('op', @op, @left, @right)
      end
    end

    class Neg < Node
      attr_reader :expr

      def initialize(tok, expr)
        @tok = tok
        @expr = expr
      end

      def sexp
        AST.s('neg', @expr)
      end
    end

    class Paren < Node
      attr_reader :expr

      def initialize(tok, expr)
        @tok = tok
        @expr = expr
      end

      def sexp
        AST.s('paren', @expr)
      end
    end

    class LeftSection < Node
      attr_reader :expr, :op

      def initialize(tok, expr, op)
        @tok = tok
        @expr = expr
        @op = op
      end

      def sexp
        AST.s('lsect', @expr, @op)
      end
    end

    class RightSection < Node
      attr_reader :op, :expr

      def initialize(tok, op, expr)
        @tok = tok
        @op = op
        @expr = expr
      end

      def sexp
        AST.s('rsect', @op, @expr)
      end
    end

    class Lambda < Node
      attr_reader :pats, :body

      def initialize(tok, pats, body)
        @tok = tok
        @pats = pats
        @body = body
      end

      def sexp
        AST.s('lam', @pats, @body)
      end
    end

    class Let < Node
      attr_reader :decls, :body

      def initialize(tok, decls, body)
        @tok = tok
        @decls = decls
        @body = body
      end

      def sexp
        AST.s('let', @decls, @body)
      end
    end

    class If < Node
      attr_reader :cond, :then_e, :else_e

      def initialize(tok, cond, then_e, else_e)
        @tok = tok
        @cond = cond
        @then_e = then_e
        @else_e = else_e
      end

      def sexp
        AST.s('if', @cond, @then_e, @else_e)
      end
    end

    class Case < Node
      attr_reader :scrut, :alts

      def initialize(tok, scrut, alts)
        @tok = tok
        @scrut = scrut
        @alts = alts
      end

      def sexp
        AST.s('case', @scrut, *@alts)
      end
    end

    class Alt < Node
      attr_reader :pat, :rhs

      def initialize(tok, pat, rhs)
        @tok = tok
        @pat = pat
        @rhs = rhs
      end

      def sexp
        AST.s('alt', @pat, @rhs)
      end
    end

    class Do < Node
      attr_reader :stmts

      def initialize(tok, stmts)
        @tok = tok
        @stmts = stmts
      end

      def sexp
        AST.s('do', *@stmts)
      end
    end

    class Tuple < Node
      attr_reader :elems

      def initialize(tok, elems)
        @tok = tok
        @elems = elems
      end

      def sexp
        AST.s('tuple', *@elems)
      end
    end

    class List < Node
      attr_reader :elems

      def initialize(tok, elems)
        @tok = tok
        @elems = elems
      end

      def sexp
        AST.s('list', *@elems)
      end
    end

    # [from ..], [from, thn ..], [from .. to], [from, thn .. to]
    class ArithSeq < Node
      attr_reader :from, :thn, :to

      def initialize(tok, from, thn, to)
        @tok = tok
        @from = from
        @thn = thn
        @to = to
      end

      def sexp
        AST.s('range', @from, @thn, @to)
      end
    end

    class Comp < Node
      attr_reader :expr, :quals

      def initialize(tok, expr, quals)
        @tok = tok
        @expr = expr
        @quals = quals
      end

      def sexp
        AST.s('comp', @expr, *@quals)
      end
    end

    class Annot < Node
      attr_reader :expr, :type

      def initialize(tok, expr, type)
        @tok = tok
        @expr = expr
        @type = type
      end

      def sexp
        AST.s('::', @expr, @type)
      end
    end

    # C { f = e, ... }; fields is an Array of [name, expr].
    class RecCon < Node
      attr_reader :con, :fields

      def initialize(tok, con, fields)
        @tok = tok
        @con = con
        @fields = fields
      end

      def sexp
        AST.s('reccon', @con, *@fields)
      end
    end

    class RecUpd < Node
      attr_reader :expr, :fields

      def initialize(tok, expr, fields)
        @tok = tok
        @expr = expr
        @fields = fields
      end

      def sexp
        AST.s('recupd', @expr, *@fields)
      end
    end

    # `_` in an expression (a typed hole, or a pattern-to-be).
    class Wildcard < Node
      def initialize(tok)
        @tok = tok
      end

      def sexp
        '_'
      end
    end

    # Pattern-only forms that the parser first meets as expressions.
    class AsPat < Node
      attr_reader :name, :expr

      def initialize(tok, name, expr)
        @tok = tok
        @name = name
        @expr = expr
      end

      def sexp
        AST.s('as', @name, @expr)
      end
    end

    class LazyPat < Node
      attr_reader :expr

      def initialize(tok, expr)
        @tok = tok
        @expr = expr
      end

      def sexp
        AST.s('lazy', @expr)
      end
    end

    class BangPat < Node
      attr_reader :expr

      def initialize(tok, expr)
        @tok = tok
        @expr = expr
      end

      def sexp
        AST.s('bang', @expr)
      end
    end

    # ---- patterns ------------------------------------------------------

    class PVar < Node
      attr_reader :name

      def initialize(tok, name)
        @tok = tok
        @name = name
      end

      def sexp
        AST.op_name(@name)
      end
    end

    class PWild < Node
      def initialize(tok)
        @tok = tok
      end

      def sexp
        '_'
      end
    end

    # A literal pattern; `negative` for -1 / -1.5.
    class PLit < Node
      attr_reader :lit, :negative

      def initialize(tok, lit, negative = false)
        @tok = tok
        @lit = lit
        @negative = negative
      end

      def sexp
        @negative ? "-#{@lit.sexp}" : @lit.sexp
      end
    end

    class PCon < Node
      attr_reader :con, :args

      def initialize(tok, con, args)
        @tok = tok
        @con = con
        @args = args
      end

      def sexp
        @args.empty? ? @con.sexp : AST.s('pcon', @con, *@args)
      end
    end

    class PTuple < Node
      attr_reader :elems

      def initialize(tok, elems)
        @tok = tok
        @elems = elems
      end

      def sexp
        AST.s('ptuple', *@elems)
      end
    end

    class PList < Node
      attr_reader :elems

      def initialize(tok, elems)
        @tok = tok
        @elems = elems
      end

      def sexp
        AST.s('plist', *@elems)
      end
    end

    class PAs < Node
      attr_reader :name, :pat

      def initialize(tok, name, pat)
        @tok = tok
        @name = name
        @pat = pat
      end

      def sexp
        AST.s('as', @name, @pat)
      end
    end

    class PLazy < Node
      attr_reader :pat

      def initialize(tok, pat)
        @tok = tok
        @pat = pat
      end

      def sexp
        AST.s('lazy', @pat)
      end
    end

    class PBang < Node
      attr_reader :pat

      def initialize(tok, pat)
        @tok = tok
        @pat = pat
      end

      def sexp
        AST.s('bang', @pat)
      end
    end

    # fields: Array of [name, pat]
    class PRec < Node
      attr_reader :con, :fields

      def initialize(tok, con, fields)
        @tok = tok
        @con = con
        @fields = fields
      end

      def sexp
        AST.s('prec', @con, *@fields)
      end
    end

    # Unresolved infix pattern: operands, constructor operators, :neg marks.
    class POpSeq < Node
      attr_reader :items

      def initialize(tok, items)
        @tok = tok
        @items = items
      end

      def sexp
        AST.s('popseq', *@items)
      end
    end

    # ---- right-hand sides and statements -------------------------------

    # Either `body` (= e) or `guards`, an Array of [quals, expr]; plus an
    # optional `where` decl list.
    class Rhs < Node
      attr_reader :body, :guards, :where

      def initialize(tok, body, guards, where)
        @tok = tok
        @body = body
        @guards = guards
        @where = where
      end

      def sexp
        parts = @body ? ['rhs', @body] : ['grhs', *@guards.map { |q, e| ['|', q, e] }]
        parts << ['where', *@where] if @where
        AST.s(*parts)
      end
    end

    class BindStmt < Node
      attr_reader :pat, :expr

      def initialize(tok, pat, expr)
        @tok = tok
        @pat = pat
        @expr = expr
      end

      def sexp
        AST.s('<-', @pat, @expr)
      end
    end

    class LetStmt < Node
      attr_reader :decls

      def initialize(tok, decls)
        @tok = tok
        @decls = decls
      end

      def sexp
        AST.s('letstmt', *@decls)
      end
    end

    class ExprStmt < Node
      attr_reader :expr

      def initialize(tok, expr)
        @tok = tok
        @expr = expr
      end

      def sexp
        @expr.sexp
      end
    end

    # ---- declarations --------------------------------------------------

    # One equation `f p1 .. pn rhs` (n may be 0). Equations of one
    # function are grouped later, not by the parser.
    class FunEq < Node
      attr_reader :name, :pats, :rhs, :infix

      def initialize(tok, name, pats, rhs, infix = false)
        @tok = tok
        @name = name
        @pats = pats
        @rhs = rhs
        @infix = infix
      end

      def sexp
        AST.s('fun', AST.op_name(@name), @pats, @rhs)
      end
    end

    class PatBind < Node
      attr_reader :pat, :rhs

      def initialize(tok, pat, rhs)
        @tok = tok
        @pat = pat
        @rhs = rhs
      end

      def sexp
        AST.s('patbind', @pat, @rhs)
      end
    end

    class TypeSig < Node
      attr_reader :names, :type

      def initialize(tok, names, type)
        @tok = tok
        @names = names
        @type = type
      end

      def sexp
        AST.s('sig', @names.map { |n| AST.op_name(n) }, @type)
      end
    end

    # assoc: :left, :right, :none
    class FixityDecl < Node
      attr_reader :assoc, :prec, :ops

      def initialize(tok, assoc, prec, ops)
        @tok = tok
        @assoc = assoc
        @prec = prec
        @ops = ops
      end

      def sexp
        AST.s({ left: 'infixl', right: 'infixr', none: 'infix' }[@assoc], @prec, @ops.map { |o| AST.op_name(o) })
      end
    end

    # fields: Array of [strict, type]; field_names: nil, or Array of names
    # parallel to fields (record syntax).
    class ConDecl < Node
      attr_reader :name, :fields, :field_names, :infix

      def initialize(tok, name, fields, field_names = nil, infix = false)
        @tok = tok
        @name = name
        @fields = fields
        @field_names = field_names
        @infix = infix
      end

      def sexp
        fs = []
        i = 0
        while i < @fields.length
          strict, t = @fields[i]
          f = strict ? ['!', t] : t
          fs << (@field_names ? [@field_names[i], f] : f)
          i += 1
        end
        AST.s('con', AST.op_name(@name), *fs)
      end
    end

    class DataDecl < Node
      attr_reader :name, :tyvars, :cons, :deriving, :newtype

      def initialize(tok, name, tyvars, cons, deriving, newtype = false)
        @tok = tok
        @name = name
        @tyvars = tyvars
        @cons = cons
        @deriving = deriving
        @newtype = newtype
      end

      def sexp
        AST.s(@newtype ? 'newtype' : 'data', @name, @tyvars, *@cons, ['deriving', *@deriving])
      end
    end

    class TypeSyn < Node
      attr_reader :name, :tyvars, :type

      def initialize(tok, name, tyvars, type)
        @tok = tok
        @name = name
        @tyvars = tyvars
        @type = type
      end

      def sexp
        AST.s('type', @name, @tyvars, @type)
      end
    end

    # context: Array of [class_name, type]
    class ClassDecl < Node
      attr_reader :context, :name, :tyvar, :decls

      def initialize(tok, context, name, tyvar, decls)
        @tok = tok
        @context = context
        @name = name
        @tyvar = tyvar
        @decls = decls
      end

      def sexp
        AST.s('class', @context, @name, @tyvar, *@decls)
      end
    end

    class InstDecl < Node
      attr_reader :context, :name, :type, :decls

      def initialize(tok, context, name, type, decls)
        @tok = tok
        @context = context
        @name = name
        @type = type
        @decls = decls
      end

      def sexp
        AST.s('instance', @context, @name, @type, *@decls)
      end
    end

    # items: nil (everything) or Array of [name, subs] where subs is nil,
    # :all for T(..), or an Array of names.
    class ImportDecl < Node
      attr_reader :module_name, :qualified, :as, :hiding, :items

      def initialize(tok, module_name, qualified, as, hiding, items)
        @tok = tok
        @module_name = module_name
        @qualified = qualified
        @as = as
        @hiding = hiding
        @items = items
      end

      def sexp
        parts = ['import', @module_name]
        parts << 'qualified' if @qualified
        parts << ['as', @as] if @as
        parts << 'hiding' if @hiding
        parts << @items.map { |n, subs| subs.nil? ? n : [n, subs == :all ? '..' : subs] } if @items
        AST.s(*parts)
      end
    end

    class ModuleDecl < Node
      attr_reader :name, :exports, :imports, :decls

      def initialize(tok, name, exports, imports, decls)
        @tok = tok
        @name = name
        @exports = exports
        @imports = imports
        @decls = decls
      end

      def sexp
        AST.s('module', @name, *@imports, *@decls)
      end
    end

    # ---- types -----------------------------------------------------------

    class TCon < Node
      attr_reader :name

      def initialize(tok, name)
        @tok = tok
        @name = name
      end

      def sexp
        @name
      end
    end

    class TVar < Node
      attr_reader :name

      def initialize(tok, name)
        @tok = tok
        @name = name
      end

      def sexp
        @name
      end
    end

    class TApp < Node
      attr_reader :fn, :args

      def initialize(tok, fn, args)
        @tok = tok
        @fn = fn
        @args = args
      end

      def sexp
        AST.s(@fn, *@args)
      end
    end

    class TFun < Node
      attr_reader :from, :to

      def initialize(tok, from, to)
        @tok = tok
        @from = from
        @to = to
      end

      def sexp
        AST.s('->', @from, @to)
      end
    end

    class TList < Node
      attr_reader :elem

      def initialize(tok, elem)
        @tok = tok
        @elem = elem
      end

      def sexp
        "[#{@elem.sexp}]"
      end
    end

    class TTuple < Node
      attr_reader :elems

      def initialize(tok, elems)
        @tok = tok
        @elems = elems
      end

      def sexp
        AST.s('ttuple', *@elems)
      end
    end

    # forall vars. context => type (either part may be empty).
    class TQual < Node
      attr_reader :vars, :context, :type

      def initialize(tok, vars, context, type)
        @tok = tok
        @vars = vars
        @context = context
        @type = type
      end

      def sexp
        AST.s('qual', @vars, @context.map { |c, t| [c, t] }, @type)
      end
    end

    # ---- REPL inputs -----------------------------------------------------

    class ReplExpr < Node
      attr_reader :expr

      def initialize(tok, expr)
        @tok = tok
        @expr = expr
      end

      def sexp
        AST.s('repl-expr', @expr)
      end
    end

    class ReplBind < Node
      attr_reader :pat, :expr

      def initialize(tok, pat, expr)
        @tok = tok
        @pat = pat
        @expr = expr
      end

      def sexp
        AST.s('repl-bind', @pat, @expr)
      end
    end

    class ReplLet < Node
      attr_reader :decls

      def initialize(tok, decls)
        @tok = tok
        @decls = decls
      end

      def sexp
        AST.s('repl-let', *@decls)
      end
    end

    class ReplDecls < Node
      attr_reader :decls

      def initialize(tok, decls)
        @tok = tok
        @decls = decls
      end

      def sexp
        AST.s('repl-decls', *@decls)
      end
    end

    class ReplImport < Node
      attr_reader :import

      def initialize(tok, import)
        @tok = tok
        @import = import
      end

      def sexp
        AST.s('repl-import', @import)
      end
    end

    class ReplEmpty < Node
      def initialize(tok)
        @tok = tok
      end

      def sexp
        '(repl-empty)'
      end
    end
  end
end
