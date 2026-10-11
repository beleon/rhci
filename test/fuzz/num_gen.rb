# frozen_string_literal: true

# Numbers at the edges (test/fuzz/run.rb --numbers): Doubles from random bit
# patterns (subnormals, huge, -0.0, NaN, infinities, halves for rounding)
# and Ints and Integers clustered at 2^31, 2^53, 2^63, 2^64, powers of ten
# and beyond, through show and read, Numeric's formatting, the RealFrac and
# RealFloat methods, conversions, Integral arithmetic (zero divisors,
# minBound `div` (-1)), Data.Bits and Data.Ratio.
module Fuzz
  class NumGen
    IMPORTS = ['import Numeric', 'import Data.Bits', 'import Data.Ratio', 'import Text.Printf'].freeze
    INT_MAX = (2**63) - 1
    INT_MIN = -(2**63)

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
      IMPORTS + Array.new(n) { probe }
    end

    # ---- values -----------------------------------------------------------------

    # A Double as a Haskell expression (exact: Ruby's shortest round-trip
    # digits, read back by correctly rounding parsers on both sides).
    def double
      x = case @r.rand(10)
          when 0, 1, 2 then [@r.rand(2**64)].pack('Q').unpack1('D')
          when 3 then [@r.rand(2**52) | (@r.rand(2) << 63)].pack('Q').unpack1('D') # subnormal
          when 4 then pick([0.5, 1.5, 2.5, -2.5, 0.49999999999999994, 4503599627370496.5, 1e22, 1e23,
                            9007199254740993.0, 2.0**63, -(2.0**63), 2.0**64, 1e-5, 0.1, 5e-324, 1.7976931348623157e308])
          when 5 then return pick(['(0/0)', '(1/0)', '(-1/0)', '(-0.0)', '0.0'])
          when 6 then (2.0**@r.rand(-1074..1023)) * pick([1, -1, 1.0000000000000002, 0.9999999999999999])
          else "#{@r.rand(1..999_999)}e#{@r.rand(-330..310)}".to_f * pick([1, -1])
          end
      return pick(['(0/0)', '(1/0)']) if x.nan? || x.infinite?

      s = x.to_s
      s = s.sub('e', '.0e') if s.include?('e') && !s.include?('.')
      x.negative? || (x.zero? && 1 / x < 0) ? "(#{s})" : s
    end

    def int
      v = case @r.rand(6)
          when 0 then pick([0, 1, -1, 2, -2, INT_MAX, INT_MIN, INT_MAX - 1, INT_MIN + 1])
          when 1 then pick([1, -1]) * ((2**pick([31, 32, 53, 62, 63])) + @r.rand(-2..2))
          when 2 then pick([1, -1]) * ((10**@r.rand(0..18)) + @r.rand(-1..1))
          when 3 then @r.rand(-100..100)
          else @r.rand(INT_MIN..INT_MAX)
          end
      v = ((v - INT_MIN) % (2**64)) + INT_MIN
      "(#{v} :: Int)"
    end

    def integer
      v = case @r.rand(5)
          when 0 then pick([1, -1]) * ((2**pick([63, 64, 65, 100, 128, 200])) + @r.rand(-2..2))
          when 1 then pick([1, -1]) * ((10**@r.rand(0..60)) + @r.rand(-1..1))
          when 2 then @r.rand(-100..100)
          when 3 then pick([0, 1, -1, INT_MAX, INT_MIN, INT_MAX + 1, INT_MIN - 1])
          else @r.rand(-(2**130)..(2**130))
          end
      "(#{v} :: Integer)"
    end

    def small
      v = @r.rand(-3..12)
      v.negative? ? "(#{v})" : v.to_s
    end

    def nonneg
      @r.rand(0..70).to_s
    end

    def ratio
      "(#{integer} % #{chance(0.1) ? '0' : integer})"
    end

    # ---- probes -----------------------------------------------------------------

    DOUBLE_UNARY = ['show %s', 'read (show %s) :: Double', 'showFFloat (Just %d) %s ""', 'showEFloat (Just %d) %s ""',
                    'showGFloat (Just %d) %s ""', 'showFFloat Nothing %s ""', 'showEFloat Nothing %s ""',
                    'truncate %s :: Integer', 'round %s :: Integer', 'ceiling %s :: Integer', 'floor %s :: Integer',
                    'truncate %s :: Int', 'round %s :: Int', 'floor %s :: Int', 'ceiling %s :: Int',
                    'properFraction %s :: (Integer, Double)', 'decodeFloat %s', 'significand %s', 'exponent %s',
                    'isDenormalized %s', 'isNegativeZero %s', 'isNaN %s', 'isInfinite %s', 'toRational %s',
                    'fromRational (toRational %s) :: Double', 'sqrt %s', 'exp %s', 'log %s', 'sin %s', 'atan %s',
                    'signum %s', 'abs %s', 'negate %s', 'recip %s', 'scaleFloat %d %s', '%s ^^ %d', '%s ^ 3',
                    'floatToDigits 10 (abs %s)', 'fromIntegral (round %s :: Int) :: Double', 'succ %s',
                    'showHex (truncate (abs %s) :: Integer) ""', 'realToFrac %s :: Double', 'round (%s * 1e10) :: Integer',
                    'printf "%%.3f %%e %%g" %s %s %s :: String', 'take 4 [%s ..]'].freeze

    DOUBLE_BINARY = ['%s + %s', '%s - %s', '%s * %s', '%s / %s', '%s ** %s', 'logBase %s %s', 'atan2 %s %s',
                     'min %s %s', 'max %s %s', 'compare %s %s', '%s == %s', '%s < %s', '%s >= %s',
                     'encodeFloat (truncate %s) (truncate %s `mod` 100)', '(%s, %s)'].freeze

    INT_UNARY = ['show %s', 'read (show %s) :: Int', 'negate %s', 'abs %s', 'signum %s', 'toInteger %s',
                 'fromIntegral %s :: Double', 'fromIntegral %s :: Integer', 'showHex %s ""', 'showOct %s ""',
                 'popCount %s', 'complement %s', 'shiftL %s %n', 'shiftR %s %n', 'rotate %s %d', 'testBit %s %n',
                 'countLeadingZeros %s', 'countTrailingZeros %s', 'setBit %s %n', 'clearBit %s %n', 'succ %s',
                 'pred %s', '%s ^ %n', 'even %s', 'fromEnum %s', 'take 3 [%s ..]', 'take 3 [%s, %s + 1 ..]',
                 'fromIntegral %s :: Int', '%s `shiftL` 1 `div` 2', 'printf "%%d %%5x %%o" %s %s %s :: String'].freeze

    INT_BINARY = ['%s + %s', '%s - %s', '%s * %s', '%s `div` %s', '%s `mod` %s', '%s `quot` %s', '%s `rem` %s',
                  '%s `divMod` %s', '%s `quotRem` %s', 'gcd %s %s', 'lcm %s %s', '%s .&. %s', '%s .|. %s',
                  'xor %s %s', 'compare %s %s', 'max %s %s', '%s `div` (-1)', '%s `quot` 0'].freeze

    INTEGER_UNARY = ['show %s', 'read (show %s) :: Integer', 'fromIntegral %s :: Int', 'fromIntegral %s :: Double',
                     'fromInteger %s :: Double', 'popCount %s', 'complement %s', 'shiftL %s %n', 'shiftR %s %n',
                     'testBit %s %n', '%s ^ %n', 'showHex (abs %s) ""', 'toRational (fromInteger %s :: Double)',
                     'truncate (fromInteger %s :: Double) :: Integer', 'signum %s', 'abs %s', 'succ %s', 'even %s',
                     'fromIntegral %s :: Integer', 'bit (fromIntegral (abs %s `mod` 100)) :: Integer'].freeze

    INTEGER_BINARY = ['%s + %s', '%s - %s', '%s * %s', '%s `div` %s', '%s `mod` %s', '%s `quot` %s', '%s `rem` %s',
                      '%s `divMod` %s', '%s `quotRem` %s', 'gcd %s %s', 'lcm %s %s', '%s .&. %s', '%s .|. %s',
                      'xor %s %s', 'compare %s %s', '%s %% %s', 'fromRational (%s %% %s) :: Double'].freeze

    RATIO_UNARY = ['show %s', 'numerator %s', 'denominator %s', 'truncate %s :: Integer', 'round %s :: Integer',
                   'properFraction %s :: (Integer, Rational)', 'fromRational %s :: Double', 'recip %s', 'floor %s :: Int',
                   '%s + %s', '%s * %s', '%s / %s', 'compare %s %s', 'toRational (fromRational %s :: Double) == %s'].freeze

    def probe
      case @r.rand(10)
      when 0, 1, 2 then fill(pick(DOUBLE_UNARY), -> { double })
      when 3 then fill(pick(DOUBLE_BINARY), -> { double })
      when 4 then fill(pick(INT_UNARY), -> { int })
      when 5 then fill(pick(INT_BINARY), -> { int })
      when 6 then fill(pick(INTEGER_UNARY), -> { integer })
      when 7 then fill(pick(INTEGER_BINARY), -> { integer })
      when 8 then fill(pick(RATIO_UNARY), -> { ratio })
      else mixed
      end
    end

    def mixed
      case @r.rand(6)
      when 0 then "fromIntegral #{int} * #{double}"
      when 1 then "truncate (fromIntegral #{integer} / #{double}) :: Integer"
      when 2 then "realToFrac (#{double}) :: Rational"
      when 3 then "toEnum (fromEnum #{double}) :: Double"
      when 4 then "fromIntegral (#{int}) + fromIntegral (#{int}) :: Integer"
      else "showFFloat (Just #{@r.rand(0..20)}) (fromRational #{ratio} :: Double) \"\""
      end
    end

    # %s: a value; %d: a small Int; %n: a shift or exponent (0..70).
    def fill(template, value)
      out = +''
      i = 0
      while i < template.length
        if template[i] == '%' && i + 1 < template.length
          c = template[i + 1]
          out << case c
                 when 's' then value.call
                 when 'd' then small
                 when 'n' then nonneg
                 else c
                 end
          i += 2
        else
          out << template[i]
          i += 1
        end
      end
      out
    end
  end
end
