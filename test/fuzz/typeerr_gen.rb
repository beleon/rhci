# frozen_string_literal: true

require_relative 'gen'

# Inputs that should not type-check (test/fuzz/run.rb --typeerrors): a
# well-typed expression from Gen, changed once or twice the way a slip
# would -- an annotation or a literal of another type, an argument dropped,
# doubled or swapped, a near-miss operator, a function around it that may
# not fit, an ambiguous use of a class -- then evaluated or asked `:t`.
# Many changes still type-check (defaulting, polymorphism); rhci must
# accept and reject exactly the inputs GHCi does.
module Fuzz
  class TypeErrGen < Gen
    def section(n)
      Fuzz::IMPORTS + Gen::DECLS + Array.new(n) { probe }
    end

    def probe
      e = expr(random_type(2), 3)
      e = mutate(e)
      e = mutate(e) if chance(0.3)
      chance(0.3) ? ":t #{e}" : e
    end

    # [[start, end]] of the balanced parenthesised groups outside literals.
    def groups(s)
      out = []
      stack = []
      each_code_char(s) do |c, i|
        if c == '('
          stack << i
        elsif c == ')' && !stack.empty?
          out << [stack.pop, i]
        end
      end
      out
    end

    # Yields the characters outside string and Char literals.
    def each_code_char(s)
      i = 0
      while i < s.length
        c = s[i]
        if c == '"'
          i += 1
          i += (s[i] == '\\' ? 2 : 1) while i < s.length && s[i] != '"'
        elsif c == "'" && (i.zero? || s[i - 1] !~ /[A-Za-z0-9_']/)
          j = s[i + 1] == '\\' ? s.index("'", i + 2) : i + 2
          i = j if j && s[j] == "'"
        else
          yield c, i
        end
        i += 1
      end
    end

    # Offsets of whole words outside literals that match pred.
    def words(s)
      out = []
      start = nil
      each_code_char(s + ' ') do |c, i|
        if c =~ /[A-Za-z0-9_'.]/
          start ||= i
        elsif start
          out << [start, i - start]
          start = nil
        end
      end
      out
    end

    def replace_at(s, at, len, text)
      s[0, at] + text + s[(at + len)..-1]
    end

    LITERALS = ['2.5', "'x'", '"x"', 'True', '()', '[]', 'Nothing', '(1 :: Int)', '(2 :: Integer)', '(-1)', 'LT'].freeze
    TYPES = ['Int', 'Integer', 'Double', 'Char', 'Bool', 'String', '[Int]', 'Maybe Int', '(Int, Int)', '()'].freeze
    NEAR_MISSES = [[' + ', ' ++ '], [' ++ ', ' + '], [' == ', ' + '], [' && ', ' || '], [' && ', ' + '],
                   [' . ', ' $ '], [' $ ', ' . '], [' `div` ', ' / '], [' / ', ' `div` '], [' * ', ' ^ '],
                   [' - ', ' : '], [' : ', ' ++ '], [' < ', ' == '], ['map ', 'fmap '], ['map ', 'filter '],
                   ['length ', 'sum '], ['sum ', 'length '], ['show ', 'read '], ['fromIntegral ', 'round '],
                   ['Just ', 'Right '], ['fst ', 'snd '], ['head ', 'tail '], ['concat ', 'concatMap ']].freeze
    WRAPPERS = %w[length not round sqrt fromIntegral negate show succ abs fst head toEnum fromEnum Just
                  maximum sum print return].freeze

    def mutate(e)
      case @r.rand(9)
      when 0 # an annotation of another type
        at = e.index(':: ', @r.rand([e.length, 1].max)) || e.index(':: ')
        return wrap(e) unless at

        stop = at + 3
        stop += 1 while stop < e.length && !')]},'.include?(e[stop])
        replace_at(e, at + 3, stop - at - 3, pick(TYPES))
      when 1 # a literal of another type
        nums = words(e).select { |at, len| e[at, len] =~ /\A\d/ }
        return wrap(e) if nums.empty?

        at, len = pick(nums)
        replace_at(e, at, len, pick(LITERALS))
      when 2 # an argument dropped
        g = groups(e)
        return wrap(e) if g.empty?

        a, b = pick(g)
        replace_at(e, a, b - a + 1, '')
      when 3 # an argument doubled
        g = groups(e)
        return wrap(e) if g.empty?

        a, b = pick(g)
        replace_at(e, b + 1, 0, " #{e[a..b]}")
      when 4 # two arguments swapped
        g = groups(e).sort
        pairs = g.each_cons(2).select { |(_, b1), (a2, _)| e[(b1 + 1)...a2] == ' ' }
        return wrap(e) if pairs.empty?

        (a1, b1), (a2, b2) = pick(pairs)
        e[0, a1] + e[a2..b2] + ' ' + e[a1..b1] + e[(b2 + 1)..-1]
      when 5, 6 # a near-miss operator or function
        options = NEAR_MISSES.select { |from, _| e.include?(from) }
        return wrap(e) if options.empty?

        from, to = pick(options)
        at = e.index(from, @r.rand([e.length, 1].max)) || e.index(from)
        replace_at(e, at, from.length, to)
      when 7 then wrap(e)
      else ambiguous(e)
      end
    end

    def wrap(e)
      "#{pick(WRAPPERS)} (#{e})"
    end

    def ambiguous(e)
      pick(["(#{e}, show (read \"1\"))", "(#{e}) == mempty", "toEnum (fromEnum (#{e}))", "[#{e}, minBound]",
            "fromIntegral (length [#{e}]) / 2", "length [#{e}] / 2", "(#{e}) + 1.5", "realToFrac (#{e})",
            "truncate (#{e})", "read (show (#{e}))", "(#{e}, mempty)", "const (#{e}) undefined",
            "let f x = x + 1 in f (#{e})", "let g = id in (g (#{e}), g 'c')", "\\x -> (#{e}) x"])
    end
  end
end
