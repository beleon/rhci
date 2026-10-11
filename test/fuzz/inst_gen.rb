# frozen_string_literal: true

# Hand-written instances of the Prelude's classes (test/fuzz/run.rb
# --instances): each section declares a few types and writes their
# instances by hand, choosing at random which minimal definition to give
# (Show by show or by showsPrec, Eq by == or /=, Ord by compare or <=,
# Foldable by foldMap or foldr, Num with or without negate, ...) and
# leaving some classes out; probes then lean on the default methods and
# superclass dictionaries: ranges through a user Enum, sum and literals
# through a user Num, maximum and sort through a user Ord, Foldable and
# Traversable methods on a user tree, Semigroup/Monoid folds.
module Fuzz
  class InstGen
    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    def block(lines)
      ":{\n#{lines.join("\n")}\n:}"
    end

    def section(n)
      out = Fuzz::IMPORTS + ['data V = V Int Int', 'newtype N = N Int',
                             'data Tree a = Leaf | Node (Tree a) a (Tree a)', 'data Pair a = Pair a a']
      out << block(pick([
        ['instance Show V where', '  show (V a b) = "<" ++ show a ++ "," ++ show b ++ ">"'],
        ['instance Show V where', '  showsPrec d (V a b) = showParen (d > 10) (showString "V " . showsPrec 11 a . showChar \' \' . showsPrec 11 b)'],
        ['instance Show V where', '  showsPrec d (V a b) = showParen (d > 6) (shows a . showString " :/ " . shows b)']
      ]))
      out << block(pick([['instance Show N where', '  show (N n) = "N" ++ show n'],
                         ['instance Show N where', '  showsPrec d (N n) = showParen (d >= 11) (showString "N " . showsPrec 11 n)']]))
      out << block(pick([['instance Eq V where', '  V a b == V c d = a == c && b == d'],
                         ['instance Eq V where', '  V a b /= V c d = a /= c || b /= d']]))
      out << block(pick([['instance Ord V where', '  compare (V a b) (V c d) = compare (a + b) (c + d)'],
                         ['instance Ord V where', '  V a b <= V c d = (a, b) <= (c, d)']]))
      out << block(['instance Eq N where', '  N a == N b = a == b']) if chance(0.9)
      out << block(['instance Ord N where', '  compare (N a) (N b) = compare a b']) if chance(0.8)
      if chance(0.85)
        neg = chance(0.5) ? ['  negate (N a) = N (negate a)'] : ['  N a - N b = N (a - b)']
        out << block(['instance Num N where', '  N a + N b = N (a + b)', '  N a * N b = N (a * b)', '  abs (N a) = N (abs a)',
                      '  signum (N a) = N (signum a)', '  fromInteger n = N (fromInteger n)'] + neg)
      end
      out << block(['instance Enum N where', '  toEnum = N', '  fromEnum (N n) = n']) if chance(0.8)
      out << block(['instance Bounded V where', '  minBound = V 0 0', '  maxBound = V 9 9']) if chance(0.6)
      if chance(0.8)
        out << block(['instance Semigroup N where', '  N a <> N b = N (a + b)'])
        out << block(['instance Monoid N where', '  mempty = N 0']) if chance(0.8)
      end
      out << block(['instance Show a => Show (Tree a) where',
                    pick(['  show Leaf = "."', '  showsPrec _ Leaf = showString "."']),
                    pick(['  show (Node l x r) = "(" ++ show l ++ " " ++ show x ++ " " ++ show r ++ ")"',
                          '  showsPrec d (Node l x r) = showParen (d > 10) (showsPrec 11 l . showChar \' \' . showsPrec 11 x . showChar \' \' . showsPrec 11 r)'])])
      out << block(['instance Functor Tree where', '  fmap _ Leaf = Leaf', '  fmap f (Node l x r) = Node (fmap f l) (f x) (fmap f r)'])
      out << block(pick([['instance Foldable Tree where', '  foldMap _ Leaf = mempty', '  foldMap f (Node l x r) = foldMap f l <> f x <> foldMap f r'],
                         ['instance Foldable Tree where', '  foldr _ z Leaf = z', '  foldr f z (Node l x r) = foldr f (f x (foldr f z r)) l']]))
      if chance(0.7)
        out << block(['instance Traversable Tree where', '  traverse _ Leaf = pure Leaf',
                      '  traverse f (Node l x r) = Node <$> traverse f l <*> f x <*> traverse f r'])
      end
      out << block(['instance Functor Pair where', '  fmap f (Pair a b) = Pair (f a) (f b)'])
      out << block(['instance Applicative Pair where', '  pure a = Pair a a', '  Pair f g <*> Pair a b = Pair (f a) (g b)']) if chance(0.7)
      out << block(['instance Show a => Show (Pair a) where', '  show (Pair a b) = "P " ++ show a ++ " " ++ show b'])
      out + Array.new(n) { probe }
    end

    def num
      pick(%w[0 1 2 3 -1 7])
    end

    def v
      a = num
      b = num
      "(V #{a.start_with?('-') ? "(#{a})" : a} #{b.start_with?('-') ? "(#{b})" : b})"
    end

    def nv
      n = num
      "(N #{n.start_with?('-') ? "(#{n})" : n})"
    end

    def tree(d = 2)
      return 'Leaf' if d.zero? || chance(0.3)

      "(Node #{tree(d - 1)} #{num.start_with?('-') ? "(#{num})" : num} #{tree(d - 1)})"
    end

    def probe
      case @r.rand(30)
      when 0 then v
      when 1 then "showsPrec #{pick([0, 7, 11])} #{v} \"\""
      when 2 then "[#{v}, #{v}]"
      when 3 then "Just #{v}"
      when 4 then "#{v} == #{v}"
      when 5 then "#{v} /= #{v}"
      when 6 then "compare #{v} #{v}"
      when 7 then "(#{v} < #{v}, #{v} >= #{v}, max #{v} #{v})"
      when 8 then "sort [#{v}, #{v}, #{v}]"
      when 9 then "maximum [#{v}, #{v}]"
      when 10 then "[minBound .. maxBound :: V]"
      when 11 then "(minBound :: V, maxBound :: V)"
      when 12 then "#{nv} + #{nv} * 3"
      when 13 then "sum [#{nv}, #{nv}, #{nv}]"
      when 14 then "#{nv} - #{nv}"
      when 15 then "negate #{nv}"
      when 16 then "(#{num} :: N)"
      when 17 then "[#{nv} .. #{nv}]"
      when 18 then "take 4 [#{nv}, #{nv} ..]"
      when 19 then "(succ #{nv}, pred #{nv})"
      when 20 then "mconcat [#{nv}, #{nv}]"
      when 21 then "foldMap (\\x -> N x) #{tree}"
      when 22 then "#{pick(%w[sum length maximum minimum product null])} #{tree}"
      when 23 then "(foldr (:) [] #{tree}, foldl (flip (:)) [] #{tree}, elem #{num} #{tree})"
      when 24 then "fmap (* 2) #{tree}"
      when 25 then "traverse (\\x -> if x > #{num} then Just x else Nothing) #{tree}"
      when 26 then "sequenceA (fmap Just #{tree})"
      when 27 then "(+) <$> Pair 1 2 <*> Pair 10 20"
      when 28 then "pure 3 :: Pair Int"
      else "#{tree}"
      end
    end
  end
end
