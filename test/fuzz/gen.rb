# frozen_string_literal: true

# Random well-typed Haskell expressions over rhci's supported surface, for
# differential testing against GHCi (test/fuzz/run.rb). Deterministic for a
# given seed. Int and Double literals carry annotations, so every
# expression has the type it was generated at; transcendental functions
# are avoided (their last bit depends on the C library).
module Fuzz
  class Gen
    INT = :int
    INTEGER = :integer
    DOUBLE = :double
    BOOL = :bool
    CHAR = :char
    STRING = :string
    ORDERING = :ordering

    SCALARS = [INT, INTEGER, DOUBLE, BOOL, CHAR, STRING].freeze
    SHAPE = :shape   # data Shape = Circle Double | Rect Double Double | Dot
    REC = :rec       # data R = R { rx :: Int, ry :: Maybe Integer, rs :: String }
    PAIRT = :pairt   # data V = Int :+ Int (infixl 6 :+)
    USER = [SHAPE, REC, PAIRT].freeze

    # Declarations each section starts with (after its imports).
    DECLS = [
      'data Shape = Circle Double | Rect Double Double | Dot deriving (Show, Eq, Ord)',
      'data R = R { rx :: Int, ry :: Maybe Integer, rs :: String } deriving (Show, Eq, Ord)',
      ':{',
      'infixl 6 :+',
      'data V = Int :+ Int deriving (Show, Eq, Ord)',
      ':}',
      # A class with a default, a superclass, instances with contexts, and
      # a constructor class.
      ':{',
      'class Describe a where',
      '  describe :: a -> String',
      '  describe _ = "thing"',
      '  tag :: a -> Int',
      ':}',
      ':{',
      'class Describe a => Rank a where',
      '  rank :: a -> Integer',
      '  rank x = toInteger (tag x) * 10',
      ':}',
      'instance Describe Int where tag n = n * 2',
      'instance Describe Bool where { describe b = if b then "yes" else "no"; tag b = fromEnum b }',
      'instance Describe Char where { describe c = [c, c]; tag = fromEnum }',
      'instance Describe a => Describe [a] where { describe xs = concatMap describe xs; tag = sum . map tag }',
      'instance (Describe a, Describe b) => Describe (a, b) where { describe (a, b) = describe a ++ "&" ++ describe b; tag (a, b) = tag a - tag b }',
      'instance Describe a => Describe (Maybe a) where { tag = maybe (-1) tag }',
      'instance Rank Int',
      'instance Rank Bool where rank b = if b then 1 else 0',
      'instance Rank a => Rank [a] where rank = product . map rank',
      ':{',
      'class Box f where',
      '  boxMap :: (a -> b) -> f a -> f b',
      '  boxSize :: f a -> Int',
      ':}',
      'instance Box Maybe where { boxMap = fmap; boxSize = maybe 0 (const 1) }',
      'instance Box [] where { boxMap = map; boxSize = length }'
    ].freeze

    # Types with a Describe instance (Rank: those with a Rank instance).
    DESCRIBABLE = [INT, BOOL, CHAR, STRING, [:list, INT], [:pair, INT, BOOL], [:maybe, CHAR], [:list, [:pair, BOOL, CHAR]]].freeze
    RANKABLE = [INT, BOOL, [:list, INT], [:list, BOOL]].freeze
    ELEMS = [INT, INTEGER, DOUBLE, BOOL, CHAR].freeze

    # bottoms: how often a leaf is a tagged error, `(error "e17" :: T)`;
    # the tag shows which one was evaluated first.
    def initialize(seed, bottoms: 0.0)
      @r = Random.new(seed)
      @bottoms = bottoms
      @tag = 0
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    # A top-level probe: an expression of a random type, or `:t` of an
    # unannotated (often polymorphic, sometimes ill-typed) one.
    def probe
      return ":t #{poly(3)}" if chance(0.12)

      expr(random_type(2), 4)
    end

    POLY = %w[map filter foldr foldl (.) ($) id const flip (+) (*) (-) (==) (<) (++) concat concatMap zip zipWith
              fst snd head tail length sum show read fmap pure return (>>=) Just maybe either Left Right uncurry curry
              not (&&) elem lookup replicate take drop reverse sequence mapM_ print (<$>) (<*>) foldMap mempty (<>)
              compare max succ toEnum fromEnum fromIntegral realToFrac (/) div even words unwords describe tag rank
              boxMap boxSize].freeze

    def poly(d)
      return pick(POLY + ['1', '2.5', "'c'", '"s"', 'True', '[]', 'Nothing', '(+ 1)', '(* 2)', '(> 0)']) if d <= 0 || chance(0.25)

      case @r.rand(5)
      when 0, 1 then "(#{poly(d - 1)} #{poly(d - 1)})"
      when 2 then "(#{poly(d - 1)} . #{poly(d - 1)})"
      when 3 then "(\\x -> #{poly(d - 1).sub(pick(POLY), 'x')})"
      else "(#{poly(d - 1)} #{poly(d - 1)} #{poly(d - 1)})"
      end
    end

    def random_type(depth)
      return pick(SCALARS) if depth.zero? || chance(0.4)

      case @r.rand(7)
      when 0 then [:list, random_type(depth - 1)]
      when 1 then [:maybe, random_type(depth - 1)]
      when 2 then [:pair, random_type(depth - 1), random_type(depth - 1)]
      when 3 then pick(USER)
      when 4 then [:map, pick([INT, CHAR, STRING]), random_type(depth - 1)]
      when 5 then [:set, pick([INT, CHAR, STRING, SHAPE])]
      else ORDERING
      end
    end

    def list_of(t)
      [:list, t]
    end

    def num?(t)
      [INT, INTEGER, DOUBLE].include?(t)
    end

    def integral?(t)
      [INT, INTEGER].include?(t)
    end

    def ord?(t)
      t != :fun
    end

    def hs_type(t)
      case t
      when INT then 'Int'
      when INTEGER then 'Integer'
      when DOUBLE then 'Double'
      when BOOL then 'Bool'
      when CHAR then 'Char'
      when STRING then 'String'
      when ORDERING then 'Ordering'
      when SHAPE then 'Shape'
      when REC then 'R'
      when PAIRT then 'V'
      else
        case t[0]
        when :map then "M.Map #{paren_type(t[1])} #{paren_type(t[2])}"
        when :set then "S.Set #{paren_type(t[1])}"
        when :list then "[#{hs_type(t[1])}]"
        when :maybe then "Maybe #{paren_type(t[1])}"
        when :pair then "(#{hs_type(t[1])}, #{hs_type(t[2])})"
        end
      end
    end

    def paren_type(t)
      s = hs_type(t)
      s.include?(' ') && !s.start_with?('[', '(') ? "(#{s})" : s
    end

    # ---- expressions ---------------------------------------------------------------

    def expr(t, d)
      return leaf(t) if d <= 0 || chance(0.15)

      e = case t
          when INT then int_expr(d)
          when INTEGER then integer_expr(d)
          when DOUBLE then double_expr(d)
          when BOOL then bool_expr(d)
          when CHAR then char_expr(d)
          when STRING then string_expr(d)
          when ORDERING then "compare #{sub(ord_elem = pick(ELEMS + USER), d)} #{sub(ord_elem, d)}"
          when SHAPE then shape_expr(d)
          when REC then rec_expr(d)
          when PAIRT then "#{sub(INT, d)} :+ #{sub(INT, d)} :: V"
          else
            case t[0]
            when :list then list_expr(t[1], d)
            when :maybe then maybe_expr(t[1], d)
            when :pair then pair_expr(t[1], t[2], d)
            when :map then map_expr(t[1], t[2], d)
            when :set then set_expr(t[1], d)
            end
          end
      e || leaf(t)
    end

    def sub(t, d)
      "(#{expr(t, d - 1)})"
    end

    def small_int
      "(#{@r.rand(-3..12)} :: Int)"
    end

    def leaf(t)
      if @bottoms.positive? && chance(@bottoms)
        @tag += 1
        return "(error \"e#{@tag}\" :: #{hs_type(t)})"
      end

      case t
      when INT then "(#{pick([0, 1, -1, 2, 3, 7, 10, -12, 42, 100, 9223372036854775807, -9223372036854775807, 255])} :: Int)"
      when INTEGER then pick(%w[0 1 2 -3 10 99 12345678901234567890 -98765432109876543210 1000000007])
      when DOUBLE then "(#{pick(%w[0.0 1.0 -1.5 0.1 0.2 2.5 3.0 1.0e-2 1.0e7 123.456 -0.0 5.0e-324 1.7976931348623157e308 0.30000000000000004])} :: Double)"
      when BOOL then pick(%w[True False])
      when CHAR then pick(["'a'", "'Z'", "'0'", "' '", "'\\n'", "'\\955'", "'\\t'", "'\\DEL'", "'~'", "'\\''", "'\"'"])
      when STRING then pick(['""', '"hello"', '"a b  c"', '"Hello, World!"', '"\\955x"', '"line1\\nline2"', '"12"', '"-7"', '"q\\"uote"', '"tab\\there"'])
      when ORDERING then pick(%w[LT EQ GT])
      when SHAPE then pick(['(Circle (-1.5))', '(Rect 2.0 (-0.0))', 'Dot', '(Circle 1.0e-2)'])
      when REC then pick(['(R { rx = -3, ry = Just (-7), rs = "a\\nb" })', '(R 1 Nothing "")', '(R { rx = 0, ry = Just 12345678901234567890, rs = "λ" })'])
      when PAIRT then pick(['((-1) :+ 2)', '(3 :+ (-4))', '(0 :+ 0)'])
      else
        case t[0]
        when :map then "(M.fromList [#{Array.new(@r.rand(0..3)) { "(#{leaf(t[1])}, #{leaf(t[2])})" }.join(', ')}] :: #{hs_type(t)})"
        when :set then "(S.fromList [#{Array.new(@r.rand(0..3)) { leaf(t[1]) }.join(', ')}] :: #{hs_type(t)})"
        when :list then chance(0.3) ? "([] :: #{hs_type(t)})" : "[#{Array.new(@r.rand(1..4)) { leaf(t[1]) }.join(', ')}]"
        when :maybe then chance(0.3) ? "(Nothing :: #{hs_type(t)})" : "(Just #{leaf(t[1])})"
        when :pair then "(#{leaf(t[1])}, #{leaf(t[2])})"
        end
      end
    end

    def int_expr(d)
      case @r.rand(22)
      when 0 then "#{sub(INT, d)} + #{sub(INT, d)}"
      when 1 then "#{sub(INT, d)} - #{sub(INT, d)}"
      when 2 then "#{sub(INT, d)} * #{sub(INT, d)}"
      when 3 then "#{pick(%w[div mod quot rem])} #{sub(INT, d)} #{sub(INT, d)}"
      when 4 then "#{pick(%w[negate abs signum])} #{sub(INT, d)}"
      when 5 then "#{pick(%w[min max gcd lcm])} #{sub(INT, d)} #{sub(INT, d)}"
      when 6 then "length #{sub(list_of(pick(ELEMS)), d)}"
      when 7 then "sum #{sub(list_of(INT), d)}"
      when 8 then "fromIntegral #{sub(INTEGER, d)} :: Int"
      when 9 then "#{pick(%w[round truncate ceiling floor])} #{sub(DOUBLE, d)} :: Int"
      when 10 then "fromEnum #{sub(pick([CHAR, BOOL, ORDERING]), d)}"
      when 11 then "#{sub(INT, d)} ^ (#{@r.rand(0..5)} :: Int)"
      when 12 then "head #{sub(list_of(INT), d)}"
      when 13 then "#{sub(list_of(INT), d)} !! #{small_int}"
      when 14 then "foldr (\\x acc -> x - acc) #{sub(INT, d)} #{sub(list_of(INT), d)}"
      when 15 then "foldl (\\acc x -> acc * 2 + x) #{sub(INT, d)} #{sub(list_of(INT), d)}"
      when 16 then "maybe #{sub(INT, d)} (+ 1) #{sub([:maybe, INT], d)}"
      when 17 then "if #{sub(BOOL, d)} then #{sub(INT, d)} else #{sub(INT, d)}"
      when 18 then "case #{sub([:maybe, INT], d)} of { Nothing -> #{sub(INT, d)}; Just v -> v * 3 }"
      when 19 then "fst #{sub([:pair, INT, BOOL], d)}"
      when 20
        case @r.rand(4)
        when 0 then "tag #{sub(pick(DESCRIBABLE), d)}"
        when 1 then "boxSize (boxMap #{endo(INT)} #{sub(pick([[:maybe, INT], [:list, INT]]), d)})"
        when 2 then "length (reads #{sub(STRING, d)} :: [(Int, String)])"
        else "read #{sub(STRING, d)} :: Int"
        end
      else
        case @r.rand(3)
        when 0 then "M.size #{sub([:map, pick([INT, CHAR]), pick(ELEMS)], d)}"
        when 1 then "S.size #{sub([:set, pick([INT, CHAR])], d)}"
        else "maximum #{sub(list_of(INT), d)}"
        end
      end
    end

    def integer_expr(d)
      case @r.rand(14)
      when 0 then "#{sub(INTEGER, d)} + #{sub(INTEGER, d)}"
      when 1 then "#{sub(INTEGER, d)} * #{sub(INTEGER, d)}"
      when 2 then "#{pick(%w[div mod quot rem])} #{sub(INTEGER, d)} #{sub(INTEGER, d)}"
      when 3 then "toInteger #{sub(INT, d)}"
      when 4 then "2 ^ (#{@r.rand(0..130)} :: Int) - #{sub(INTEGER, d)}"
      when 5 then chance(0.5) ? "product [1 .. #{@r.rand(0..25)}] :: Integer" : "rank #{sub(pick(RANKABLE), d)}"
      when 6 then "#{pick(%w[negate abs signum])} #{sub(INTEGER, d)}"
      when 7 then "#{pick(%w[gcd lcm min max])} #{sub(INTEGER, d)} #{sub(INTEGER, d)}"
      when 8 then "#{pick(%w[round truncate ceiling floor])} #{sub(DOUBLE, d)} :: Integer"
      when 9 then "sum #{sub(list_of(INTEGER), d)}"
      when 10 then "fromIntegral #{sub(INT, d)} * #{sub(INTEGER, d)}"
      when 11 then "read #{sub(STRING, d)} :: Integer"
      when 12 then "fst (#{sub(INTEGER, d)} `divMod` #{sub(INTEGER, d)})"
      else "snd (#{sub(INTEGER, d)} `quotRem` #{sub(INTEGER, d)})"
      end
    end

    def double_expr(d)
      case @r.rand(14)
      when 0 then "#{sub(DOUBLE, d)} + #{sub(DOUBLE, d)}"
      when 1 then "#{sub(DOUBLE, d)} - #{sub(DOUBLE, d)}"
      when 2 then "#{sub(DOUBLE, d)} * #{sub(DOUBLE, d)}"
      when 3 then "#{sub(DOUBLE, d)} / #{sub(DOUBLE, d)}"
      when 4 then "sqrt (abs #{sub(DOUBLE, d)})"
      when 5 then "fromIntegral #{sub(pick([INT, INTEGER]), d)} :: Double"
      when 6 then "#{pick(%w[negate abs signum recip])} #{sub(DOUBLE, d)}"
      when 7 then "#{pick(%w[min max])} #{sub(DOUBLE, d)} #{sub(DOUBLE, d)}"
      when 8 then "sum #{sub(list_of(DOUBLE), d)}"
      when 9 then "realToFrac #{sub(DOUBLE, d)} :: Double"
      when 10 then "#{sub(DOUBLE, d)} ^ (#{@r.rand(0..4)} :: Int)"
      when 11 then "#{sub(DOUBLE, d)} ** 2"
      when 12 then "read #{sub(STRING, d)} :: Double"
      else "fromIntegral (round #{sub(DOUBLE, d)} :: Integer) / 4 :: Double"
      end
    end

    def bool_expr(d)
      case @r.rand(12)
      when 0
        t = pick(ELEMS + [STRING, [:list, INT], [:maybe, INT]])
        "#{sub(t, d)} #{pick(%w[== /= < <= > >=])} #{sub(t, d)}"
      when 1 then "#{sub(BOOL, d)} #{pick(%w[&& ||])} #{sub(BOOL, d)}"
      when 2 then "not #{sub(BOOL, d)}"
      when 3 then "#{pick(%w[even odd])} #{sub(pick([INT, INTEGER]), d)}"
      when 4 then "elem #{sub(INT, d)} #{sub(list_of(INT), d)}"
      when 5 then "null #{sub(list_of(pick(ELEMS)), d)}"
      when 6 then "#{pick(%w[any all])} even #{sub(list_of(INT), d)}"
      when 7 then "#{pick(%w[isDigit isUpper isLower isSpace isAlpha isPunctuation])} #{sub(CHAR, d)}"
      when 8 then "isNaN #{sub(DOUBLE, d)}"
      when 9 then "#{pick(%w[isPrefixOf isSuffixOf isInfixOf])} #{sub(STRING, d)} #{sub(STRING, d)}"
      when 10 then "and #{sub(list_of(BOOL), d)}"
      else
        case @r.rand(4)
        when 0 then "M.member #{sub(INT, d)} #{sub([:map, INT, pick(ELEMS)], d)}"
        when 1 then "S.member #{sub(CHAR, d)} #{sub([:set, CHAR], d)}"
        when 2 then "S.isSubsetOf #{sub([:set, INT], d)} #{sub([:set, INT], d)}"
        else "maybe False even #{sub([:maybe, INT], d)}"
        end
      end
    end

    def char_expr(d)
      case @r.rand(7)
      when 0 then "#{pick(%w[toUpper toLower])} #{sub(CHAR, d)}"
      when 1 then "chr (65 + #{sub(INT, d)} `mod` 26)"
      when 2 then "head #{sub(STRING, d)}"
      when 3 then "last #{sub(STRING, d)}"
      when 4 then "#{pick(%w[succ pred])} #{sub(CHAR, d)}"
      when 5 then "#{sub(STRING, d)} !! #{small_int}"
      else "maximum #{sub(STRING, d)}"
      end
    end

    def string_expr(d)
      case @r.rand(14)
      when 0 then "show #{sub(random_type(2), d)}"
      when 1 then "#{sub(STRING, d)} ++ #{sub(STRING, d)}"
      when 2 then "map #{pick(%w[toUpper toLower succ])} #{sub(STRING, d)}"
      when 3 then "reverse #{sub(STRING, d)}"
      when 4 then "#{pick(%w[take drop])} #{small_int} #{sub(STRING, d)}"
      when 5 then "unwords (words #{sub(STRING, d)})"
      when 6 then "unlines (lines #{sub(STRING, d)})"
      when 7 then "concatMap show #{sub(list_of(pick(ELEMS)), d)}"
      when 8 then "filter #{pick(%w[isAlpha isDigit isSpace])} #{sub(STRING, d)}"
      when 9 then "replicate (#{@r.rand(0..4)} :: Int) #{sub(CHAR, d)}"
      when 10 then "[#{sub(CHAR, d)}, #{sub(CHAR, d)}]"
      when 11 then "showsPrec #{@r.rand(0..11)} #{sub(pick([INT, DOUBLE, [:maybe, INT]]), d)} \"\""
      when 12 then "intercalate \", \" #{sub(list_of(STRING), d)}"
      when 13 then printf_expr(d)
      when 14 then "describe #{sub(pick(DESCRIBABLE), d)}"
      when 15 then "show (#{read_expr(d)})"
      else "sort #{sub(STRING, d)}"
      end
    end

    # printf with a random format: each argument gets a conversion that fits
    # its type, with random flags, widths and precisions.
    def printf_expr(d)
      parts = []
      args = []
      @r.rand(1..3).times do
        t = pick([INT, INTEGER, DOUBLE, STRING, CHAR])
        flags = pick(['', '', '-', '0', '+', ' ', '#'])
        width = pick(['', '', '3', '8'])
        conv = case t
               when INT, INTEGER then pick(%w[d d x X o u])
               when DOUBLE then pick(%w[f e g])
               when STRING then 's'
               else 'c'
               end
        prec = if t == DOUBLE then pick(['', '.0', '.2', '.5'])
               elsif t == STRING then pick(['', '', '.2'])
               else ''
               end
        flags = '' if %w[s c].include?(conv) && flags != '-'
        parts << "#{pick(['', 'x=', ' | '])}%#{flags}#{width}#{prec}#{conv}"
        args << sub(t, d)
      end
      parts << pick(['', '%%', '!'])
      "printf #{parts.join.inspect} #{args.join(' ')} :: String"
    end

    # read of a value's show (sometimes padded or parenthesised), at its type.
    def read_expr(d)
      t = pick(ELEMS + USER + [STRING, [:list, INT], [:maybe, INT], [:pair, INT, CHAR], [:list, [:maybe, DOUBLE]],
                               [:map, INT, STRING], [:set, CHAR], ORDERING])
      s = "show #{sub(t, d)}"
      s = pick(["\" \" ++ #{s} ++ \"  \"", "\"(\" ++ #{s} ++ \")\"", "\"((\" ++ #{s} ++ \"))\"", s, s])
      "read (#{s}) :: #{hs_type(t)}"
    end

    def list_expr(e, d)
      t = list_of(e)
      case @r.rand(16)
      when 0 then "#{sub(t, d)} ++ #{sub(t, d)}"
      when 1 then "reverse #{sub(t, d)}"
      when 2 then "#{pick(%w[take drop])} #{small_int} #{sub(t, d)}"
      when 3 then "filter #{pred(e)} #{sub(t, d)}"
      when 4 then "map #{endo(e)} #{sub(t, d)}"
      when 5 then "sort #{sub(t, d)}"
      when 6 then "nub #{sub(t, d)}"
      when 7 then "replicate (#{@r.rand(0..3)} :: Int) #{sub(e, d)}"
      when 8 then range(e, d)
      when 9 then "#{pick(%w[tail init])} #{sub(t, d)}"
      when 10 then "concat [#{sub(t, d)}, #{sub(t, d)}]"
      when 11 then "#{pick(%w[takeWhile dropWhile])} #{pred(e)} #{sub(t, d)}"
      when 12 then "snd (span #{pred(e)} #{sub(t, d)})"
      when 13 then "take (#{@r.rand(0..6)} :: Int) (cycle #{sub(t, d)})"
      when 14 then "[x | x <- #{sub(t, d)}, #{pred(e)} x]"
      else
        case @r.rand(4)
        when 0 then "M.elems #{sub([:map, pick([INT, CHAR]), e], d)}"
        when 1 then "S.toList (S.fromList #{sub(t, d)})"
        when 2 then "map snd (M.toList #{sub([:map, INT, e], d)})"
        else "zipWith const #{sub(t, d)} #{sub(list_of(pick(ELEMS)), d)}"
        end
      end
    end

    def range(e, _d)
      case e
      when INT then "[(#{@r.rand(-5..5)} :: Int) .. #{@r.rand(-5..10)}]"
      when INTEGER
        a = @r.rand(-5..5)
        b = a + pick([-3, -2, -1, 1, 2, 3]) # a step of 0 never ends
        "[#{a}, #{b} .. #{@r.rand(-10..10)}] :: [Integer]"
      when DOUBLE then "[#{pick(%w[0.1 0 1.5 -1])}, #{pick(%w[0.2 0.5 1 2.5])} .. #{pick(%w[1.0 2 3.3 0.95])}] :: [Double]"
      when CHAR then "[#{pick(["'a'", "'x'", "'0'"])} .. #{pick(["'e'", "'z'", "'5'"])}]"
      when BOOL then '[False ..]'
      else "[#{leaf(e)}]"
      end
    end

    def pred(e)
      case e
      when INT, INTEGER then pick(['even', 'odd', '(> 2)', '(/= 0)'])
      when DOUBLE then pick(['(> 0.5)', '(< 0)', '(/= 1)'])
      when BOOL then pick(%w[id not])
      when CHAR then pick(['isAlpha', 'isDigit', 'isUpper', "(/= 'a')"])
      else '(const True)'
      end
    end

    def endo(e)
      case e
      when INT, INTEGER then pick(['(+ 1)', '(* 2)', 'negate', '(`div` 2)', 'abs', '(subtract 3)'])
      when DOUBLE then pick(['(/ 2)', '(* 1.5)', 'negate', '(+ 0.1)'])
      when BOOL then 'not'
      when CHAR then pick(%w[toUpper succ])
      else 'id'
      end
    end

    def maybe_expr(e, d)
      case @r.rand(6)
      when 0 then "Just #{sub(e, d)}"
      when 1 then "lookup #{sub(INT, d)} (zip [1 ..] #{sub(list_of(e), d)})"
      when 2 then "find #{pred(e)} #{sub(list_of(e), d)}"
      when 3 then "fmap #{endo(e)} #{sub([:maybe, e], d)}"
      when 4 then chance(0.5) ? "listToMaybe #{sub(list_of(e), d)}" : "M.lookup #{sub(INT, d)} #{sub([:map, INT, e], d)}"
      else "#{sub([:maybe, e], d)} >>= \\v -> if #{sub(BOOL, d)} then Just v else Nothing"
      end
    end

    def shape_expr(d)
      case @r.rand(4)
      when 0 then "Circle #{sub(DOUBLE, d)}"
      when 1 then "Rect #{sub(DOUBLE, d)} #{sub(DOUBLE, d)}"
      when 2 then "maximum [#{sub(SHAPE, d)}, #{sub(SHAPE, d)}]"
      else "fromMaybe Dot #{sub([:maybe, SHAPE], d)}"
      end
    end

    def rec_expr(d)
      case @r.rand(3)
      when 0 then "R { rx = #{expr(INT, d - 1)}, ry = #{expr([:maybe, INTEGER], d - 1)}, rs = #{expr(STRING, d - 1)} }"
      when 1 then "#{sub(REC, d)} { rx = #{expr(INT, d - 1)} }"
      else "#{sub(REC, d)} { rs = reverse (rs #{sub(REC, d)}) }"
      end
    end

    def map_expr(k, v, d)
      t = [:map, k, v]
      case @r.rand(11)
      when 0 then "M.insert #{sub(k, d)} #{sub(v, d)} #{sub(t, d)}"
      when 1 then "M.delete #{sub(k, d)} #{sub(t, d)}"
      when 2 then "M.fromList (zip #{sub([:list, k], d)} #{sub([:list, v], d)})"
      when 3 then "M.union #{sub(t, d)} #{sub(t, d)}"
      when 4 then "M.map #{endo(v)} #{sub(t, d)}"
      when 5 then "M.filter #{pred(v)} #{sub(t, d)}"
      when 6 then "M.adjust #{endo(v)} #{sub(k, d)} #{sub(t, d)}"
      when 7 then "M.alter (fmap #{endo(v)}) #{sub(k, d)} #{sub(t, d)}"
      when 8 then "M.insertWith const #{sub(k, d)} #{sub(v, d)} #{sub(t, d)}"
      when 9 then "M.difference #{sub(t, d)} #{sub(t, d)}"
      else "M.fromListWith const #{sub([:list, [:pair, k, v]], d)}"
      end
    end

    def set_expr(e, d)
      t = [:set, e]
      case @r.rand(7)
      when 0 then "S.insert #{sub(e, d)} #{sub(t, d)}"
      when 1 then "S.delete #{sub(e, d)} #{sub(t, d)}"
      when 2 then "S.fromList #{sub([:list, e], d)}"
      when 3 then "S.union #{sub(t, d)} #{sub(t, d)}"
      when 4 then "S.difference #{sub(t, d)} #{sub(t, d)}"
      when 5 then "S.intersection #{sub(t, d)} #{sub(t, d)}"
      else "S.filter #{pred(e)} #{sub(t, d)}"
      end
    end

    def pair_expr(a, b, d)
      if a == b && integral?(a) && chance(0.4)
        return "#{pick(%w[divMod quotRem])} #{sub(a, d)} #{sub(a, d)}"
      end
      if a.is_a?(Array) && b == a && a[0] == :list && chance(0.4)
        return "#{pick(%w[splitAt])} #{small_int} #{sub(a, d)}"
      end

      "(#{expr(a, d - 1)}, #{expr(b, d - 1)})"
    end
  end
end
