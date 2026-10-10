# frozen_string_literal: true

module Rhci
  # The lazy evaluator: an eval/apply machine in the spirit of the STG
  # machine, over code produced by Lower. One `loop` and an explicit frame
  # stack -- evaluation never recurses in Ruby, so the depth of a Haskell
  # computation is bounded by memory, not by the host's call stack.
  module VM
    # ---- runtime values ---------------------------------------------------
    # Unboxed: Integer (Int, Integer, Char), Float (Double).
    #
    # Constructor values, thunks and closures are Arrays underneath, laid
    # out flat, so each is one object rather than an object plus a fields or
    # environment array (on mruby every object costs ~100-170 bytes and GC
    # work). Hot code indexes them directly; the methods are for the rest.

    # A constructor application: [con, field0, field1, ...]. Nullary
    # constructors are shared (ConInfo#nullary).
    class ConValue < Array
      def self.build(con, fields)
        d = ConValue.new(fields.length + 1)
        d[0] = con
        i = 0
        while i < fields.length
          d[i + 1] = fields[i]
          i += 1
        end
        d
      end

      def con
        self[0]
      end

      def fields
        self[1..-1] || []
      end

      def inspect
        length == 1 ? self[0].name : "(#{self[0].name} #{fields.map(&:inspect).join(' ')})"
      end
    end

    # A suspended computation: [state, code-or-value, captured values...].
    # state :pending (slot 1 is the ThunkCode), :blackhole (under
    # evaluation), :value (slot 1 is the value; captures dropped), or
    # :raised (slot 1 is the exception). The thunk is its own environment:
    # capture j lives at index 2 + j.
    class Thunk < Array
      ENV_OFFSET = 2

      def self.build(code)
        t = Thunk.new(ENV_OFFSET + code.captures.length)
        t[0] = :pending
        t[1] = code
        t
      end

      def state
        self[0]
      end

      def value
        self[1]
      end

      # Overwrite with a final state, releasing the captured values (in
      # place: slice! would allocate an array of the removed elements).
      def settle(state, value)
        self[0] = state
        self[1] = value
        i = ENV_OFFSET
        n = length
        while i < n
          self[i] = nil
          i += 1
        end
        self
      end

      def inspect
        self[0] == :value ? self[1].inspect : "<thunk #{self[0]}>"
      end
    end

    # A string literal, unpacked one cons cell at a time:
    # [state, value, code points, index].
    class StringThunk < Thunk
      def self.build(cps, index)
        t = StringThunk.new(4)
        t[0] = :pending
        t[2] = cps
        t[3] = index
        t
      end
    end

    # A function closure: [LamCode, captured values...]; capture j lives at
    # index 1 + j.
    class Fun < Array
      ENV_OFFSET = 1

      def self.build(code)
        f = Fun.new(ENV_OFFSET + code.captures.length)
        f[0] = code
        f
      end

      def code
        self[0]
      end

      def inspect
        '<function>'
      end
    end

    # A function applied to fewer arguments than its arity.
    class PAP
      attr_reader :fun, :args

      def initialize(fun, args)
        @fun = fun
        @args = args
      end

      def inspect
        '<function>'
      end
    end

    # A global binding. Redefining a name at the prompt makes a new Cell;
    # code compiled earlier keeps pointing at the old one (GHCi shadowing).
    class Cell
      attr_accessor :name, :value

      def initialize(name, value = nil)
        @name = name
        @value = value
      end
    end

    # ---- code (produced by Lower; plain data) -------------------------------

    # Atoms (operands) are encoded for speed: an Integer i >= 0 is local
    # slot i, i < 0 is environment slot -i-1; a Cell is a global; a
    # ValueAtom is a constant (Integer constants must be wrapped).
    class ValueAtom
      attr_reader :value

      def initialize(value)
        @value = value
      end
    end

    # captures: atoms evaluated in the creating context to build the env.
    class LamCode
      attr_reader :arity, :captures, :nlocals, :body, :name

      def initialize(arity, captures, nlocals, body, name = nil)
        @arity = arity
        @captures = captures
        @nlocals = nlocals
        @body = body
        @name = name
      end
    end

    class ThunkCode
      attr_reader :captures, :nlocals, :body

      def initialize(captures, nlocals, body)
        @captures = captures
        @nlocals = nlocals
        @body = body
      end
    end

    # Code nodes carry an integer opcode (`op`) so the machine dispatches
    # with one comparison chain on integers instead of class tests.
    OP_LOCAL = 0
    OP_ENV = 1
    OP_GLOBAL = 2
    OP_VALUE = 3
    OP_APP = 4
    OP_LET = 5
    OP_CASE = 6
    OP_CON = 7
    OP_PRIM = 8
    OP_STR = 9

    class XLocal
      attr_reader :op, :index

      def initialize(index)
        @op = OP_LOCAL
        @index = index
      end
    end

    class XEnv
      attr_reader :op, :index

      def initialize(index)
        @op = OP_ENV
        @index = index
      end
    end

    class XGlobal
      attr_reader :op, :cell

      def initialize(cell)
        @op = OP_GLOBAL
        @cell = cell
      end
    end

    class XValue
      attr_reader :op, :value

      def initialize(value)
        @op = OP_VALUE
        @value = value
      end
    end

    # The expression node that evaluates an encoded atom.
    def self.atom_node(atom)
      if atom.is_a?(Integer)
        atom >= 0 ? XLocal.new(atom) : XEnv.new(-atom - 1)
      elsif atom.is_a?(Cell)
        XGlobal.new(atom)
      else
        XValue.new(atom.value)
      end
    end

    class XApp
      attr_reader :op, :fn, :args

      def initialize(fn_atom, args)
        @op = OP_APP
        @fn = VM.atom_node(fn_atom) # evaluated once the args are pushed
        @args = args
      end
    end

    # binds: [slot, kind, payload]; kind :thunk (ThunkCode), :fun (LamCode),
    # :con ([ConInfo, atoms]), :str (code points), :value (a constant).
    class XLet
      attr_reader :op, :binds, :body

      def initialize(binds, body)
        @op = OP_LET
        @binds = binds
        @body = body
      end
    end

    # con_alts: Array indexed by tag of [slots, body] (nil = no alt);
    # lit_alts: Hash value => body; default: body or nil.
    class XCase
      attr_reader :op, :scrut, :binder, :con_alts, :lit_alts, :default

      def initialize(scrut, binder, con_alts, lit_alts, default)
        @op = OP_CASE
        @scrut = scrut
        @binder = binder
        @con_alts = con_alts
        @lit_alts = lit_alts
        @default = default
      end
    end

    class XCon
      attr_reader :op, :con, :args

      def initialize(con, args)
        @op = OP_CON
        @con = con
        @args = args
      end
    end

    # meth: the Machine method implementing the primitive (resolved when
    # the code is built, so an unknown primitive fails early); strict: the
    # operands must already be evaluated (all but `raise`).
    class XPrim
      attr_reader :op, :prim, :args, :meth, :strict

      def initialize(prim, args)
        @op = OP_PRIM
        @prim = prim
        @args = args
        @meth = Machine::PRIM_METHODS[prim]
        raise "machine: unknown primitive #{prim}" unless @meth

        @strict = prim != :raise
      end
    end

    class XStr
      attr_reader :op, :cps

      def initialize(cps)
        @op = OP_STR
        @cps = cps
      end
    end

    # Stack frames are not objects: an update frame is the Thunk itself,
    # pending arguments are an Array, and a case continuation is three
    # entries -- env, locals, then the XCase on top.

    # The machine's frame stack, in fixed-size segments. One huge Array that
    # is written on every push/pop is re-scanned whole by mruby's incremental
    # GC each time the write barrier fires, which made deep evaluation
    # quadratic; with segments only the small top one is ever written.
    class FrameStack
      SEGMENT = 1024

      attr_reader :length

      def initialize
        @top = []
        @full = []
        @length = 0
      end

      def push(frame)
        if @top.length == SEGMENT
          @full.push(@top)
          @top = []
        end
        @top.push(frame)
        @length += 1
        self
      end

      def pop
        return nil if @length.zero?

        @top = @full.pop if @top.empty?
        @length -= 1
        @top.pop
      end
    end

    # ---- built-in constructors ------------------------------------------------

    module Builtins
      UNIT, = Core.data_type('()', [['()', 0]])
      FALSE, TRUE = Core.data_type('Bool', [['False', 0], ['True', 0]])
      NIL, CONS = Core.data_type('[]', [['[]', 0], [':', 2]])
      LT, EQ, GT = Core.data_type('Ordering', [['LT', 0], ['EQ', 0], ['GT', 0]])
      IORES, = Core.data_type('IORes', [['IORes', 1]])

      UNIT_V = (UNIT.nullary = ConValue.build(UNIT, []))
      FALSE_V = (FALSE.nullary = ConValue.build(FALSE, []))
      TRUE_V = (TRUE.nullary = ConValue.build(TRUE, []))
      NIL_V = (NIL.nullary = ConValue.build(NIL, []))

      @tuples = {}

      def self.tuple(n)
        @tuples[n] ||= Core.data_type("(#{',' * (n - 1)})", [["(#{',' * (n - 1)})", n]])[0]
      end

      def self.bool(b)
        b ? TRUE_V : FALSE_V
      end
    end

    # ---- exceptions -----------------------------------------------------------

    # A Haskell exception. `message` is a Ruby String, or a Haskell String
    # value (rendered by Machine#exception_message).
    class HsException < StandardError
      attr_reader :payload

      def initialize(payload)
        @payload = payload
        super(payload.is_a?(String) ? payload : 'Haskell exception')
      end
    end

    # Evaluation stopped by a host limit; the session stays usable.
    class LimitExceeded < StandardError
    end

    # ---- the machine ----------------------------------------------------------

    class Machine
      include Builtins

      CHECK_EVERY = 4096
      NAN = 0.0 / 0.0

      attr_reader :steps
      attr_writer :args

      # out: an IO-like object (write/flush). limits: Hash with optional
      # :steps, :stack (frames), :deadline (monotonic seconds).
      # input: stdin (gets/getc); err: stderr; args: what getArgs returns.
      def initialize(out = nil, limits = nil, input: nil, err: nil, args: [])
        if limits && limits[:deadline] && Shim.now.nil?
          raise UnsupportedError, 'time limits need a clock, which this runtime lacks'
        end

        @input = input
        @err = err
        @args = args
        @peeked = nil
        @stdin_state = :open
        @buffering = {}
        @out = out
        @buf = ''.dup
        @stack = FrameStack.new
        @steps = 0
        @limits = limits || {}
        @interrupted = false
        @next_check = CHECK_EVERY
      end

      def interrupt!
        @interrupted = true
      end

      # Start a new top-level evaluation: the step limit counts from here.
      def begin_evaluation
        @step_base = @steps
        @interrupted = false
        Shim.interrupt_pending? # a Ctrl-C from before this input is stale
      end

      # A character read ahead by isEOF that the REPL's own line reader
      # must see first (GHCi's prompt reads the same stdin), or nil.
      def take_peeked
        c = @peeked
        @peeked = nil
        c.nil? || c == :eof ? nil : ''.dup << c
      end

      # What `interact`/getContents does before handing out the String.
      def semi_close_stdin(op = 'hGetContents')
        stdin_usable(op)
        @stdin_state = :semi
      end

      def flush_output
        return if @buf.empty?

        Shim.write(@out, @buf) if @out
        @buf = ''.dup
        Shim.flush(@out) if @out
      end

      # Evaluate a value to weak head normal form.
      def whnf(v)
        return v unless v.is_a?(Thunk)
        return v[1] if v[0] == :value

        run(XValue.new(v), nil, nil)
      end

      # Evaluate compiled code (a ThunkCode with no captures) to WHNF.
      def eval_code(code)
        run(code.body, Array.new(code.nlocals), [])
      end

      # Apply a function value to argument values and evaluate to WHNF.
      def apply(fn, args)
        @stack.push(args.dup)
        base = @stack.length - 1
        run(XValue.new(fn), nil, nil, base)
      end

      # Fully evaluate a Haskell list (of WHNF-able elements) into a Ruby
      # Array of WHNF values.
      def list_to_a(v)
        out = []
        cell = whnf(v)
        while cell.con.equal?(CONS)
          out << whnf(cell[1])
          cell = whnf(cell[2])
        end
        out
      end

      # A Haskell String to a Ruby String.
      def string(v)
        s = ''.dup
        list_to_a(v).each { |c| s << c }
        s
      end

      # A Ruby String as a Haskell String value.
      def haskell_string(s)
        str_value(s)
      end

      def exception_message(e)
        p = e.payload
        p.is_a?(String) ? p : string(p)
      end

      private

      # The mruby builds have this loop in C (mrbgems/rhci-native/src/
      # machine.c, a port of run_ruby); CRuby runs the Ruby one.
      NATIVE = method_defined?(:run_native)

      def run(expr, locals, env, base = @stack.length)
        return run_native(expr, locals, env, base) if NATIVE && Machine.native

        run_ruby(expr, locals, env, base)
      end

      # Tests switch the C loop off to compare it with the Ruby one.
      def self.native
        @native.nil? ? true : @native
      end

      def self.native=(on)
        @native = on
      end

      # The eval/apply loop. Returns the WHNF value once the stack is back
      # at `base` (entry depth), which makes the machine re-entrant for
      # host-side helpers such as `string`.
      def run_ruby(expr, locals, env, base)
        stack = @stack
        value = nil
        evaluating = true
        begin
          while true # rubocop:disable Style/InfiniteLoop -- `loop do` costs a block call per step
            if evaluating
              @steps += 1
              check_limits if @steps >= @next_check
              op = expr.op
              if op <= OP_VALUE
                v = if op == OP_LOCAL then locals[expr.index]
                    elsif op == OP_ENV then env[expr.index]
                    elsif op == OP_GLOBAL then expr.cell.value
                    else expr.value
                    end
                if v.is_a?(Thunk)
                  state = v[0]
                  if state == :value
                    value = v[1]
                    evaluating = false
                  elsif state == :pending
                    if v.is_a?(StringThunk)
                      value = unpack(v)
                      evaluating = false
                    else
                      v[0] = :blackhole
                      stack.push(v)
                      code = v[1]
                      env = v # a thunk is its own environment
                      n = code.nlocals
                      locals = n.zero? ? nil : Array.new(n)
                      expr = code.body
                    end
                  elsif state == :blackhole
                    raise HsException, '<<loop>>'
                  else
                    raise v[1]
                  end
                else
                  value = v
                  evaluating = false
                end
              elsif op == OP_APP
                f = expr.fn
                fo = f.op
                fv = if fo == OP_GLOBAL then f.cell.value
                     elsif fo == OP_LOCAL then locals[f.index]
                     elsif fo == OP_ENV then env[f.index]
                     else f.value
                     end
                fv = fv[1] if fv.is_a?(Thunk) && fv[0] == :value
                atoms = expr.args
                n = atoms.length
                if fv.is_a?(Fun) && fv[0].arity == n
                  # Known saturated call: the arguments go straight into the
                  # callee's locals; no argument frame, no extra step.
                  code = fv[0]
                  nl = Array.new(code.nlocals)
                  i = 0
                  while i < n
                    a = atoms[i]
                    nl[i] = a.is_a?(Integer) ? (a >= 0 ? locals[a] : env[-a - 1]) : a.value
                    i += 1
                  end
                  locals = nl
                  env = fv # a closure is its own environment
                  expr = code.body
                else
                  stack.push(gather(atoms, locals, env))
                  expr = f
                end
              elsif op == OP_CASE
                sc = expr.scrut
                so = sc.op
                sv = nil
                if so <= OP_VALUE
                  sv = if so == OP_LOCAL then locals[sc.index]
                       elsif so == OP_ENV then env[sc.index]
                       elsif so == OP_GLOBAL then sc.cell.value
                       else sc.value
                       end
                  if sv.is_a?(Thunk)
                    sv = sv[0] == :value ? sv[1] : nil
                  end
                elsif so == OP_PRIM && sc.strict
                  # A primitive scrutinee needs no frame: its operands are
                  # already values.
                  pa = sc.args
                  a = pa[0]
                  x = a.is_a?(Integer) ? (a >= 0 ? locals[a] : env[-a - 1]) : a.value
                  if pa.length == 2
                    a = pa[1]
                    y = a.is_a?(Integer) ? (a >= 0 ? locals[a] : env[-a - 1]) : a.value
                    bad_operand(sc) if x.is_a?(Thunk) || y.is_a?(Thunk)
                    sv = __send__(sc.meth, x, y)
                  else
                    bad_operand(sc) if x.is_a?(Thunk)
                    sv = __send__(sc.meth, x)
                  end
                end
                if sv.nil?
                  stack.push(env)
                  stack.push(locals)
                  stack.push(expr)
                  expr = sc
                else
                  # Scrutinee already in WHNF: choose the alternative now.
                  locals[expr.binder] = sv if expr.binder
                  expr = select_alt(expr, sv, locals)
                end
              elsif op == OP_LET
                allocate(expr.binds, locals, env)
                expr = expr.body
              elsif op == OP_CON
                con = expr.con
                value = con.arity.zero? ? nullary(con) : build_data(con, expr.args, locals, env)
                evaluating = false
              elsif op == OP_PRIM
                pa = expr.args
                a = pa[0]
                x = a.is_a?(Integer) ? (a >= 0 ? locals[a] : env[-a - 1]) : a.value
                if pa.length == 2
                  a = pa[1]
                  y = a.is_a?(Integer) ? (a >= 0 ? locals[a] : env[-a - 1]) : a.value
                  bad_operand(expr) if expr.strict && (x.is_a?(Thunk) || y.is_a?(Thunk))
                  value = __send__(expr.meth, x, y)
                else
                  bad_operand(expr) if expr.strict && x.is_a?(Thunk)
                  value = __send__(expr.meth, x)
                end
                evaluating = false
              elsif op == OP_STR
                value = unpack(StringThunk.build(expr.cps, 0))
                evaluating = false
              else
                raise "machine: unknown code #{expr.class}"
              end
            else
              return value if stack.length == base

              frame = stack.pop
              if frame.is_a?(XCase)
                locals = stack.pop
                env = stack.pop
                locals[frame.binder] = value if frame.binder
                expr = select_alt(frame, value, locals)
                evaluating = true
              elsif frame.is_a?(Thunk)
                frame.settle(:value, value)
              else # pending arguments
                fun = value
                args = frame
                if fun.is_a?(PAP)
                  args = fun.args + args
                  fun = fun.fun
                end
                raise "machine: applying a non-function #{fun.inspect}" unless fun.is_a?(Fun)

                code = fun[0]
                n = code.arity
                if args.length < n
                  value = PAP.new(fun, args)
                else
                  if args.length > n
                    stack.push(args[n..-1])
                    args = args[0, n]
                  end
                  # The (fresh) argument array becomes the callee's locals.
                  nl = code.nlocals
                  args[nl - 1] = nil if nl > n
                  locals = args
                  env = fun
                  expr = code.body
                  evaluating = true
                end
              end
            end
          end
        rescue HsException => e
          unwind(base, e)
          raise e
        rescue LimitExceeded => e
          unwind(base, nil)
          raise e
        end
      end

      # Atom values, without a block: on mruby every block allocates a Proc,
      # which is the dominant cost in this loop.
      def gather(atoms, locals, env)
        n = atoms.length
        out = Array.new(n)
        i = 0
        while i < n
          a = atoms[i]
          out[i] = if a.is_a?(Integer)
                     a >= 0 ? locals[a] : env[-a - 1]
                   else
                     a.value # a Cell or a ValueAtom
                   end
          i += 1
        end
        out
      end

      def nullary(con)
        con.nullary ||= ConValue.build(con, [])
      end

      def build_data(con, atoms, locals, env)
        n = atoms.length
        d = ConValue.new(n + 1)
        d[0] = con
        i = 0
        while i < n
          a = atoms[i]
          d[i + 1] = a.is_a?(Integer) ? (a >= 0 ? locals[a] : env[-a - 1]) : a.value
          i += 1
        end
        d
      end

      def select_alt(xc, value, locals)
        if xc.con_alts
          alt = xc.con_alts[value[0].tag]
          if alt
            slots = alt[0]
            i = 0
            while i < slots.length
              s = slots[i]
              locals[s] = value[i + 1] if s
              i += 1
            end
            return alt[1]
          end
        elsif xc.lit_alts
          body = xc.lit_alts[value]
          return body if body
        end
        return xc.default if xc.default

        raise HsException, 'machine: no matching case alternative'
      end

      # Two phases, so that a recursive group can refer to itself
      # (`let ones = 1 : ones`).
      def allocate(binds, locals, env)
        n = binds.length
        i = 0
        while i < n
          slot, kind, payload = binds[i]
          locals[slot] =
            case kind
            when :thunk then Thunk.build(payload)
            when :fun then Fun.build(payload)
            when :con
              con = payload[0]
              if con.arity.zero?
                nullary(con)
              else
                d = ConValue.new(con.arity + 1)
                d[0] = con
                d
              end
            when :str then StringThunk.build(payload, 0)
            else payload
            end
          i += 1
        end
        i = 0
        while i < n
          slot, kind, payload = binds[i]
          case kind
          when :thunk then fill(locals[slot], Thunk::ENV_OFFSET, payload.captures, locals, env)
          when :fun then fill(locals[slot], Fun::ENV_OFFSET, payload.captures, locals, env)
          when :con then fill(locals[slot], 1, payload[1], locals, env) unless payload[1].empty?
          end
          i += 1
        end
      end

      # Write atom values into obj[offset...].
      def fill(obj, offset, atoms, locals, env)
        i = 0
        n = atoms.length
        while i < n
          a = atoms[i]
          obj[offset + i] = a.is_a?(Integer) ? (a >= 0 ? locals[a] : env[-a - 1]) : a.value
          i += 1
        end
      end

      def unpack(st)
        return st[1] if st[0] == :value

        cps = st[2]
        i = st[3]
        v = if i >= cps.length
              NIL_V
            else
              d = ConValue.new(3)
              d[0] = CONS
              d[1] = cps[i]
              d[2] = StringThunk.build(cps, i + 1)
              d
            end
        st[0] = :value
        st[1] = v
        st[2] = nil
        v
      end

      # Pop frames above `base`. A Haskell exception overwrites each thunk
      # under evaluation to re-raise it (as GHC does); a host limit resets
      # them so that a later attempt recomputes.
      def unwind(base, exc)
        while @stack.length > base
          f = @stack.pop
          next unless f.is_a?(Thunk)

          if exc
            f.settle(:raised, exc)
          else
            f[0] = :pending
          end
        end
      end

      def check_limits
        @next_check = @steps + CHECK_EVERY
        if @interrupted || Shim.interrupt_pending?
          @interrupted = false
          raise LimitExceeded, 'Interrupted.'
        end
        max = @limits[:steps]
        raise LimitExceeded, "step limit (#{max}) exceeded" if max && @steps - (@step_base || 0) > max

        max = @limits[:stack]
        raise LimitExceeded, "stack limit (#{max} frames) exceeded" if max && @stack.length > max

        deadline = @limits[:deadline]
        raise LimitExceeded, 'time limit exceeded' if deadline && Shim.now > deadline
      end

      # A primitive's String result, in WHNF like every primitive result.
      def str_value(s)
        unpack(StringThunk.build(s.codepoints, 0))
      end

      # ---- input ---------------------------------------------------------------

      # The next character's code point from stdin, or nil at end of input.
      def next_char
        if @peeked
          c = @peeked
          @peeked = nil
          return c == :eof ? nil : c
        end
        flush_output
        ch = @input ? Shim.read_char(@input) : nil
        raise LimitExceeded, 'Interrupted.' if ch == :interrupt

        ch&.ord
      end

      def eof?
        @peeked ||= (next_char || :eof)
        @peeked == :eof
      end

      # stdin after getContents is semi-closed, and closed once the lazy
      # String has reached its end; GHC's handle operations then fail.
      def stdin_usable(op)
        return if @stdin_state == :open

        how = @stdin_state == :semi ? 'semi-closed' : 'closed'
        raise HsException, "<stdin>: #{op}: illegal operation (handle is #{how})"
      end

      def put_char(c)
        if c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)
          raise HsException, "<stdout>: hPutChar: invalid argument (cannot encode character '\\#{c}')"
        end

        @buf << c
        flush_output if c == 10 || @buf.length >= 4096
      end

      # ---- primitives: arguments are WHNF values -------------------------------

      # ---- primitives: one method each, operands are WHNF values ----------------

      # Primitive names (from Core) to method names; arity from the method.
      PRIM_METHODS = {}

      PRIM_METHODS[:integerAdd] = :p_integerAdd
      PRIM_METHODS[:integerSub] = :p_integerSub
      PRIM_METHODS[:integerMul] = :p_integerMul
      PRIM_METHODS[:integerNegate] = :p_integerNegate
      PRIM_METHODS[:integerQuot] = :p_integerQuot
      PRIM_METHODS[:integerRem] = :p_integerRem
      PRIM_METHODS[:integerDiv] = :p_integerDiv
      PRIM_METHODS[:integerMod] = :p_integerMod
      PRIM_METHODS[:integerEq] = :p_integerEq
      PRIM_METHODS[:integerLt] = :p_integerLt
      PRIM_METHODS[:integerLe] = :p_integerLe
      PRIM_METHODS[:integerGt] = :p_integerGt
      PRIM_METHODS[:integerGe] = :p_integerGe
      PRIM_METHODS[:integerToInt] = :p_integerToInt
      PRIM_METHODS[:integerToDouble] = :p_integerToDouble
      PRIM_METHODS[:integerShow] = :p_integerShow
      PRIM_METHODS[:intAdd] = :p_intAdd
      PRIM_METHODS[:intSub] = :p_intSub
      PRIM_METHODS[:intMul] = :p_intMul
      PRIM_METHODS[:intNegate] = :p_intNegate
      PRIM_METHODS[:intQuot] = :p_intQuot
      PRIM_METHODS[:intRem] = :p_intRem
      PRIM_METHODS[:intDiv] = :p_intDiv
      PRIM_METHODS[:intMod] = :p_intMod
      PRIM_METHODS[:doubleAdd] = :p_doubleAdd
      PRIM_METHODS[:doubleSub] = :p_doubleSub
      PRIM_METHODS[:doubleMul] = :p_doubleMul
      PRIM_METHODS[:doubleDiv] = :p_doubleDiv
      PRIM_METHODS[:doubleNegate] = :p_doubleNegate
      PRIM_METHODS[:doubleEq] = :p_doubleEq
      PRIM_METHODS[:doubleLt] = :p_doubleLt
      PRIM_METHODS[:doubleLe] = :p_doubleLe
      PRIM_METHODS[:doubleGt] = :p_doubleGt
      PRIM_METHODS[:doubleGe] = :p_doubleGe
      PRIM_METHODS[:doubleSqrt] = :p_doubleSqrt
      PRIM_METHODS[:doubleExp] = :p_doubleExp
      PRIM_METHODS[:doubleLog] = :p_doubleLog
      PRIM_METHODS[:doublePow] = :p_doublePow
      PRIM_METHODS[:doubleIsNaN] = :p_doubleIsNaN
      PRIM_METHODS[:doubleIsInfinite] = :p_doubleIsInfinite
      PRIM_METHODS[:doubleIsNegativeZero] = :p_doubleIsNegativeZero
      PRIM_METHODS[:doubleDecode] = :p_doubleDecode
      PRIM_METHODS[:doubleTruncate] = :p_doubleTruncate
      PRIM_METHODS[:doubleFromRational] = :p_doubleFromRational
      PRIM_METHODS[:doubleShow] = :p_doubleShow
      PRIM_METHODS[:chr] = :p_chr
      PRIM_METHODS[:coerce] = :p_coerce
      PRIM_METHODS[:putChar] = :p_putChar
      PRIM_METHODS[:hPutChar] = :p_hPutChar
      PRIM_METHODS[:hFlush] = :p_hFlush
      PRIM_METHODS[:getChar] = :p_getChar
      PRIM_METHODS[:getLine] = :p_getLine
      PRIM_METHODS[:isEOF] = :p_isEOF
      PRIM_METHODS[:readChar] = :p_readChar
      PRIM_METHODS[:getArgs] = :p_getArgs
      PRIM_METHODS[:getContents] = :p_getContents
      PRIM_METHODS[:setBuffering] = :p_setBuffering
      PRIM_METHODS[:getBuffering] = :p_getBuffering
      PRIM_METHODS[:charCategory] = :p_charCategory
      PRIM_METHODS[:charTitle] = :p_charTitle
      PRIM_METHODS[:isUpperCase] = :p_isUpperCase
      PRIM_METHODS[:isLowerCase] = :p_isLowerCase
      PRIM_METHODS[:charUpper] = :p_charUpper
      PRIM_METHODS[:charLower] = :p_charLower
      PRIM_METHODS[:intToInteger] = :p_intToInteger
      PRIM_METHODS[:ord] = :p_ord
      PRIM_METHODS[:doubleAbs] = :p_doubleAbs
      PRIM_METHODS[:doubleSin] = :p_doubleSin
      PRIM_METHODS[:doubleCos] = :p_doubleCos
      PRIM_METHODS[:doubleTan] = :p_doubleTan
      PRIM_METHODS[:doubleAsin] = :p_doubleAsin
      PRIM_METHODS[:doubleAcos] = :p_doubleAcos
      PRIM_METHODS[:doubleAtan] = :p_doubleAtan
      PRIM_METHODS[:doubleSinh] = :p_doubleSinh
      PRIM_METHODS[:doubleCosh] = :p_doubleCosh
      PRIM_METHODS[:doubleTanh] = :p_doubleTanh
      PRIM_METHODS[:doubleAsinh] = :p_doubleAsinh
      PRIM_METHODS[:doubleAcosh] = :p_doubleAcosh
      PRIM_METHODS[:doubleAtanh] = :p_doubleAtanh
      PRIM_METHODS[:doubleFloor] = :p_doubleFloor
      PRIM_METHODS[:doubleCeiling] = :p_doubleCeiling
      PRIM_METHODS[:doubleRound] = :p_doubleRound
      PRIM_METHODS[:doubleEncode] = :p_doubleEncode
      PRIM_METHODS[:conTag] = :p_conTag
      PRIM_METHODS[:isSpace] = :p_isSpace
      PRIM_METHODS[:charEq] = :p_charEq
      PRIM_METHODS[:raise] = :p_raise

      def p_integerAdd(a0, a1)
        a0 + a1
      end

      def p_integerSub(a0, a1)
        a0 - a1
      end

      def p_integerMul(a0, a1)
        a0 * a1
      end

      def p_integerNegate(a0)
        -a0
      end

      def p_integerQuot(a0, a1)
        Num.quot(a0, nonzero(a1))
      end

      def p_integerRem(a0, a1)
        Num.rem(a0, nonzero(a1))
      end

      def p_integerDiv(a0, a1)
        a0 / nonzero(a1)
      end

      def p_integerMod(a0, a1)
        a0 % nonzero(a1)
      end

      def p_integerEq(a0, a1)
        Builtins.bool(a0 == a1)
      end

      def p_integerLt(a0, a1)
        Builtins.bool(a0 < a1)
      end

      def p_integerLe(a0, a1)
        Builtins.bool(a0 <= a1)
      end

      def p_integerGt(a0, a1)
        Builtins.bool(a0 > a1)
      end

      def p_integerGe(a0, a1)
        Builtins.bool(a0 >= a1)
      end

      def p_integerToInt(a0)
        Num.wrap_int(a0)
      end

      def p_integerToDouble(a0)
        Num.integer_to_double(a0)
      end

      def p_integerShow(a0)
        str_value(a0.to_s)
      end

      def p_intAdd(a0, a1)
        Num.wrap_int(a0 + a1)
      end

      def p_intSub(a0, a1)
        Num.wrap_int(a0 - a1)
      end

      def p_intMul(a0, a1)
        Num.wrap_int(a0 * a1)
      end

      def p_intNegate(a0)
        Num.wrap_int(-a0)
      end

      def p_intQuot(a0, a1)
        Num.wrap_int(Num.quot(a0, nonzero(a1)))
      end

      def p_intRem(a0, a1)
        Num.rem(a0, nonzero(a1))
      end

      def p_intDiv(a0, a1)
        Num.wrap_int(a0 / nonzero(a1))
      end

      def p_intMod(a0, a1)
        a0 % nonzero(a1)
      end

      def p_doubleAdd(a0, a1)
        a0 + a1
      end

      def p_doubleSub(a0, a1)
        a0 - a1
      end

      def p_doubleMul(a0, a1)
        a0 * a1
      end

      def p_doubleDiv(a0, a1)
        a0 / a1
      end

      def p_doubleNegate(a0)
        Num.negate_double(a0)
      end

      def p_doubleEq(a0, a1)
        Builtins.bool(Num.double_eq(a0, a1))
      end

      def p_doubleLt(a0, a1)
        Builtins.bool(a0 < a1)
      end

      def p_doubleLe(a0, a1)
        Builtins.bool(a0 <= a1)
      end

      def p_doubleGt(a0, a1)
        Builtins.bool(a0 > a1)
      end

      def p_doubleGe(a0, a1)
        Builtins.bool(a0 >= a1)
      end

      def p_doubleSqrt(a0)
        a0 < 0 ? NAN : Math.sqrt(a0)
      end

      def p_doubleExp(a0)
        Math.exp(a0)
      end

      def p_doubleLog(a0)
        a0 < 0 ? NAN : Math.log(a0)
      end

      def p_doublePow(a0, a1)
        Num.pow(a0, a1)
      end

      def p_doubleIsNaN(a0)
        Builtins.bool(Num.nan?(a0))
      end

      def p_doubleIsInfinite(a0)
        Builtins.bool(Num.infinite?(a0))
      end

      def p_doubleIsNegativeZero(a0)
        Builtins.bool(Num.negative_zero?(a0))
      end

      def p_doubleDecode(a0)
        m, e = Num.decode_double(a0)
        ConValue.build(Builtins.tuple(2), [m, e])
      end

      def p_doubleTruncate(a0)
        Num.truncate_double(a0)
      end

      def p_doubleFromRational(a0, a1)
        Num.rational_to_double(a0, a1)
      end

      def p_doubleShow(a0)
        str_value(Num.show_double(a0))
      end

      def p_chr(a0)
        c = a0
        raise HsException, "Prelude.chr: bad argument: #{c}" if c < 0 || c > 0x10FFFF

        c
      end

      def p_intToInteger(a0)
        a0
      end

      def p_ord(a0)
        a0
      end

      def p_doubleAbs(a0)
        a0.abs
      end

      def p_doubleSin(a0)
        Math.sin(a0)
      end

      def p_doubleCos(a0)
        Math.cos(a0)
      end

      def p_doubleTan(a0)
        Math.tan(a0)
      end

      def p_doubleAsin(a0)
        a0 < -1.0 || a0 > 1.0 ? NAN : Math.asin(a0)
      end

      def p_doubleAcos(a0)
        a0 < -1.0 || a0 > 1.0 ? NAN : Math.acos(a0)
      end

      def p_doubleAtan(a0)
        Math.atan(a0)
      end

      def p_doubleSinh(a0)
        Math.sinh(a0)
      end

      def p_doubleCosh(a0)
        Math.cosh(a0)
      end

      def p_doubleTanh(a0)
        Math.tanh(a0)
      end

      def p_doubleAsinh(a0)
        Math.asinh(a0)
      end

      def p_doubleAcosh(a0)
        a0 < 1.0 ? NAN : Math.acosh(a0)
      end

      def p_doubleAtanh(a0)
        a0 < -1.0 || a0 > 1.0 ? NAN : Math.atanh(a0)
      end

      def p_doubleFloor(a0)
        Num.floor_double(finite!(a0))
      end

      def p_doubleCeiling(a0)
        Num.ceiling_double(finite!(a0))
      end

      def p_doubleRound(a0)
        Num.round_double(finite!(a0))
      end

      # encodeFloat m e: m * 2^e, correctly rounded.
      def p_doubleEncode(a0, a1)
        a1 >= 0 ? Num.integer_to_double(a0 << a1) : Num.rational_to_double(a0, 1 << -a1)
      end

      def finite!(x)
        return x unless Num.nan?(x) || Num.infinite?(x)

        Num.truncate_double(x) # raises the unsupported error for NaN/Infinity
      end

      # The constructor index of an evaluated constructor value.
      def p_conTag(a0)
        a0[0].tag
      end

      # fromEnum of GHC's GeneralCategory.
      def p_charCategory(c)
        Unicode.category(c)
      end

      def p_charUpper(c)
        Unicode.to_upper(c)
      end

      def p_charLower(c)
        Unicode.to_lower(c)
      end

      def p_charTitle(c)
        Unicode.to_title(c)
      end

      def p_isUpperCase(c)
        Builtins.bool(Unicode.uppercase?(c))
      end

      def p_isLowerCase(c)
        Builtins.bool(Unicode.lowercase?(c))
      end

      # GHC's isSpace: Latin-1 whitespace, else the category Space.
      def p_isSpace(c)
        sp = if c <= 0x377
               c == 32 || (c >= 9 && c <= 13) || c == 0xA0
             else
               Unicode.category(c) == 22
             end
        Builtins.bool(sp)
      end

      # The identity at a different type (ReadP's rank-2 encoding).
      def p_coerce(a0)
        a0
      end

      def p_charEq(a0, a1)
        Builtins.bool(a0 == a1)
      end

      # Write to a handle: 1 stdout (buffered), 2 stderr (stdout is flushed
      # first, so the two interleave in program order).
      def p_hPutChar(h, c)
        if h == 2
          flush_output
          if c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)
            raise HsException, "<stderr>: hPutChar: invalid argument (cannot encode character '\\#{c}')"
          end
          Shim.write(@err, ''.dup << c) if @err
          Shim.flush(@err) if @err
        elsif h == 1
          put_char(c)
        else
          raise HsException, '<stdin>: hPutChar: illegal operation (handle is not open for writing)'
        end
        UNIT_V
      end

      def p_hFlush(h)
        flush_output if h == 1
        UNIT_V
      end

      def p_getChar(_)
        stdin_usable('hGetChar')
        c = next_char
        raise HsException, '<stdin>: hGetChar: end of file' unless c

        c
      end

      def p_getLine(_)
        stdin_usable('hGetLine')
        c = next_char
        raise HsException, '<stdin>: hGetLine: end of file' unless c

        line = ''.dup
        while c && c != 10
          line << c
          c = next_char
        end
        str_value(line)
      end

      def p_isEOF(_)
        stdin_usable('hIsEOF')
        Builtins.bool(eof?)
      end

      def p_getContents(_)
        semi_close_stdin
        UNIT_V
      end

      # The next character of lazily read input, or -1 at its end (which
      # closes stdin).
      def p_readChar(_)
        c = next_char
        return c if c

        @stdin_state = :closed
        -1
      end

      # Buffering modes are remembered and reported, but output always
      # appears in program order: stdout is flushed at each newline, before
      # stderr is written, and before stdin is read.
      def p_setBuffering(h, mode)
        @buffering[h] = mode
        UNIT_V
      end

      # The mode last set for handle h, or dflt (GHCi's NoBuffering).
      def p_getBuffering(h, dflt)
        @buffering[h] || dflt
      end

      def p_getArgs(_)
        list = NIL_V
        @args.reverse_each do |a|
          d = ConValue.new(3)
          d[0] = CONS
          d[1] = str_value(a)
          d[2] = list
          list = d
        end
        list
      end

      def p_putChar(a0)
        put_char(a0)
        UNIT_V
      end

      def p_raise(a0)
        raise HsException, a0
      end

      def bad_operand(xprim)
        raise "machine: primitive #{xprim.prim} given an unevaluated operand"
      end

      def nonzero(b)
        raise HsException, 'divide by zero' if b.zero?

        b
      end
    end
  end
end
