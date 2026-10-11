# frozen_string_literal: true

require_relative 'gen'

# Read on damaged input (test/fuzz/run.rb --reads). Text that `show` would
# produce for a random value -- numbers, Chars and Strings with every escape
# form, lists, tuples, Maybe, Either, Ratio, the shared declarations' record
# and infix constructor -- is altered the ways people (and programs) write
# it: other spacing and line breaks, redundant or missing parentheses,
# other spellings of numbers (hex, octal, exponents, signs), truncation,
# trailing text, other case, a dropped or doubled comma. Then `read`,
# `reads`, `readMaybe` or `readEither` at the type decides.
module Fuzz
  class ReadGen
    IMPORTS = ['import Text.Read', 'import Data.Ratio'].freeze
    DECLS = ['data Shape = Circle Double | Rect Double Double | Dot deriving (Show, Read, Eq, Ord)',
             'data R = R { rx :: Int, ry :: Maybe Integer, rs :: String } deriving (Show, Read, Eq, Ord)',
             ':{', 'infixl 6 :+', 'data V = Int :+ Int deriving (Show, Read, Eq, Ord)', ':}'].freeze

    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    def section(n)
      Fuzz::IMPORTS + IMPORTS + DECLS + Array.new(n) { probe }
    end

    TYPES = %w[Int Integer Double Char String Bool Ordering () [Int] (Int,Bool) (Maybe\ Int) (Either\ Int\ Bool)
               [Double] (Int,Int,Int) Rational [[Int]] (Maybe\ (Maybe\ Int)) R V Shape [Char] [(Int,String)]].freeze

    # [type, text show would give].
    def shown(t = pick(TYPES), d = 0)
      text = case t
             when 'Int', 'Integer' then int_text
             when 'Double' then pick(['0.5', '-2.5', '1.0e-2', '1.0e7', '3.0', '-0.0', 'Infinity', 'NaN', '123.456', '5.0e-324'])
             when 'Char' then char_text
             when 'String', '[Char]' then string_text
             when 'Bool' then pick(%w[True False])
             when 'Ordering' then pick(%w[LT EQ GT])
             when '()' then '()'
             when 'Rational' then "#{int_text} % #{@r.rand(1..9)}"
             when '(Int,Bool)' then "(#{int_text},#{pick(%w[True False])})"
             when '(Int,Int,Int)' then "(#{int_text},#{int_text},#{int_text})"
             when '[(Int,String)]' then "[#{Array.new(@r.rand(0..2)) { "(#{int_text},#{string_text})" }.join(',')}]"
             when '[Int]' then "[#{Array.new(@r.rand(0..3)) { int_text }.join(',')}]"
             when '[Double]' then "[#{Array.new(@r.rand(0..3)) { shown('Double')[1] }.join(',')}]"
             when '[[Int]]' then "[#{Array.new(@r.rand(0..2)) { shown('[Int]')[1] }.join(',')}]"
             when '(Maybe Int)' then chance(0.3) ? 'Nothing' : "Just #{paren_neg(int_text)}"
             when '(Maybe (Maybe Int))' then chance(0.3) ? 'Nothing' : "Just #{chance(0.3) ? 'Nothing' : "(Just #{paren_neg(int_text)})"}"
             when '(Either Int Bool)' then chance(0.5) ? "Left #{paren_neg(int_text)}" : "Right #{pick(%w[True False])}"
             when 'R' then "R {rx = #{int_text}, ry = #{chance(0.4) ? 'Nothing' : "Just #{paren_neg(int_text)}"}, rs = #{string_text}}"
             when 'V' then "#{int_text} :+ #{paren_neg(int_text)}"
             else pick(['Dot', "Circle #{paren_neg('2.5')}", "Rect 1.0 #{paren_neg('-3.0')}"])
             end
      [t, text]
    end

    def int_text
      pick(['0', '7', '-3', '42', '-100', '9223372036854775807', '-9223372036854775808', '9223372036854775808',
            '123456789012345678901234567890', '-1'])
    end

    def paren_neg(s)
      s.start_with?('-') ? "(#{s})" : s
    end

    def char_text
      pick(["'a'", "'\\n'", "'\\955'", "'\\''", "'\"'", "'\\\\'", "'\\DEL'", "'\\SOH'", "'\\t'", "'\\1114111'"])
    end

    def string_text
      pick(['""', '"abc"', '"a b"', '"\\955x"', '"\\1234\\&5"', '"\\SO\\&H"', '"tab\\there"', '"q\\"uote"', '"\\\\"'])
    end

    # ---- damage -----------------------------------------------------------------

    def damage(t, s)
      case @r.rand(14)
      when 0, 1 then respace(s)
      when 2 then "(#{s})"
      when 3 then " ( ( #{s} ) ) "
      when 4 then s.sub('(', '').sub(')', '') # unbalanced or unparenthesised negative
      when 5 then numbers(t, s)
      when 6 then s[0, @r.rand(0...[s.length, 1].max)]
      when 7 then s + pick([' x', ')', ' ', '\n', ',', ' -- c', '()'])
      when 8 then chance(0.5) ? s.downcase : s.upcase
      when 9 then s.sub(',', '').sub('= ', '=')
      when 10 then s.sub(',', ',,')
      when 11 then escapes(t, s)
      when 12 then s.gsub(' ', '')
      else s
      end
    end

    def respace(s)
      out = +''
      s.each_char do |c|
        out << pick([' ', "\n", "\t", '  ']) if '(),[]{}=:'.include?(c) && chance(0.5)
        out << c
        out << pick([' ', "\n", '   ']) if '(),[]{}='.include?(c) && chance(0.5)
      end
      chance(0.5) ? "  #{out}\n" : out
    end

    # Other spellings of the same (or a nearby) number.
    def numbers(t, s)
      return "#{s}e0" unless t == 'Int' || t == 'Integer' || t == 'Double' || t == '[Int]'

      pick(['0x1F', '0X1f', '0o17', '0O17', '0b101', '1e3', '1E3', '1.5e1', '12e-1', '1.0', '.5', '5.', '+5', '- 5',
            '--5', ' -  5 ', '(-5)', '((5))', '1_000', '00012', '-0', '0x', '1e', '1e+2', 'NaN', 'Infinity',
            '-Infinity', '1e400', '1e-400', '1e999999999', "\u0663", "#{s}#{s}"]).then do |n|
        t == '[Int]' ? "[#{n},#{n}]" : n
      end
    end

    def escapes(t, s)
      return s unless %w[Char String [Char]].include?(t)

      pick(["'\\x41'", "'\\o101'", "'\\65'", "'\\^A'", "'\\NUL'", "'\\SO'", "'\\SOH'", "''", "'ab'", "'\\&'",
            "'\\1114112'", '"\\x41\\&1"', '"a\\   \\b"', '"\\^@"', '"unterminated', '"\\SOH"', '"\\SO\\&H"',
            '"\\&"', '"\\o12x"', "\"\\x110000\"", '"a"b"'])
    end

    # A Haskell string literal for s.
    def hs_string(s)
      out = +'"'
      prev_numeric = false
      s.each_char do |c|
        o = c.ord
        if prev_numeric && c >= '0' && c <= '9'
          out << '\\&'
        end
        prev_numeric = false
        out << case c
               when '"' then '\\"'
               when '\\' then '\\\\'
               when "\n" then '\\n'
               when "\t" then '\\t'
               else
                 if o < 32 || o == 127
                   prev_numeric = true
                   "\\#{o}"
                 else
                   c
                 end
               end
      end
      out << '"'
    end

    def probe
      t, s = shown
      s = damage(t, s)
      hs = hs_string(s)
      case @r.rand(6)
      when 0, 1 then "read #{hs} :: #{t}"
      when 2 then "reads #{hs} :: [(#{t}, String)]"
      when 3 then "readMaybe #{hs} :: Maybe #{t}"
      when 4 then "readEither #{hs} :: Either String #{t}"
      else "(read #{hs} :: #{t}) == (read #{hs_string(shown(t)[1])} :: #{t})"
      end
    end
  end
end
