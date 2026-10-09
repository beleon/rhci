# frozen_string_literal: true

module Rhci
  # The lazy evaluator: an eval/apply machine in the spirit of the STG
  # machine, over code produced by Lower. One `loop` and an explicit frame
  # stack -- evaluation never recurses in Ruby, so the depth of a Haskell
  # computation is bounded by memory, not by the host's call stack.
  module VM
    # ---- runtime values ---------------------------------------------------
    # Unboxed: Integer (Int, Integer, Char), Float (Double).

    # A constructor application. Nullary constructors are shared (Builtins).
    class Data
      attr_reader :con
      attr_accessor :fields # written once, by a recursive let (Machine#allocate)

      def initialize(con, fields)
        @con = con
        @fields = fields
      end

      def inspect
        @fields.empty? ? @con.name : "(#{@con.name} #{@fields.map(&:inspect).join(' ')})"
      end
    end

    # A suspended computation, overwritten with its value when evaluated.
    # state: :pending, :blackhole (under evaluation), :value, :raised
    class Thunk
      attr_accessor :state, :code, :env, :value

      def initialize(code, env)
        @state = :pending
        @code = code
        @env = env
        @value = nil
      end

      def inspect
        @state == :value ? @value.inspect : "<thunk #{@state}>"
      end
    end

    # A string literal, unpacked one cons cell at a time.
    class StringThunk < Thunk
      attr_reader :cps, :index

      def initialize(cps, index)
        super(nil, nil)
        @cps = cps
        @index = index
      end
    end

    class Fun
      attr_accessor :code, :env

      def initialize(code, env)
        @code = code
        @env = env
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

    class LocalAtom
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def get(locals, _env)
        locals[@index]
      end
    end

    class EnvAtom
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def get(_locals, env)
        env[@index]
      end
    end

    class GlobalAtom
      attr_reader :cell

      def initialize(cell)
        @cell = cell
      end

      def get(_locals, _env)
        @cell.value
      end
    end

    class ValueAtom
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def get(_locals, _env)
        @value
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

    class XAtom
      attr_reader :atom

      def initialize(atom)
        @atom = atom
      end
    end

    class XApp
      attr_reader :fn, :args, :fn_x

      def initialize(fn, args)
        @fn = fn
        @args = args
        @fn_x = XAtom.new(fn) # what to evaluate once the args are pushed
      end
    end

    # binds: [slot, kind, payload]; kind :thunk (ThunkCode), :fun (LamCode),
    # :con ([ConInfo, atoms]), :str (code points), :value (a constant).
    class XLet
      attr_reader :binds, :body

      def initialize(binds, body)
        @binds = binds
        @body = body
      end
    end

    # con_alts: Array indexed by tag of [slots, body] (nil = no alt);
    # lit_alts: Hash value => body; default: body or nil.
    class XCase
      attr_reader :scrut, :binder, :con_alts, :lit_alts, :default

      def initialize(scrut, binder, con_alts, lit_alts, default)
        @scrut = scrut
        @binder = binder
        @con_alts = con_alts
        @lit_alts = lit_alts
        @default = default
      end
    end

    class XCon
      attr_reader :con, :args

      def initialize(con, args)
        @con = con
        @args = args
      end
    end

    class XPrim
      attr_reader :op, :args

      def initialize(op, args)
        @op = op
        @args = args
      end
    end

    class XStr
      attr_reader :cps

      def initialize(cps)
        @cps = cps
      end
    end

    # ---- stack frames (besides Thunk = update frame, Array = pending args) ---

    class CaseFrame
      attr_reader :xcase, :locals, :env

      def initialize(xcase, locals, env)
        @xcase = xcase
        @locals = locals
        @env = env
      end
    end

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
      FALSE, TRUE = Core.data_type('Bool', [['False', 0], ['True', 1]])
      NIL, CONS = Core.data_type('[]', [['[]', 0], [':', 2]])
      LT, EQ, GT = Core.data_type('Ordering', [['LT', 0], ['EQ', 0], ['GT', 0]])
      IORES, = Core.data_type('IORes', [['IORes', 1]])

      UNIT_V = (UNIT.nullary = Data.new(UNIT, []))
      FALSE_V = (FALSE.nullary = Data.new(FALSE, []))
      TRUE_V = (TRUE.nullary = Data.new(TRUE, []))
      NIL_V = (NIL.nullary = Data.new(NIL, []))

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

      # out: an IO-like object (write/flush). limits: Hash with optional
      # :steps, :stack (frames), :deadline (monotonic seconds).
      def initialize(out = nil, limits = nil)
        if limits && limits[:deadline] && Shim.now.nil?
          raise UnsupportedError, 'time limits need a clock, which this runtime lacks'
        end

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

      def flush_output
        return if @buf.empty?

        Shim.write(@out, @buf) if @out
        @buf = ''.dup
        Shim.flush(@out) if @out
      end

      # Evaluate a value to weak head normal form.
      def whnf(v)
        return v unless v.is_a?(Thunk)
        return v.value if v.state == :value

        run(XAtom.new(ValueAtom.new(v)), nil, nil)
      end

      # Evaluate compiled code (a ThunkCode with no captures) to WHNF.
      def eval_code(code)
        run(code.body, Array.new(code.nlocals), [])
      end

      # Apply a function value to argument values and evaluate to WHNF.
      def apply(fn, args)
        @stack.push(args.dup)
        base = @stack.length - 1
        run(XAtom.new(ValueAtom.new(fn)), nil, nil, base)
      end

      # Fully evaluate a Haskell list (of WHNF-able elements) into a Ruby
      # Array of WHNF values.
      def list_to_a(v)
        out = []
        cell = whnf(v)
        while cell.con.equal?(CONS)
          out << whnf(cell.fields[0])
          cell = whnf(cell.fields[1])
        end
        out
      end

      # A Haskell String to a Ruby String.
      def string(v)
        s = ''.dup
        list_to_a(v).each { |c| s << c }
        s
      end

      def exception_message(e)
        p = e.payload
        p.is_a?(String) ? p : string(p)
      end

      private

      # The eval/apply loop. Returns the WHNF value once the stack is back
      # at `base` (entry depth), which makes the machine re-entrant for
      # host-side helpers such as `string`.
      def run(expr, locals, env, base = @stack.length)
        stack = @stack
        value = nil
        evaluating = true
        begin
          loop do
            if evaluating
              @steps += 1
              check_limits if @steps >= @next_check
              case expr
              when XAtom
                v = expr.atom.get(locals, env)
                if v.is_a?(Thunk)
                  case v.state
                  when :value
                    value = v.value
                    evaluating = false
                  when :pending
                    if v.is_a?(StringThunk)
                      value = unpack(v)
                      evaluating = false
                    else
                      v.state = :blackhole
                      stack.push(v)
                      code = v.code
                      env = v.env
                      locals = code.nlocals.zero? ? nil : Array.new(code.nlocals)
                      expr = code.body
                    end
                  when :blackhole then raise HsException, '<<loop>>'
                  else raise v.value
                  end
                else
                  value = v
                  evaluating = false
                end
              when XApp
                stack.push(gather(expr.args, locals, env))
                expr = expr.fn_x
              when XCase
                stack.push(CaseFrame.new(expr, locals, env))
                expr = expr.scrut
              when XLet
                allocate(expr.binds, locals, env)
                expr = expr.body
              when XCon
                con = expr.con
                value = con.arity.zero? ? nullary(con) : Data.new(con, gather(expr.args, locals, env))
                evaluating = false
              when XPrim
                value = prim(expr.op, gather(expr.args, locals, env))
                evaluating = false
              when XStr
                value = unpack(StringThunk.new(expr.cps, 0))
                evaluating = false
              else
                raise "machine: unknown code #{expr.class}"
              end
            else
              return value if stack.length == base

              frame = stack.pop
              case frame
              when Thunk
                frame.state = :value
                frame.value = value
                frame.code = nil
                frame.env = nil
              when Array
                fun = value
                args = frame
                if fun.is_a?(PAP)
                  args = fun.args + args
                  fun = fun.fun
                end
                raise "machine: applying a non-function #{fun.inspect}" unless fun.is_a?(Fun)

                code = fun.code
                n = code.arity
                if args.length < n
                  value = PAP.new(fun, args)
                else
                  stack.push(args[n..-1]) if args.length > n
                  env = fun.env
                  locals = Array.new(code.nlocals)
                  i = 0
                  while i < n
                    locals[i] = args[i]
                    i += 1
                  end
                  expr = code.body
                  evaluating = true
                end
              when CaseFrame
                xc = frame.xcase
                locals = frame.locals
                env = frame.env
                locals[xc.binder] = value if xc.binder
                expr = select_alt(xc, value, locals)
                evaluating = true
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
          out[i] = atoms[i].get(locals, env)
          i += 1
        end
        out
      end

      def nullary(con)
        con.nullary ||= Data.new(con, [])
      end

      def select_alt(xc, value, locals)
        if xc.con_alts
          alt = xc.con_alts[value.con.tag]
          if alt
            slots = alt[0]
            fields = value.fields
            i = 0
            while i < slots.length
              s = slots[i]
              locals[s] = fields[i] if s
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
            when :thunk then Thunk.new(payload, nil)
            when :fun then Fun.new(payload, nil)
            when :con then payload[0].arity.zero? ? nullary(payload[0]) : Data.new(payload[0], nil)
            when :str then StringThunk.new(payload, 0)
            else payload
            end
          i += 1
        end
        i = 0
        while i < n
          slot, kind, payload = binds[i]
          case kind
          when :thunk, :fun
            obj = locals[slot]
            caps = obj.code.captures
            obj.env = caps.empty? ? nil : gather(caps, locals, env)
          when :con
            locals[slot].fields = gather(payload[1], locals, env) unless payload[1].empty?
          end
          i += 1
        end
      end

      def unpack(st)
        return st.value if st.state == :value

        v = if st.index >= st.cps.length
              NIL_V
            else
              Data.new(CONS, [st.cps[st.index], StringThunk.new(st.cps, st.index + 1)])
            end
        st.state = :value
        st.value = v
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
            f.state = :raised
            f.value = exc
            f.code = nil
            f.env = nil
          else
            f.state = :pending
          end
        end
      end

      def check_limits
        @next_check = @steps + CHECK_EVERY
        if @interrupted
          @interrupted = false
          raise LimitExceeded, 'Interrupted.'
        end
        max = @limits[:steps]
        raise LimitExceeded, "step limit (#{max}) exceeded" if max && @steps > max

        max = @limits[:stack]
        raise LimitExceeded, "stack limit (#{max} frames) exceeded" if max && @stack.length > max

        deadline = @limits[:deadline]
        raise LimitExceeded, 'time limit exceeded' if deadline && Shim.now > deadline
      end

      # A primitive's String result, in WHNF like every primitive result.
      def str_value(s)
        unpack(StringThunk.new(s.codepoints, 0))
      end

      def put_char(c)
        if c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)
          raise HsException, "<stdout>: hPutChar: invalid argument (cannot encode character '\\#{c}')"
        end

        @buf << c
        flush_output if c == 10 || @buf.length >= 4096
      end

      # ---- primitives: arguments are WHNF values -------------------------------

      LAZY_PRIMS = { raise: true }.freeze

      def prim(op, a)
        unless LAZY_PRIMS.key?(op)
          i = 0
          while i < a.length
            raise "machine: primitive #{op} given an unevaluated argument" if a[i].is_a?(Thunk)

            i += 1
          end
        end
        case op
        # Integer (unbounded)
        when :integerAdd then a[0] + a[1]
        when :integerSub then a[0] - a[1]
        when :integerMul then a[0] * a[1]
        when :integerNegate then -a[0]
        when :integerQuot then Num.quot(a[0], nonzero(a[1]))
        when :integerRem then Num.rem(a[0], nonzero(a[1]))
        when :integerDiv then a[0] / nonzero(a[1])
        when :integerMod then a[0] % nonzero(a[1])
        when :integerEq then Builtins.bool(a[0] == a[1])
        when :integerLt then Builtins.bool(a[0] < a[1])
        when :integerLe then Builtins.bool(a[0] <= a[1])
        when :integerGt then Builtins.bool(a[0] > a[1])
        when :integerGe then Builtins.bool(a[0] >= a[1])
        when :integerToInt then Num.wrap_int(a[0])
        when :integerToDouble then Num.integer_to_double(a[0])
        when :integerShow then str_value(a[0].to_s)
        # Int (64-bit, wrapping; edge cases like minBound `div` (-1) are
        # handled by the Prelude, as in GHC's base)
        when :intAdd then Num.wrap_int(a[0] + a[1])
        when :intSub then Num.wrap_int(a[0] - a[1])
        when :intMul then Num.wrap_int(a[0] * a[1])
        when :intNegate then Num.wrap_int(-a[0])
        when :intQuot then Num.wrap_int(Num.quot(a[0], nonzero(a[1])))
        when :intRem then Num.rem(a[0], nonzero(a[1]))
        when :intDiv then Num.wrap_int(a[0] / nonzero(a[1]))
        when :intMod then a[0] % nonzero(a[1])
        # Double
        when :doubleAdd then a[0] + a[1]
        when :doubleSub then a[0] - a[1]
        when :doubleMul then a[0] * a[1]
        when :doubleDiv then a[0] / a[1]
        when :doubleNegate then -a[0]
        when :doubleEq then Builtins.bool(Num.double_eq(a[0], a[1]))
        when :doubleLt then Builtins.bool(a[0] < a[1])
        when :doubleLe then Builtins.bool(a[0] <= a[1])
        when :doubleGt then Builtins.bool(a[0] > a[1])
        when :doubleGe then Builtins.bool(a[0] >= a[1])
        when :doubleSqrt then a[0] < 0 ? NAN : Math.sqrt(a[0])
        when :doubleExp then Math.exp(a[0])
        when :doubleLog then a[0] < 0 ? NAN : Math.log(a[0])
        when :doublePow then Num.pow(a[0], a[1])
        when :doubleIsNaN then Builtins.bool(Num.nan?(a[0]))
        when :doubleIsInfinite then Builtins.bool(Num.infinite?(a[0]))
        when :doubleIsNegativeZero then Builtins.bool(Num.negative_zero?(a[0]))
        when :doubleDecode
          m, e = Num.decode_double(a[0])
          Data.new(Builtins.tuple(2), [m, e])
        when :doubleTruncate then Num.truncate_double(a[0])
        when :doubleFromRational then Num.rational_to_double(a[0], a[1])
        when :doubleShow then str_value(Num.show_double(a[0]))
        # Char (code points)
        when :chr
          c = a[0]
          raise HsException, "Prelude.chr: bad argument: #{c}" if c < 0 || c > 0x10FFFF

          c
        # Effects and failure
        when :putChar
          put_char(a[0])
          UNIT_V
        when :raise then raise HsException, a[0]
        else raise "machine: unknown primitive #{op}"
        end
      end

      def nonzero(b)
        raise HsException, 'divide by zero' if b.zero?

        b
      end
    end
  end
end
