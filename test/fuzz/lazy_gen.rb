# frozen_string_literal: true

# Laziness and strictness (test/fuzz/run.rb --laziness): infinite and
# self-referential structures (always cut by take, !!, takeWhile, head),
# knot-tying through tuples and fix, lazy (~) against strict patterns,
# pattern bindings that fail only when used, unused bindings that would
# fail, seq / $! / foldl' / bang patterns, strict fields, newtype patterns
# (which force nothing) against data patterns, and output printed before
# an exception. B is a tagged `error`: when both sides raise, the same tag
# must come out (the same thing was forced first).
module Fuzz
  class LazyGen
    DECLS = ['data S = S !Int Int deriving Show', 'newtype NT = NT Int deriving Show', 'data D = D Int deriving Show',
             'data P = P { pa :: Int, pb :: !Int } deriving Show'].freeze

    def initialize(seed)
      @r = Random.new(seed)
      @tag = 0
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    def section(n)
      Fuzz::IMPORTS + ['import Data.Function (fix)'] + DECLS + Array.new(n) { probe }
    end

    TEMPLATES = [
      # infinite and self-referential
      'take N (cycle [N, B])', 'take N (iterate (*2) N)', 'let xs = N : map (*2) xs in take N xs',
      'let fibs = 0 : 1 : zipWith (+) fibs (tail fibs) in fibs !! N', 'takeWhile (< N) [1 ..]', 'zip [1 ..] "abc"',
      'let ones = 1 : ones in take N ones', 'head (filter (> N) [1 ..])', 'let xs = [N ..] in xs !! N',
      'take N (repeat B)', 'length (take N (repeat B))', 'take N (cycle [B])', 'take N [N, B ..]',
      'let xs = B : xs in length (take N xs)', 'take N (map (* 2) [N ..])', 'takeWhile (/= N) (cycle [N, N, B])',
      'let xs = 1 : map (+ 1) xs in xs !! N', 'take N (scanl (+) 0 [1 ..])', 'fst (span (< N) [1 ..])',
      'take N (concat (repeat [N, B]))', 'let (evens, odds) = (0 : map (+ 1) odds, map (+ 1) evens) in take N evens',
      # knot-tying
      'let (a, b) = (N, a + 1) in b', 'let xs = map (+ 1) (N : xs) in take N xs',
      'fix (\\f n -> if n == 0 then 1 else n * f (n - 1)) N', 'let (a, b) = (b + 1, N) in a',
      'fst (fix (\\p -> (N, fst p)))', 'take N (fix (N :))', 'let f = \\n -> if n <= 0 then [] else n : f (n - 1) in f N',
      # lazy and strict patterns
      'let f ~(a, b) = N in f B', 'let f (a, b) = N in f B', 'case B of ~(a, b) -> N', 'case B of (a, b) -> N',
      'let (a, b) = B in N', 'let (a, b) = B in a', 'let Just x = Nothing in N', 'let Just x = Nothing in x',
      '(\\ ~(x:_) -> N) []', '(\\(x:_) -> N) []', 'let [a, b] = [N] in N', 'let [a, b] = [N] in a',
      'case B of NT _ -> N', 'case B of D _ -> N', 'case NT B of NT _ -> N', 'case D B of D _ -> N',
      'let f (NT _) = N in f B', 'let f (D _) = N in f B', 'let f ~(D _) = N in f B',
      # unused or partly used
      'let x = B in N', 'let y = B; z = N in z', 'fst (N, B)', 'snd (B, N)', 'const N B', 'length [B, B]',
      'null (B : B)', 'take 0 B', 'take N (N : B)', '[N, B] !! 0', 'map (const N) [B, B]', 'zipWith const [N, N] [B]',
      'and [False, B]', 'or [True, B]', 'B && False', 'False && B', 'all even [N, N, B]', 'any odd [N, B]',
      'elem N [N, B]', 'lookup N [(N, N), B]', 'maybe N (const N) (Just B)', 'either (const N) id (Left B)',
      'fromMaybe N (Just B)', 'length (zip [B, B] [N])', 'fst (unzip [(N, B)])', 'words (show N ++ B)',
      # strictness
      'seq B N', 'B `seq` N', 'seq (N, B) N', 'seq [B] N', 'seq (B :: Int) N', 'const N $! B', 'const N $! (N, B)',
      "foldl' (+) 0 [N, B]", 'foldr (\\x _ -> x) N [N, B]', 'foldl (\\_ x -> x) N [B, N]',
      'length (foldl (flip (:)) [] [B, B])', 'sum [N, B]', 'maximum [B]', 'let !x = B in N', 'let f !x = N in f B',
      '(\\ !x -> N) B', 'case B of _ -> N', 'case B of x -> N', 'case (B :: Bool) of { True -> N; False -> N }',
      'seq (Just B) N', 'seq (\\x -> B) N', 'seq (B :: Int -> Int) N', 'id $! N', 'seq (S N B) N', 'seq (S B N) N',
      'case S N B of S a _ -> a', 'case S B N of S _ b -> b', 'let s = S B N in N', 'pa (P N B)', 'pb (P B N)',
      'seq (P B N) N', 'seq (P N B) N', "foldl' (flip (:)) [] [B, N]", 'seq (foldr (+) 0 [N, B]) N',
      'length (show (S N B))', 'seq (NT B) N', 'seq (D B) N',
      # output before an exception
      '[N, N, B]', '(N, B)', 'Just B', 'show (take N (cycle [N, B]))', 'take N (show [N, B])', '"ab" ++ B',
      '[1 .. N] ++ B', "replicate N 'x' ++ B", 'S N B', 'S B N', 'P N B', 'P B N', 'D B', 'NT B', '[S N N, B]',
      'map (`div` N) [N, 0, N]', 'zip [N, N] [N, B]', 'concat [[N], B, [N]]'
    ].freeze

    def bottom
      @tag += 1
      "(error \"e#{@tag}\")"
    end

    def num
      pick(%w[0 1 2 3 5 7])
    end

    def probe
      t = pick(TEMPLATES).gsub(/\bN\b/) { num }.gsub(/\bB\b/) { bottom }
      return t unless chance(0.2)

      # Used once more, inside another lazy context.
      pick(["fst (#{t}, #{bottom})", "length [#{t}, #{bottom}]", "const (#{t}) #{bottom}", "seq (#{t}) #{num}",
            "case #{t} of _ -> #{num}", "let y = #{t} in #{num}"])
    end
  end
end
