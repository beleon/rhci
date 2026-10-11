# frozen_string_literal: true

require_relative 'prog_gen'

# Random GHCi sessions (test/fuzz/run.rb --sessions): sequences of prompt
# inputs whose meaning depends on what came before -- definitions and
# redefinitions (shadowing: earlier definitions keep the binding they saw),
# `let`, functions on one line or in `:{ :}` blocks (guards, where,
# recursion), `pat <- return e`, expressions and `it`, and `:t`.
module Fuzz
  class SessionGen < ProgGen
    VALUE_NAMES = %w[x y z w val acc].freeze
    VALUE_TYPES = [INT, INTEGER, DOUBLE, BOOL, STRING, [:list, INT], [:maybe, INT], [:pair, INT, BOOL]].freeze
    SENTINEL = '"end of session"'

    # The inputs of one session (multi-line ones as ":{\n...\n:}").
    def session(length)
      @env = []
      @funcs = []
      @cons = %w[TC TA TB TD]
      out = ['data T = ' + @cons.map { |c| CONS[c][0] }.join(' | ') + ' deriving (Show, Eq, Ord)']
      out << ":{\n#{measure_class.join("\n")}\n:}"
      @fn = 0
      length.times { out << statement }
      out << SENTINEL
      out
    end

    def statement
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

    def bind_name(name, t)
      @env.reject! { |n, _| n == name }
      @env << [name, t]
    end
  end
end
