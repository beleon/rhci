# frozen_string_literal: true

# Tokens and lexing (test/fuzz/run.rb --tokens): short inputs built around
# the places where a lexer and GHC's can part -- operators made of comment
# and arrow characters (`-->`, `+--`, `|--`), `..` after a constructor
# (`[LT..]` is a qualified name), negation against sections and
# subtraction, backtick sections, dots between names (`Just.id`), primes
# and underscores, Unicode identifiers and operators, every numeric literal
# form, Char and String escapes and gaps, nested and unterminated comments,
# qualified operators, one-line layout, tuple sections, keywords of
# extensions used as names. Half are respaced at random (spaces dropped or
# doubled outside literals): `x - 1` becomes `x-1`, `[1 .. 3]` `[1..3]`.
module Fuzz
  class LexGen
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
      Fuzz::IMPORTS + Array.new(n) { probe }
    end

    def num
      pick(%w[0 1 2 3 7 10 42])
    end

    TEMPLATES = [
      # operators made of comment and arrow characters
      'let (-->) a b = a + b in N --> N', 'let (|--) a b = a in N |-- N', 'let (+--) a b = a * b in N +-- N',
      'N + N -- comment', 'N +-- N', 'let x --> y = x - y in N --> N', 'let (<--) = (-) in N <-- N',
      'let (-|) = max in N -| N', 'let (.--.) a b = a in N .--. N', 'N --| N', 'N -- | N', 'N ---> N',
      'let (~~) = (+) in N ~~ N', 'let (!) = (*) in N ! N', 'let (#) = (+) in N # N', 'let (@@) = (-) in N @@ N',
      # ranges and dots
      '[N .. N]', '[N..N]', '[LT ..]', '[LT..]', '[False ..]', '[False ..True]', "['a' .. 'e']", '[1.0, 1.5 .. 3]',
      '[N, N .. N]', 'take 3 [N ..]', '[x .. y] where x = 1', 'let x = N; y = N in [x..y]', 'Just . id $ N',
      'Just.id $ N', '(show.length) [N]', 'show . length $ [N]', 'let f = id.id in f N', '(.) id id N',
      'Prelude.map (+N) [N]', '(Prelude.+) N N', 'N Prelude.+ N', 'Data.List.sort [N, N]', "Data.Char.ord 'a'",
      'M.size M.empty', 'Data.Map.empty', 'Prelude..', 'map (Prelude.. id) []', '[minBound .. maxBound :: Bool]',
      # negation, subtraction, sections
      'map (subtract N) [N, N]', 'map (- N) [N]', '(- N) N', 'negate N ^ 2', '- N ^ 2', '(-N) ^ 2', 'N - -N',
      'N - (-N)', 'abs -N', 'abs (-N)', 'let f x = x in f -N', 'let x = N in x-N', 'let x = N in x -N',
      'let x = N in x- N', '(subtract N) N', '(\\x -> -x) N', '(+ (-N)) N', '(+ -N) N', '- - N', '(-) N N',
      'let f (-1) = True; f _ = False in f (-1)', 'N `div` -N', '-N `div` N', '-N `mod` N', 'negate -N',
      # backticks
      '(`div` N) N', '(N `div`) N', "(`elem` [N, N]) N", 'N `max` N `max` N', 'let f `op` g = f + g in N `op` N',
      'N`div`N', '(`subtract` N) N', 'let a `plus` b = a + b; infixl 6 `plus` in N `plus` N * N',
      # names
      "let x' = N; x'' = x' + N in x''", 'let _x = N in _x', 'let a_b = N in a_b', "let x'y = N in x'y",
      'let λ = N in λ', 'let (∘) f g x = f (g x) in ((+N) ∘ (*N)) N', 'let ñ = N in ñ', 'let x₁ = N in x₁',
      'let as = N in as', 'let qualified = N in qualified', 'let hiding = N in hiding', 'let forall = N in forall',
      'let family = N in family', 'let role = N in role', 'let pattern = N in pattern', 'let mdo = N in mdo',
      'let proc = N in proc', 'let rec = N in rec', 'let stock = N in stock', 'let anyclass = N in anyclass',
      'let via = N in via', 'let javascript = N in javascript', 'let capi = N in capi', 'let ccall = N in ccall',
      'let label = N in label', 'let dynamic = N in dynamic', "let a' = N in a' + a'", "'a'", "x' where x' = N",
      # numeric literals
      '0x1F', '0X1f', '0o17', '0O17', '0b101', '0B11', '1_000', '1_000.5', '0x_ff', '1e3', '1E3', '1e3 :: Int',
      '1.5e-2', '1.0e+3', '0x1.8p1', '007', '.5', '5.', '2e', '1e', '0x', '0o8', '0xg', '12e-1 :: Double',
      '1e400', '1e-400', '0.1 + 0.2', '1__0', '1_', '_1', '1e1_0', '0b', '0b102', '9223372036854775808 :: Int',
      '(-9223372036854775808) :: Int', '-9223372036854775808 :: Int',
      # characters and strings
      "'\\''", "'\"'", '"\\""', "'\\x41'", "'\\o101'", "'\\65'", '"\\SOH"', '"\\SO\\&H"', '"\\SO" ++ "H"',
      '"a\\   \\b"', '"{- not a comment -}"', '"-- not a comment"', "'\\^A'", "'\\DEL'",
      '"\\1234\\&5"', "'\\1114111'", "'\\1114112'", "'\\x110000'", "''", "'ab'", '"\\q"', '"\\&"', "'\\&'",
      '"tab\\there"', "'\\t'", '"\\^@"', "'\\NUL'", '"\\ESC[0m"', '"a" "b"', "'a''b'", 'length "\\SOH"',
      # comments
      'N {- c -} + N', 'N {- {- nested -} -} + N', '{--} N', 'N + {- unterminated', 'N {-- c --} + N',
      'let x = N in x--N', 'N + N {- -} -- end', '{-# INLINE f #-} N', 'N {- -} {- -} + N', 'N + N -}',
      # layout and syntax on one line
      '\\x -> x', '(\\x->x+N) N', '(\\ x y -> x) N N', "case N of { 1 -> 'a'; _ -> 'b' }",
      "case N of 1 -> 'a'; _ -> 'b'", 'if True then N else N', 'let { a = N; b = N } in a + b',
      'let a = N; b = N in a + b', 'do { x <- Just N; return x }', 'do x <- Just N; return x',
      '[x | x <- [1..N], odd x, let y = x * 2, y > 2]', '[(x,y) | x <- [N,N], y <- "ab"]', '(,N) N', '(N,) N',
      '(,) N N', '(,,) N N N', '( )', '[ ]', '(,) N', 'let f xs@(x:_) = x in f [N]', 'let f ~(a,b) = N in f undefined',
      'let f !x = N in f undefined', '_', '_foo + N', 'let { } in N', 'case N of {}', 'if N > 0 then N else N :: Int',
      '\\case 1 -> N', 'N :: Int :: Int', '(N :: Int) :: Integer', "let f = \\x -> x in f 'c'",
      'let (a, b) = (N, N) in a', 'let [a, b] = [N, N] in b', 'let Just c = Just N in c'
    ].freeze

    def probe
      t = pick(TEMPLATES).gsub('N') { num }
      chance(0.5) ? respace(t) : t
    end

    # Spaces dropped or doubled, and added after `(` or before `)`,
    # outside literals and comments.
    def respace(s)
      out = +''
      i = 0
      while i < s.length
        c = s[i]
        if c == '"' || (c == "'" && (i.zero? || s[i - 1] !~ /[A-Za-z0-9_']/))
          j = i + 1
          j += (s[j] == '\\' ? 2 : 1) while j < s.length && s[j] != c
          out << s[i..j]
          i = j + 1
          next
        end
        if c == ' '
          r = @r.rand
          out << (r < 0.15 ? '' : r < 0.3 ? '  ' : ' ')
        else
          out << c
          out << ' ' if '(['.include?(c) && chance(0.1)
        end
        i += 1
      end
      out
    end
  end
end
