# frozen_string_literal: true

module Rhci
  # Compiles Core to machine code: resolves variables to slots
  # (LocalAtom), closure environments (EnvAtom) or global cells, converts
  # closures to flat environments, and puts the program in A-normal form
  # (arguments, constructor fields and primitive operands become atoms;
  # complex arguments are let-bound as thunks).
  class Lower
    # One code body (a function or thunk): its slot numbering and the
    # variables it captures from enclosing bodies.
    class Body
      attr_reader :captures, :nlocals

      def initialize(parent)
        @parent = parent
        @slots = {}
        @env = {}
        @captures = []
        @nlocals = 0
      end

      # Core binder names are unique within a body (the renamer ensures it);
      # a repeat would silently break lexical scoping, so it is an error.
      def bind(name)
        raise "lower: duplicate binder #{name}" if name && @slots.key?(name)

        slot = new_slot
        @slots[name] = slot if name
        slot
      end

      def new_slot
        @nlocals += 1
        @nlocals - 1
      end

      def local?(name)
        @slots.key?(name) || (@parent && @parent.local?(name))
      end

      # The atom for `name` inside this body (nil if not a local anywhere).
      def lookup(name)
        return VM::LocalAtom.new(@slots[name]) if @slots.key?(name)
        return VM::EnvAtom.new(@env[name]) if @env.key?(name)
        return nil unless @parent && @parent.local?(name)

        @captures << @parent.lookup(name)
        @env[name] = @captures.length - 1
        VM::EnvAtom.new(@env[name])
      end
    end

    # `globals` maps names to VM::Cell.
    def initialize(globals)
      @globals = globals
    end

    # A top-level expression -> ThunkCode with no captures.
    def expression(expr)
      body = Body.new(nil)
      x = compile(expr, body)
      VM::ThunkCode.new([], body.nlocals, x)
    end

    # A global definition -> its value (a Fun, or a CAF thunk).
    def global_value(name, expr)
      if expr.is_a?(Core::Lam)
        VM::Fun.new(lam(expr, nil, name), nil)
      else
        VM::Thunk.new(expression(expr), nil)
      end
    end

    private

    def compile(e, body)
      pending = []
      x = compile_inner(e, body, pending)
      pending.empty? ? x : VM::XLet.new(pending, x)
    end

    def compile_inner(e, body, pending)
      case e
      when Core::Var, Core::Lit then VM::XAtom.new(atom(e, body, pending))
      when Core::Str then VM::XStr.new(e.cps)
      when Core::App
        fn = atom(e.fn, body, pending)
        VM::XApp.new(fn, e.args.map { |a| atom(a, body, pending) })
      when Core::Lam
        slot = body.new_slot
        pending << [slot, :fun, lam(e, body)]
        VM::XAtom.new(VM::LocalAtom.new(slot))
      when Core::Let
        slots = e.binds.map { |name, _| body.bind(name) }
        binds = []
        e.binds.each_with_index { |(_, rhs), i| binds << rhs_bind(slots[i], rhs, body, binds) }
        VM::XLet.new(binds, compile(e.body, body))
      when Core::Case then compile_case(e, body)
      when Core::Con then VM::XCon.new(e.con, e.args.map { |a| atom(a, body, pending) })
      when Core::Prim
        e.args.each do |a|
          raise "lower: primitive #{e.op} needs atomic operands" unless a.is_a?(Core::Var) || a.is_a?(Core::Lit)
        end
        VM::XPrim.new(e.op, e.args.map { |a| atom(a, body, pending) })
      else
        raise "lower: unexpected #{e.class}"
      end
    end

    # A let binding. Extra binds needed for constructor fields go into the
    # same (recursive) group.
    def rhs_bind(slot, rhs, body, group)
      case rhs
      when Core::Lam then [slot, :fun, lam(rhs, body)]
      when Core::Lit then [slot, :value, rhs.value]
      when Core::Str then [slot, :str, rhs.cps]
      when Core::Con
        [slot, :con, [rhs.con, rhs.args.map { |a| atom(a, body, group) }]]
      else [slot, :thunk, thunk(rhs, body)]
      end
    end

    # An atom for `e`; non-atomic expressions are let-bound into `pending`.
    def atom(e, body, pending)
      case e
      when Core::Var
        a = body.lookup(e.name)
        return a if a

        cell = @globals[e.name]
        raise "lower: unknown variable #{e.name}" unless cell

        VM::GlobalAtom.new(cell)
      when Core::Lit then VM::ValueAtom.new(e.value)
      else
        slot = body.new_slot
        pending << rhs_bind(slot, e, body, pending)
        VM::LocalAtom.new(slot)
      end
    end

    def lam(e, parent, name = nil)
      body = Body.new(parent)
      e.params.each { |p| body.bind(p) }
      x = compile(e.body, body)
      VM::LamCode.new(e.params.length, body.captures, body.nlocals, x, name)
    end

    def thunk(e, parent)
      body = Body.new(parent)
      x = compile(e, body)
      VM::ThunkCode.new(body.captures, body.nlocals, x)
    end

    def compile_case(e, body)
      scrut = compile(e.scrut, body)
      binder = e.binder ? body.bind(e.binder) : nil
      con_alts = nil
      lit_alts = nil
      default = nil
      e.alts.each do |alt|
        case alt.kind
        when :con
          con_alts ||= Array.new(alt.key.siblings.length)
          slots = alt.vars.map { |v| v.nil? || v == '_' ? nil : body.bind(v) }
          con_alts[alt.key.tag] = [slots, compile(alt.body, body)]
        when :lit
          lit_alts ||= {}
          lit_alts[alt.key] = compile(alt.body, body)
        else
          default = compile(alt.body, body)
        end
      end
      VM::XCase.new(scrut, binder, con_alts, lit_alts, default)
    end
  end
end
