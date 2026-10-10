# frozen_string_literal: true

module Rhci
  # The compiled Prelude as data: a session's names, types, class and
  # instance tables, and machine code, encoded at build time by
  # tools/snapshot.rb and decoded here into fresh objects for each session
  # (so top-level thunks, which evaluation overwrites, are never shared).
  #
  # Format: parts separated by "\f". Part 0 is a header, "rhci-snapshot\t2\t
  # <records per chunk>\t<records>\t<core records>\t<structure records>";
  # the other parts are chunks of records, each split only when one of its
  # records is first needed. Records are separated by "\n", fields by "\t".
  # Record 0 holds the roots. Kinds: "O\tClass\t@ivar\tvalue..." (an
  # object), "A\tvalue...", "B\tClass\tvalue..." (an Array subclass: thunks,
  # closures, constructor values), "H\tkey\tvalue...", and
  # "L\tlabel\tkey_core\tn\tm\tkey\tvalue...(n pairs)\tpending ref" (a
  # LazyTable: n loaded entries, and a "P" record of m pending ones, as
  # "key\tvalue ref" or, when keyed by Names, "Name#core\tkey ref\tvalue
  # ref"). Values:
  # i<integer> f<IEEE bits, hex> s<string> y<symbol> r<record index> n T F,
  # K<name> for shared singletons, and [v,v...] for an Array of integers,
  # nil and booleans that only one place refers to (written inline).
  #
  # The records come in three runs. The core (what typical inputs need,
  # found by running a corpus at build time) is decoded at startup; the rest
  # of the tables' structure is decoded entry by entry: on a lookup, by an
  # operation over a whole table, or in the background (load_step); last
  # comes compiled code, decoded per global on first use (LazyCell).
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
        'Rhci::Core::Var' => Core::Var, 'Rhci::Core::Lit' => Core::Lit, 'Rhci::Core::Str' => Core::Str,
        'Rhci::Core::App' => Core::App, 'Rhci::Core::Lam' => Core::Lam, 'Rhci::Core::Let' => Core::Let,
        'Rhci::Core::Case' => Core::Case, 'Rhci::Core::Alt' => Core::Alt, 'Rhci::Core::Con' => Core::Con,
        'Rhci::Core::Prim' => Core::Prim
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

    # The decoder of a snapshot: its root (session state, see
    # Session#prelude_state) is decoded on request, and with it the core.
    def self.decoder(source)
      register_classes if CLASSES.empty?
      Decoder.new(source)
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
      # tracing: LazyTables report the entries looked up (trace_log), which
      # tools/snapshot.rb uses to choose the core.
      attr_reader :tracing, :trace_log, :core_records

      # source: the snapshot text, or its parts as an Array (each a String
      # or an Array of pieces, joined when needed).
      def initialize(source)
        @parts = source.is_a?(String) ? source.split("\f") : source
        head = part(0).split("\t")
        raise 'snapshot: unknown version' unless head[0] == 'rhci-snapshot' && head[1] == '2'

        @chunk = head[2].to_i
        @core_records = head[4].to_i
        @split = Array.new(@parts.length)
        @objs = Array.new(head[3].to_i)
        @syms = {}
        @tables = []
        @tracing = false
        @loaded_count = 0
      end

      def root
        obj(0)
      end

      def start_trace
        @tracing = true
        @trace_log = []
        @decoded = []
      end

      # With tracing: the records decoded so far, in order.
      attr_reader :decoded

      def trace(label, key)
        @trace_log << [label, key]
      end

      # A LazyTable with pending entries, for load_step.
      def register(table)
        @tables << table
      end

      # Table entries decoded so far, after startup.
      attr_reader :loaded_count

      def entry_loaded
        @loaded_count += 1
      end

      # Table entries still pending (registered tables; tables inside
      # objects not yet decoded are not counted).
      def pending_count
        n = 0
        @tables.each { |t| n += t.pending_count }
        n
      end

      # Are table entries still pending?
      def pending?
        @tables.pop until @tables.empty? || @tables.last.pending?
        !@tables.empty?
      end

      # Decodes pending table entries until Shim.now passes deadline (nil:
      # until none are left). True once everything is loaded.
      def load_step(deadline)
        while pending?
          @tables.last.load_some(16)
          return false if deadline && Shim.now >= deadline
        end
        true
      end

      # The object of record i, decoded (with everything it refers to,
      # except cell values and pending table entries) on first request.
      def obj(i)
        o = @objs[i]
        return o if o

        @decoded << i if @tracing
        f = record(i).split("\t", -1)
        kind = f[0]
        if kind == 'O' && f[1] == 'Rhci::VM::Cell'
          return @objs[i] = lazy_cell(f)
        end
        return lazy_table(i, f) if kind == 'L'

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

      # References and integers, most fields by far, dispatch on the first
      # byte without allocating it.
      def value(v)
        b = v.getbyte(0)
        return obj(v[1, v.length].to_i) if b == 114 # r
        return v[1, v.length].to_i if b == 105 # i
        return inline_array(v) if b == 91 # [

        Snapshot.value(v, nil)
      end

      # "[i0,i5,n]": an Array of integers, nil and booleans, written inline.
      def inline_array(v)
        out = []
        return out if v.length == 2

        v[1, v.length - 2].split(',').each { |x| out << Snapshot.value(x, nil) }
        out
      end

      private

      def part(c)
        p = @parts[c]
        p.is_a?(Array) ? p.join : p
      end

      def record(i)
        c = i / @chunk + 1
        recs = @split[c] ||= part(c).split("\n")
        recs[i % @chunk]
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

      # The table exists (in @objs) before its entries are decoded, which
      # may refer back to it. Its pending entries stay in their own record
      # until the table first needs them (pending_entries).
      def lazy_table(i, f)
        t = LazyTable.new({}, self, f[2] == 'T', Snapshot.unescape(f[1]))
        @objs[i] = t
        n = f[3].to_i
        j = 5
        n.times do
          t[value(f[j])] = value(f[j + 1])
          j += 2
        end
        t.add_pending(f[j], f[4].to_i)
        t
      end

      public

      # The pending entries of a table: record ref ("P\tkey\tvalue
      # ref..." or "P\tName#core\tkey ref\tvalue ref..."), as a Hash.
      def pending_entries(ref, key_core)
        f = record(ref[1..-1].to_i).split("\t", -1)
        out = {}
        j = 1
        if key_core
          while j < f.length
            out[Snapshot.unescape(f[j])] = [f[j + 1], f[j + 2]]
            j += 3
          end
        else
          while j < f.length
            out[Snapshot.value(f[j], nil)] = f[j + 1]
            j += 2
          end
        end
        out
      end

      private

      def sym(s)
        @syms[s] ||= s.to_sym
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
          out << (d == 'n' ? "\n" : d == 't' ? "\t" : d == 'f' ? "\f" : d)
        else
          out << c
        end
        i += 1
      end
      out
    end
  end
end
