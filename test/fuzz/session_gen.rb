# frozen_string_literal: true

require_relative 'prog_gen'

# Random GHCi sessions (test/fuzz/run.rb --sessions): sequences of prompt
# inputs whose meaning depends on what came before -- definitions and
# redefinitions (shadowing: earlier definitions keep the binding they saw),
# `let`, functions on one line or in `:{ :}` blocks (guards, where,
# recursion), `pat <- return e`, expressions and `it`, and `:t`.
#
# Half the sessions also import along the way: Data.Map and Data.Set
# qualified under changing aliases (Data.Map.Strict under the same one,
# import and hiding lists), names from Data.Map unqualified, and the
# Prelude with hiding lists or none; the expressions then use those
# aliases and names, in scope or not, ambiguous or not.
module Fuzz
  class SessionGen < ProgGen
    VALUE_NAMES = %w[x y z w val acc].freeze
    VALUE_TYPES = [INT, INTEGER, DOUBLE, BOOL, STRING, [:list, INT], [:maybe, INT], [:pair, INT, BOOL]].freeze
    SENTINEL = '"end of session"'

    # Prelude names Data.Map exports too. Import sessions import Data.List
    # without them, so that only the Prelude provides them (in GHCi and in
    # rhci alike).
    CLASHING = %w[lookup filter null foldr take drop].freeze
    MAP_NAMES = (%w[insert empty member findWithDefault size fromList toList singleton] + CLASHING).freeze
    MAP_ALIASES = %w[M Mp Q].freeze
    SET_ALIASES = %w[S St Q].freeze

    # The inputs of one session (multi-line ones as ":{\n...\n:}"),
    # imports and the shared declarations first.
    def session(length)
      @env = []
      @funcs = []
      @cons = %w[TC TA TB TD]
      @mq = 'M'
      @sq = 'S'
      @imports = chance(0.5)
      out = header + Gen::DECLS
      out << 'data T = ' + @cons.map { |c| CONS[c][0] }.join(' | ') + ' deriving (Show, Eq, Ord)'
      out << ":{\n#{measure_class.join("\n")}\n:}"
      @fn = 0
      length.times { out.concat(Array(statement)) }
      out << SENTINEL
      out
    end

    def header
      return ProgGen::IMPORTS unless @imports

      base = ProgGen::IMPORTS.reject { |l| l.include?('Data.Map') || l.include?('Data.Set') || l == 'import Data.List' }
      base = ["import Data.List hiding (#{CLASHING.join(', ')})"] + base
      chance(0.5) ? base + ['import qualified Data.Map as M', 'import qualified Data.Set as S'] : base
    end

    def statement
      return import_statement if @imports && chance(0.1)
      return bare_names if @imports && chance(0.08)
      return io_statement if chance(0.12)

      case @r.rand(12)
      when 0, 1 then define_value
      when 2 then "let #{define_value}"
      when 3 then define_function
      when 4 then define_block
      when 5 then bind
      when 6
        names = @env.map(&:first).reject { |n| n == 'it' } + @funcs.map { |f| f[:name] }
        names.empty? ? expression : ":t #{pick(names)}"
      else expression
      end
    end

    # `name = e`; a name already in use is shadowed from here on. The
    # definition is recursive -- `name` in e would mean the new one -- so e
    # is generated without it.
    def define_value
      name = pick(VALUE_NAMES)
      t = pick(VALUE_TYPES)
      @env.reject! { |n, _| n == name }
      e = expr(t, 3)
      bind_name(name, t)
      "#{name} = #{e}"
    end

    def define_function
      name = chance(0.3) && @fn.positive? ? "g#{@r.rand(@fn)}" : "g#{@fn += 1}"
      arg = pick([INT, STRING, [:list, INT], BOOL])
      ret = pick(VALUE_TYPES)
      @funcs.reject! { |f| f[:name] == name } # recursive, like any definition
      body = with_env([['a', arg]]) { expr(ret, 3) }
      @funcs << { name: name, args: [arg], ret: ret }
      "#{name} a = #{body}"
    end

    # A whole function from the program templates, as a `:{ :}` block.
    def define_block
      name = "h#{@fn += 1}"
      lines = function(name)
      ":{\n#{lines.join("\n")}\n:}"
    end

    def bind
      if chance(0.5)
        t = pick(VALUE_TYPES)
        e = expr(t, 3)
        name = pick(VALUE_NAMES)
        bind_name(name, t)
        "#{name} <- return (#{e})"
      else
        a = pick(VALUE_TYPES)
        b = pick(VALUE_TYPES)
        e1 = expr(a, 2)
        e2 = expr(b, 2)
        n1, n2 = VALUE_NAMES.sample(2, random: @r)
        bind_name(n1, a)
        bind_name(n2, b)
        "(#{n1}, #{n2}) <- return (#{e1}, #{e2})"
      end
    end

    # An expression; `it` is its value from then on.
    def expression
      t = pick(VALUE_TYPES + [USERT])
      e = expr(t, 3)
      bind_name('it', t)
      e
    end

    # IO at the prompt: run, its result printed (unless ()) and bound to it.
    def io_statement
      case @r.rand(4)
      when 0
        bind_name('it', :unit)
        "print (#{expr(pick(VALUE_TYPES), 3)})"
      when 1
        bind_name('it', :unit)
        "putStrLn (#{expr(STRING, 2)})"
      when 2
        t = pick(VALUE_TYPES)
        e = expr(t, 3)
        bind_name('it', t)
        "return (#{e})"
      else
        bind_name('it', :unit)
        "mapM_ print [#{expr(INT, 2)}, #{expr(INT, 2)}]"
      end
    end

    # ---- imports --------------------------------------------------------------

    def some(names, max = 4)
      names.sample(@r.rand(1..max), random: @r)
    end

    def import_statement
      case @r.rand(9)
      when 0, 1, 2
        mod = pick(['Data.Map', 'Data.Map', 'Data.Map.Strict'])
        @mq = pick(MAP_ALIASES)
        list = case @r.rand(6)
               when 0 then " (#{(some(MAP_NAMES) + (chance(0.5) ? ['Map'] : [])).join(', ')})"
               when 1 then " hiding (#{some(MAP_NAMES).join(', ')})"
               else ''
               end
        # Without `qualified`, the names come in unqualified as well.
        "import #{chance(0.85) ? 'qualified ' : ''}#{mod} as #{@mq}#{list}"
      when 3
        @sq = pick(SET_ALIASES)
        "import qualified Data.Set as #{@sq}"
      when 4 then "import Data.Map (#{some(MAP_NAMES, 6).join(', ')})"
      when 5 then "import Prelude hiding (#{some(CLASHING).join(', ')})"
      when 6 then chance(0.5) ? 'import Prelude' : "import Prelude (#{some(CLASHING).join(', ')})"
      when 7 then "import Data.List (#{some(CLASHING).join(', ')})"
      else
        # Replaces the implicit Prelude import: unqualified, nothing remains.
        ['import qualified Prelude as P', 'P.length [P.fst (1, 2)]', 'length [1]', 'import Prelude']
      end
    end

    # Data.Map's names (or the Prelude's of the same spelling) unqualified,
    # or under an alias that may not be imported.
    def bare_names
      k = sub(INT, 1)
      m = "(fromList [(#{k}, 'a'), (#{sub(INT, 1)}, 'b')])"
      case @r.rand(12)
      when 0 then "size #{m}"
      when 1 then "findWithDefault 'z' #{sub(INT, 1)} #{m}"
      when 2 then "member #{k} (insert 3 'c' empty)"
      when 3 then "toList (insert #{k} 'x' (singleton 1 'y'))"
      when 4 then chance(0.5) ? "lookup #{k} #{m}" : "lookup #{k} [(#{k}, True)]"
      when 5 then chance(0.5) ? "filter even #{sub([:list, INT], 1)}" : "filter (> 'a') #{m}"
      when 6 then chance(0.5) ? "null #{sub([:list, INT], 1)}" : "null #{m}"
      when 7 then chance(0.5) ? "foldr (:) [] #{m}" : "foldr (+) 0 #{sub([:list, INT], 1)}"
      when 8 then chance(0.5) ? "take 1 #{m}" : "drop 1 #{sub([:list, INT], 1)}"
      when 9 then ":t #{pick(MAP_NAMES)}"
      when 10 then ":t #{pick(MAP_ALIASES)}.#{pick(MAP_NAMES)}"
      else "#{pick(MAP_ALIASES)}.size (#{pick(MAP_ALIASES)}.fromList [(#{k}, #{sub(INT, 1)})])"
      end
    end

    def bind_name(name, t)
      @env.reject! { |n, _| n == name }
      @env << [name, t]
    end
  end
end
