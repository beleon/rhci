# frozen_string_literal: true

module Rhci
  # The small, untyped, named language the desugarer targets and the
  # lowering pass (Lower) compiles for the machine. Dictionary passing is
  # already explicit here; there are no types.
  #
  #   Var(name)            local or global
  #   Lit(value)           Integer (also Char code points) or Float
  #   Str(cps)             string literal (code points), unpacked lazily
  #   App(fn, args)        application
  #   Lam(params, body)
  #   Let(binds, body)     recursive; binds = [[name, expr], ...]
  #   Case(scrut, binder, alts)  forces scrut to WHNF; binder may be nil
  #   Alt(kind, key, vars, body) kind :con (key ConInfo), :lit (key value),
  #                              :default (key nil)
  #   Con(con, args)       saturated constructor application
  #   Prim(op, args)       primitive on already-evaluated atoms
  module Core
    # A data constructor. `tag` is its index among its type's constructors.
    class ConInfo
      attr_reader :name, :tag, :arity, :type_name, :field_names, :fixity
      attr_accessor :siblings, :nullary # nullary: the shared value (VM)

      def initialize(name, tag, arity, type_name, field_names = nil, fixity = nil)
        @name = name
        @tag = tag
        @arity = arity
        @type_name = type_name
        @field_names = field_names
        @fixity = fixity
        @siblings = [self]
      end

      def inspect
        "#<ConInfo #{@name}>"
      end
    end

    # Builds the ConInfos of one type and links them as siblings.
    def self.data_type(type_name, cons)
      infos = []
      cons.each_with_index { |(name, arity), i| infos << ConInfo.new(name, i, arity, type_name) }
      infos.each { |c| c.siblings = infos }
      infos
    end

    class Var
      attr_reader :name

      def initialize(name)
        @name = name
      end
    end

    class Lit
      attr_reader :value

      def initialize(value)
        @value = value
      end
    end

    class Str
      attr_reader :cps

      def initialize(cps)
        @cps = cps
      end
    end

    class App
      attr_reader :fn, :args

      def initialize(fn, args)
        @fn = fn
        @args = args
      end
    end

    class Lam
      attr_reader :params, :body

      def initialize(params, body)
        @params = params
        @body = body
      end
    end

    class Let
      attr_reader :binds, :body

      def initialize(binds, body)
        @binds = binds
        @body = body
      end
    end

    class Case
      attr_reader :scrut, :binder, :alts

      def initialize(scrut, binder, alts)
        @scrut = scrut
        @binder = binder
        @alts = alts
      end
    end

    class Alt
      attr_reader :kind, :key, :vars, :body

      def initialize(kind, key, vars, body)
        @kind = kind
        @key = key
        @vars = vars
        @body = body
      end
    end

    class Con
      attr_reader :con, :args

      def initialize(con, args)
        @con = con
        @args = args
      end
    end

    class Prim
      attr_reader :op, :args

      def initialize(op, args)
        @op = op
        @args = args
      end
    end
  end
end
