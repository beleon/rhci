# frozen_string_literal: true

module Rhci
  # Types for the checker. Plain data, so schemes can be snapshotted.
  #
  #   TMeta   unification variable: `ref` once solved; `level` for
  #           generalisation (Rémy/OCaml-style levels)
  #   TSkol   rigid variable from a signature, with the level it was made at
  #   TCon    type constructor (`name` printed, `key` unique)
  #   TAp     type application (functions are TAp(TAp(->, a), b))
  #   TGen    the i-th quantified variable of a Scheme
  module Types
    class TMeta
      attr_accessor :ref, :level
      attr_reader :id

      def initialize(id, level)
        @id = id
        @level = level
        @ref = nil
      end
    end

    class TSkol
      attr_reader :name, :id, :level

      def initialize(name, id, level)
        @name = name
        @id = id
        @level = level
      end
    end

    class TCon
      attr_reader :name, :key, :arity

      def initialize(name, arity, key = name)
        @name = name
        @key = key
        @arity = arity
      end
    end

    class TAp
      attr_reader :fn, :arg

      def initialize(fn, arg)
        @fn = fn
        @arg = arg
      end
    end

    class TGen
      attr_reader :index

      def initialize(index)
        @index = index
      end
    end

    # forall (nvars generic variables). preds => type
    # preds: [class_name, type] pairs (used from step 5 on).
    class Scheme
      attr_reader :nvars, :preds, :type
      attr_accessor :names # source names of the variables, when known

      def initialize(nvars, type, preds = [])
        @nvars = nvars
        @type = type
        @preds = preds
      end
    end

    ARROW = TCon.new('->', 2)
    LIST = TCon.new('[]', 1)
    UNIT = TCon.new('()', 0)
    # GHC.Types.Any: what GHCi gives a type variable left open by a prompt
    # binding (`xs <- return []` makes xs :: [Any]). It has no instances.
    ANY = TCon.new('Any', 0)
    CHAR = TCon.new('Char', 0)
    INT = TCon.new('Int', 0)
    INTEGER = TCon.new('Integer', 0)
    DOUBLE = TCon.new('Double', 0)
    @tuples = {}

    def self.tuple_con(n)
      @tuples[n] ||= TCon.new("(#{',' * (n - 1)})", n)
    end

    def self.fn(a, b)
      TAp.new(TAp.new(ARROW, a), b)
    end

    def self.list(a)
      TAp.new(LIST, a)
    end

    def self.app(con, args)
      t = con
      args.each { |a| t = TAp.new(t, a) }
      t
    end

    def self.tuple(ts)
      app(tuple_con(ts.length), ts)
    end

    def self.mono(t)
      Scheme.new(0, t)
    end

    # Follow solved metas (with path compression).
    def self.prune(t)
      while t.is_a?(TMeta) && t.ref
        r = t.ref
        r = r.ref while r.is_a?(TMeta) && r.ref
        t.ref = r
        t = r
      end
      t
    end

    # The head constructor and arguments of an application spine.
    def self.spine(t)
      args = []
      t = prune(t)
      while t.is_a?(TAp)
        args.unshift(prune(t.arg))
        t = prune(t.fn)
      end
      [t, args]
    end

    # [argument, result] if t is a function type, else nil.
    def self.split_fn(t)
      h, args = spine(t)
      h.equal?(ARROW) && args.length == 2 ? args : nil
    end

    # ---- printing ------------------------------------------------------------

    # Renders types GHC-style: a -> b, [a], (a, b), Maybe (Maybe a).
    # Unsolved metas and generic variables get names a, b, c, ... in order
    # of first appearance; skolems keep their own names.
    class Printer
      def initialize
        @names = {}
        @used = {}
      end

      def scheme(s)
        t = s.type
        body = type(t)
        return body if s.preds.empty?

        ctx = s.preds.map { |c, ty| "#{c.respond_to?(:name) ? c.name.str : c} #{type(ty, 2)}" }
        ctx = ctx.length == 1 ? ctx[0] : "(#{ctx.join(', ')})"
        "#{ctx} => #{body}"
      end

      # prec: 0 top, 1 function argument, 2 application argument.
      def type(t, prec = 0)
        t = Types.prune(t)
        case t
        when TMeta then var_name("m#{t.id}")
        when TGen then var_name("g#{t.index}")
        when TSkol then t.name
        when TCon then t.name
        else
          h, args = Types.spine(t)
          if h.equal?(ARROW) && args.length == 2
            s = "#{type(args[0], 1)} -> #{type(args[1], 0)}"
            prec > 0 ? "(#{s})" : s
          elsif h.equal?(LIST) && args.length == 1
            "[#{type(args[0])}]"
          elsif h.is_a?(TCon) && h.name.start_with?('(,') && args.length == h.arity
            "(#{args.map { |a| type(a) }.join(', ')})"
          else
            s = ([type(h, 2)] + args.map { |a| type(a, 2) }).join(' ')
            prec > 1 ? "(#{s})" : s
          end
        end
      end

      # Print the scheme variable `index` as `name` (:info prints a data
      # type's constructors with the type's own parameter names).
      def name_gen(index, name)
        @names["g#{index}"] = name
        @used[name] = true
      end

      private

      def var_name(key)
        @names[key] ||= fresh_name
      end

      def fresh_name
        @next ||= 0
        loop do
          i = @next
          @next += 1
          n = ''.dup
          loop do
            n = (97 + i % 26).chr + n
            i = i / 26 - 1
            break if i < 0
          end
          next if @used.key?(n)

          @used[n] = true
          return n
        end
      end
    end
  end
end
