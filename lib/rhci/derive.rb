# frozen_string_literal: true

module Rhci
  # `deriving` clauses, as instance declarations in source text, following
  # the Haskell 2010 Report (ch. 11) as GHC implements it. The text is
  # parsed and then treated exactly like a user-written instance.
  #
  # Generated code calls only rhci_* names (Prelude-internal aliases), so a
  # user's own definitions (say, of `showString` or `.`) cannot capture it.
  module Derive
    SUPPORTED = %w[Show Eq Ord Enum Bounded].freeze

    # Instance declarations (AST) for a data declaration's deriving clause.
    # fixity: lookup of a constructor operator's [assoc, prec].
    def self.instances(d, source, fixity = nil)
      return [] if d.deriving.empty?

      text = d.deriving.map do |cls|
        unless SUPPORTED.include?(cls)
          raise UnsupportedError.new("deriving #{cls} is not supported", d.tok.line, d.tok.col, source)
        end

        case cls
        when 'Show' then derive_show(d, fixity)
        when 'Eq' then derive_eq(d, fixity)
        when 'Ord' then derive_ord(d, fixity)
        when 'Enum' then derive_enum(d, fixity)
        else derive_bounded(d, fixity)
        end
      end.join("\n")
      Frontend.parse_module(text, '<deriving>').decls
    end

    # ---- helpers ---------------------------------------------------------------

    def self.head(cls, d, context_classes = [cls])
      vars = used_tyvars(d)
      ctx = []
      vars.each { |v| context_classes.each { |c| ctx << "#{c} #{v}" } }
      ctx_s = ctx.empty? ? '' : "(#{ctx.join(', ')}) => "
      ty = d.tyvars.empty? ? d.name : "(#{([d.name] + d.tyvars).join(' ')})"
      "instance #{ctx_s}#{cls} #{ty} where\n"
    end

    # Type parameters that occur in some field (they get a constraint).
    def self.used_tyvars(d)
      used = {}
      d.cons.each { |c| c.fields.each { |_, t| collect_tyvars(t, used) } }
      d.tyvars.select { |v| used.key?(v) }
    end

    def self.collect_tyvars(t, acc)
      case t
      when AST::TVar then acc[t.name] = true
      when AST::TApp
        if t.fn.is_a?(AST::TVar)
          raise UnsupportedError.new('deriving for types with higher-kinded parameters is not supported',
                                     t.tok.line, t.tok.col)
        end
        collect_tyvars(t.fn, acc)
        t.args.each { |a| collect_tyvars(a, acc) }
      when AST::TFun
        collect_tyvars(t.from, acc)
        collect_tyvars(t.to, acc)
      when AST::TList then collect_tyvars(t.elem, acc)
      when AST::TTuple then t.elems.each { |e| collect_tyvars(e, acc) }
      end
    end

    def self.con_ref(c)
      operator?(c.name) ? "(#{c.name})" : c.name
    end

    def self.operator?(name)
      !AST.ident_start?(name[0])
    end

    def self.pat(c, prefix)
      return con_ref(c) if c.fields.empty?

      "(#{con_ref(c)} #{(1..c.fields.length).map { |i| "#{prefix}#{i}" }.join(' ')})"
    end

    # A Haskell string literal for s.
    def self.str(s)
      out = '"'.dup
      s.each_char do |ch|
        out << '\\' if ch == '\\' || ch == '"'
        out << ch
      end
      out << '"'
    end

    # f1 . f2 . ... as nested prefix applications of rhci_compose.
    def self.compose(parts)
      wrapped = parts.map { |p| "(#{p})" }
      wrapped.reverse.inject { |acc, p| "(rhci_compose #{p} #{acc})" }
    end

    def self.nullary_only?(d)
      !d.cons.empty? && d.cons.all? { |c| c.fields.empty? }
    end

    # ---- Show --------------------------------------------------------------------

    def self.derive_show(d, fixity)
      out = head('Show', d)
      d.cons.each do |c|
        n = c.fields.length
        body =
          if n.zero?
            "rhci_showString #{str(con_label(c))}"
          elsif c.field_names
            parts = ["rhci_showString #{str("#{con_label(c)} {")}"]
            c.field_names.each_with_index do |f, i|
              parts << "rhci_showString #{str(', ')}" if i > 0
              fname = operator?(f) ? "(#{f})" : f
              parts << "rhci_showString #{str("#{fname} = ")}"
              parts << "rhci_showsPrec 0 x#{i + 1}"
            end
            parts << 'rhci_showChar \'}\''
            "rhci_showParen (rhci_intGe d 11) #{compose(parts)}"
          elsif c.infix
            prec = fixity ? fixity.call(c.name)[1] : 9
            parts = ["rhci_showsPrec #{prec + 1} x1", "rhci_showString #{str(" #{c.name} ")}",
                     "rhci_showsPrec #{prec + 1} x2"]
            "rhci_showParen (rhci_intGt d #{prec}) #{compose(parts)}"
          else
            parts = ["rhci_showString #{str("#{con_label(c)} ")}"]
            (1..n).each do |i|
              parts << 'rhci_showSpace' if i > 1
              parts << "rhci_showsPrec 11 x#{i}"
            end
            "rhci_showParen (rhci_intGe d 11) #{compose(parts)}"
          end
        out << "  showsPrec d #{pat(c, 'x')} = #{body}\n"
      end
      out << "  showsPrec _ _ = rhci_showString \"\"\n" if d.cons.empty?
      out
    end

    # How a constructor's name appears in prefix position.
    def self.con_label(c)
      operator?(c.name) ? "(#{c.name})" : c.name
    end

    # ---- Eq ------------------------------------------------------------------------

    def self.derive_eq(d, _fixity)
      out = head('Eq', d)
      d.cons.each do |c|
        n = c.fields.length
        body = n.zero? ? 'True' : (1..n).map { |i| "(rhci_eq x#{i} y#{i})" }.reduce { |a, b| "(rhci_and #{a} #{b})" }
        out << "  (==) #{pat(c, 'x')} #{pat(c, 'y')} = #{body}\n"
      end
      out << (d.cons.empty? ? "  (==) _ _ = True\n" : "  (==) _ _ = False\n") if d.cons.length != 1
      out
    end

    # ---- Ord -------------------------------------------------------------------------

    def self.derive_ord(d, _fixity)
      out = head('Ord', d)
      d.cons.each do |c|
        n = c.fields.length
        body = n.zero? ? 'EQ' : (1..n).map { |i| "(rhci_compare x#{i} y#{i})" }.reduce { |a, b| "(rhci_thenCmp #{a} #{b})" }
        out << "  compare #{pat(c, 'x')} #{pat(c, 'y')} = #{body}\n"
      end
      if d.cons.length > 1
        out << "  compare x y = rhci_compareInt (rhci_conTag x) (rhci_conTag y)\n"
      elsif d.cons.empty?
        out << "  compare _ _ = EQ\n"
      end
      out
    end

    # ---- Enum and Bounded ----------------------------------------------------------------

    def self.derive_enum(d, _fixity)
      unless nullary_only?(d)
        raise UnsupportedError.new("cannot derive Enum for ‘#{d.name}’: it has a constructor with fields",
                                   d.tok.line, d.tok.col)
      end
      last = d.cons.length - 1
      name = d.name
      out = head('Enum', d)
      out << "  fromEnum x = rhci_conTag x\n"
      alts = []
      d.cons.each_with_index { |c, i| alts << "#{i} -> #{con_ref(c)}" }
      alts << "_ -> rhci_error (rhci_append #{str("toEnum{#{name}}: tag (")} " \
              "(rhci_append (rhci_showInt n) #{str(") is outside of enumeration's range (0,#{last})")}))"
      out << "  toEnum n = case n of { #{alts.join('; ')} }\n"
      out << "  succ x = case rhci_conTag x of { #{last} -> rhci_error " \
             "#{str("succ{#{name}}: tried to take `succ' of last tag in enumeration")}; t -> toEnum (rhci_intAdd t 1) }\n"
      out << "  pred x = case rhci_conTag x of { 0 -> rhci_error " \
             "#{str("pred{#{name}}: tried to take `pred' of first tag in enumeration")}; t -> toEnum (rhci_intSub t 1) }\n"
      out << "  enumFrom x = rhci_map toEnum (rhci_enumFromToInt (rhci_conTag x) #{last})\n"
      out << "  enumFromThen x y = rhci_map toEnum (rhci_enumFromThenToInt (rhci_conTag x) (rhci_conTag y) " \
             "(if rhci_intGe (rhci_conTag y) (rhci_conTag x) then #{last} else 0))\n"
      out
    end

    def self.derive_bounded(d, _fixity)
      out = head('Bounded', d)
      if nullary_only?(d)
        out << "  minBound = #{con_ref(d.cons.first)}\n  maxBound = #{con_ref(d.cons.last)}\n"
      elsif d.cons.length == 1
        c = d.cons[0]
        args = Array.new(c.fields.length, 'minBound').join(' ')
        out << "  minBound = #{con_ref(c)} #{args}\n"
        out << "  maxBound = #{con_ref(c)} #{Array.new(c.fields.length, 'maxBound').join(' ')}\n"
      else
        raise UnsupportedError.new("cannot derive Bounded for ‘#{d.name}’", d.tok.line, d.tok.col)
      end
      out
    end
  end
end
