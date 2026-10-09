# frozen_string_literal: true

module Rhci
  # The compiled Prelude as data: a session's names, types, class and
  # instance tables, and machine code, encoded at build time by
  # tools/snapshot.rb and decoded here into fresh objects for each session
  # (so top-level thunks, which evaluation overwrites, are never shared).
  #
  # Format: records separated by "\n", fields by "\t". Record 0 holds the
  # roots. Kinds: "O\tClass\t@ivar\tvalue..." (an object), "A\tvalue...",
  # "B\tClass\tvalue..." (an Array subclass: thunks, closures, constructor
  # values), "H\tkey\tvalue...". Values: i<integer> f<IEEE bits, hex> s<string>
  # y<symbol> r<record index> n T F, and K<name> for shared singletons.
  module Snapshot
    CLASSES = {}

    # Class names as the encoder writes them (CRuby's Class#name); mruby's
    # lean build has no Class#name, so the table is spelled out.
    def self.register_classes
      {
        'Rhci::NameEnv' => NameEnv, 'Rhci::Name' => Name, 'Rhci::TyInfo' => TyInfo,
        'Rhci::ClassInfo' => ClassInfo, 'Rhci::InstInfo' => InstInfo, 'Rhci::RBind' => RBind,
        'Rhci::Core::ConInfo' => Core::ConInfo,
        'Rhci::Types::TCon' => Types::TCon, 'Rhci::Types::TAp' => Types::TAp,
        'Rhci::Types::TGen' => Types::TGen, 'Rhci::Types::Scheme' => Types::Scheme,
        'Rhci::AST::TCon' => AST::TCon, 'Rhci::AST::TVar' => AST::TVar, 'Rhci::AST::TApp' => AST::TApp,
        'Rhci::AST::TFun' => AST::TFun, 'Rhci::AST::TList' => AST::TList, 'Rhci::AST::TTuple' => AST::TTuple,
        'Rhci::AST::TQual' => AST::TQual,
        'Rhci::VM::Cell' => VM::Cell, 'Rhci::VM::Fun' => VM::Fun, 'Rhci::VM::Thunk' => VM::Thunk,
        'Rhci::VM::ConValue' => VM::ConValue, 'Rhci::VM::ValueAtom' => VM::ValueAtom,
        'Rhci::VM::LamCode' => VM::LamCode, 'Rhci::VM::ThunkCode' => VM::ThunkCode,
        'Rhci::VM::XLocal' => VM::XLocal, 'Rhci::VM::XEnv' => VM::XEnv, 'Rhci::VM::XGlobal' => VM::XGlobal,
        'Rhci::VM::XValue' => VM::XValue, 'Rhci::VM::XApp' => VM::XApp, 'Rhci::VM::XLet' => VM::XLet,
        'Rhci::VM::XCase' => VM::XCase, 'Rhci::VM::XCon' => VM::XCon, 'Rhci::VM::XPrim' => VM::XPrim,
        'Rhci::VM::XStr' => VM::XStr
      }.each { |k, v| CLASSES[k] = v }
    end

    # Objects that must keep their identity across encoding: the type
    # checker and machine compare them with equal?.
    def self.singletons
      return @singletons if @singletons

      s = {
        'tArrow' => Types::ARROW, 'tList' => Types::LIST, 'tUnit' => Types::UNIT, 'tChar' => Types::CHAR,
        'tInt' => Types::INT, 'tInteger' => Types::INTEGER, 'tDouble' => Types::DOUBLE,
        'cUnit' => VM::Builtins::UNIT, 'cFalse' => VM::Builtins::FALSE, 'cTrue' => VM::Builtins::TRUE,
        'cNil' => VM::Builtins::NIL, 'cCons' => VM::Builtins::CONS, 'cLT' => VM::Builtins::LT,
        'cEQ' => VM::Builtins::EQ, 'cGT' => VM::Builtins::GT, 'cIORes' => VM::Builtins::IORES,
        'vUnit' => VM::Builtins::UNIT_V, 'vFalse' => VM::Builtins::FALSE_V, 'vTrue' => VM::Builtins::TRUE_V,
        'vNil' => VM::Builtins::NIL_V
      }
      (2..15).each do |n|
        s["tTuple#{n}"] = Types.tuple_con(n)
        s["cTuple#{n}"] = VM::Builtins.tuple(n)
      end
      @singletons = s
    end

    # Session state from encoded text: [NameEnv, tenv, globals]. Only what
    # renaming and type checking need is decoded now; each global's value
    # (its compiled code) is decoded when the machine first reads it.
    def self.decode(text)
      register_classes if CLASSES.empty?
      Decoder.new(text).root
    end

    # A global whose value is decoded on first use.
    class LazyCell < VM::Cell
      def initialize(name, decoder, ref)
        super(name, nil)
        @decoder = decoder
        @ref = ref
      end

      def value
        if @ref
          @value = @decoder.value(@ref)
          @ref = nil
        end
        @value
      end
    end

    class Decoder
      def initialize(text)
        @records = text.split("\n")
        @objs = Array.new(@records.length)
        @syms = {}
      end

      def root
        obj(0)
      end

      # The object of record i, decoded (with everything it refers to,
      # except cell values) on first request.
      def obj(i)
        o = @objs[i]
        return o if o

        f = @records[i].split("\t", -1)
        kind = f[0]
        if kind == 'O' && f[1] == 'Rhci::VM::Cell'
          return @objs[i] = lazy_cell(f)
        end

        o = case kind
            when 'O', 'B'
              klass = CLASSES[f[1]] || raise("snapshot: unknown class #{f[1]}")
              klass.allocate
            when 'A' then []
            else {}
            end
        @objs[i] = o
        case kind
        when 'O'
          j = 2
          while j < f.length
            o.instance_variable_set(sym(f[j]), value(f[j + 1])) # lint:ok (the snapshot decoder)
            j += 2
          end
        when 'A', 'B'
          j = kind == 'A' ? 1 : 2
          while j < f.length
            o << value(f[j])
            j += 1
          end
        else
          j = 1
          while j < f.length
            o[value(f[j])] = value(f[j + 1])
            j += 2
          end
        end
        o
      end

      def lazy_cell(f)
        name = nil
        ref = nil
        j = 2
        while j < f.length
          case f[j]
          when '@name' then name = value(f[j + 1])
          when '@value' then ref = f[j + 1]
          end
          j += 2
        end
        LazyCell.new(name, self, ref)
      end

      def sym(s)
        @syms[s] ||= s.to_sym
      end

      def value(v)
        case v[0]
        when 'r' then obj(v[1..-1].to_i)
        else Snapshot.value(v, nil)
        end
      end
    end

    def self.value(v, objs)
      case v[0]
      when 'r' then objs[v[1..-1].to_i]
      when 'i' then v[1..-1].to_i
      when 's' then unescape(v[1..-1])
      when 'y' then v[1..-1].to_sym
      when 'f' then Num.bits_to_double(v[1..-1].to_i(16))
      when 'K' then singletons[v[1..-1]] || raise("snapshot: unknown singleton #{v}")
      when 'T' then true
      when 'F' then false
      else nil
      end
    end

    def self.unescape(s)
      return s unless s.include?('\\')

      out = ''.dup
      i = 0
      while i < s.length
        c = s[i]
        if c == '\\'
          i += 1
          d = s[i]
          out << (d == 'n' ? "\n" : d == 't' ? "\t" : d)
        else
          out << c
        end
        i += 1
      end
      out
    end
  end
end
