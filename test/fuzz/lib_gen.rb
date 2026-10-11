# frozen_string_literal: true

# Library breadth (test/fuzz/run.rb --library): the Data.List, Data.Map,
# Data.Set, Control.Monad, Data.Either, Data.Maybe, Data.Char and
# Data.Function names no other generator uses, each in a template whose
# holes get small random values -- and lists that sometimes hold a tagged
# `error`, so what each function forces is compared too (the strictness
# bugs found earlier were of that kind: isSuffixOf, unwords, Map keys).
module Fuzz
  class LibGen
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
      Fuzz::IMPORTS + ['import Control.Monad', 'import Data.Either', 'import Data.Function', 'import Data.Ord'] + Array.new(n) { probe }
    end

    TEMPLATES = [
      # Data.List
      'transpose [L, L, L]', 'inits L', 'tails L', 'subsequences (take 4 L)', 'permutations (take 3 L)',
      'unfoldr (\\x -> if x > N then Nothing else Just (x, x + 1)) N', 'intersperse N L', 'intercalate [N] [L, L]',
      'sortBy (comparing negate) L', 'sortOn negate L', 'insertBy (comparing negate) N L', 'deleteBy (\\a b -> a == b + 1) N L',
      'unionBy (\\a b -> a `mod` 3 == b `mod` 3) L L', 'intersectBy (\\a b -> a == b) L L', 'groupBy (\\a b -> even a == even b) L',
      'nubBy (\\a b -> a `mod` 2 == b `mod` 2) L', 'maximumBy (comparing negate) (N : L)', 'minimumBy (comparing abs) (N : L)',
      'zip3 L L S', 'zipWith3 (\\a b c -> a + b + c) L L L', 'unzip3 [(N, N, N), (N, N, N)]', 'lookup N (zip L S)',
      'elemIndex N L', 'elemIndices N L', 'findIndex P L', 'findIndices P L', 'find P L', 'partition P L', 'span P L',
      'break P L', 'dropWhileEnd P L', 'stripPrefix (take 2 L) L', 'isPrefixOf (take N L) L', 'isSuffixOf [N] L',
      'isInfixOf [N] L', 'isSubsequenceOf [N, N] L', 'splitAt N L', 'genericLength L :: Integer', 'genericTake N L',
      'genericDrop N L', 'genericReplicate N N', 'genericSplitAt N L', 'genericIndex (N : L) 0', 'foldl1 (-) (N : L)',
      'foldr1 (-) (N : L)', 'scanl1 (+) L', 'scanr (+) N L', 'scanr1 (+) L', 'iterate (* 2) N !! N', 'replicate N N',
      'lines S', 'unlines [S, S]', 'words S', 'unwords [S, S]', 'zip L (tail L)', 'and (map P L)', 'or (map P L)',
      'mapAccumL (\\a x -> (a + x, a * x)) N L', 'mapAccumR (\\a x -> (a + x, a * x)) N L', 'L \\\\ L', 'union L L',
      'intersect L L', 'insert N L', 'delete N L', 'group L', 'sort L', 'nub L', 'reverse L', 'last (N : L)', 'init (N : L)',
      'L !! N', 'lookup N []', 'zipWith (,) S L', 'concat [L, L]', 'concatMap (replicate 2) L', 'all P L', 'any P L',
      'foldl\' (+) N L', 'uncons L', 'singleton N', 'splitAt (-1) L', 'take (-1) L', 'cycle L !! N', 'sum L', 'product L',
      # Data.Maybe, Data.Either, Data.Function
      'catMaybes ML', 'mapMaybe (\\x -> if P x then Just x else Nothing) L', 'fromMaybe N (listToMaybe L)',
      'maybeToList (listToMaybe L)', 'fromJust (Just N)', 'isJust (find P L)', 'isNothing (find P L)', 'maybe N (+ 1) (find P L)',
      'lefts EL', 'rights EL', 'partitionEithers EL', 'either (+ 1) negate (head (EL ++ [Left N]))', 'isLeft (Left N)',
      'fromLeft N (Right N)', 'fromRight N (Left N)', '((+) `on` negate) N N', 'sortBy (compare `on` negate) L',
      'fix (\\f n -> if n <= 0 then 0 else n + f (n - 1)) N', '(& negate) N', 'L & reverse',
      # Control.Monad
      'foldM (\\a x -> if x > 5 then Nothing else Just (a + x)) N L', 'zipWithM (\\a b -> if a > b then Nothing else Just (a + b)) L L',
      'replicateM 2 [N, N]', 'filterM (const [True, False]) (take 2 L)', 'mapM (\\x -> [x, x + 1]) (take 2 L)', 'sequence [Just N, Just N]',
      'forM (take 2 L) (\\x -> Just x)', 'msum [Nothing, Just N, Just N]', 'mplus [N] [N]', 'guard (N > N) :: [()]', 'join [[N], L]',
      'liftM2 (+) (Just N) (Just N)', 'ap [(+ 1)] L', 'when (N > 2) Nothing', 'unless (N > 2) Nothing', 'void (Just N)',
      '(>=>) (\\x -> Just (x + 1)) (\\y -> Just (y * 2)) N', 'foldM_ (\\a x -> Just (a + x)) N L', 'zipWithM_ (\\a b -> Just ()) L L',
      'mzero :: [Int]', 'forever Nothing :: Maybe ()',
      # Data.Char
      'map digitToInt (filter isHexDigit S)', 'intToDigit N', 'map generalCategory S', 'map isPunctuation S', 'map isSymbol S',
      'map isSeparator S', 'map isAlphaNum S', 'map isOctDigit S', 'map isLetter S', 'map isMark S', 'map isNumber S',
      'map toTitle S', 'map isAscii S', 'map isLatin1 S', 'map isControl S', 'map isPrint S', 'subtract N (ord (head (S ++ "a")))',
      # Data.Map
      'M.foldrWithKey (\\k v acc -> k + v + acc) N M', 'M.foldlWithKey (\\acc k v -> acc - k + v) N M', 'M.mapWithKey (+) M',
      'M.filterWithKey (\\k _ -> P k) M', 'M.partition P M', 'M.partitionWithKey (\\k _ -> P k) M', 'M.mapMaybe (\\v -> if P v then Just v else Nothing) M',
      'M.split N M', 'M.splitLookup N M', 'M.lookupLT N M', 'M.lookupGE N M', 'M.lookupLE N M', 'M.lookupGT N M', 'M.findMin M',
      'M.deleteMin M', 'M.deleteMax M', 'M.minViewWithKey M', 'M.maxView M', 'M.elemAt 0 M', 'M.findIndex N M', 'M.take N M',
      'M.drop N M', 'M.unionsWith (+) [M, M]', 'M.unions [M, M]', 'M.keysSet M', 'M.restrictKeys M (S.fromList L)',
      'M.withoutKeys M (S.fromList L)', 'M.foldr (:) [] M', 'M.foldl (flip (:)) [] M', 'M.notMember N M', 'M.update (\\v -> if P v then Nothing else Just v) N M',
      'M.updateLookupWithKey (\\_ _ -> Nothing) N M', 'M.insertLookupWithKey (\\_ a b -> a + b) N N M', 'M.alter (const (Just N)) N M',
      'M.toAscList M', 'M.assocs M', 'M.null M', 'M.isSubmapOf M M', 'M.mapKeysWith (+) (`div` 2) M', 'M.filter P M',
      'M.foldr\' (+) N M', 'M.foldl\' (+) N M', 'fmap negate M', 'sum M', 'maximum (M.insert N N M)', 'traverse (\\v -> Just v) M',
      'M.singleton N N', 'M.fromSet negate (S.fromList L)', 'M.lookupIndex N M', 'M.spanAntitone (< N) M', 'M.takeWhileAntitone (< N) M',
      # Data.Set
      'S.partition P T', 'S.split N T', 'S.splitMember N T', 'S.elemAt 0 T', 'S.findIndex N T', 'S.lookupLT N T', 'S.lookupGE N T',
      'S.deleteMin T', 'S.deleteMax T', 'S.minView T', 'S.maxView T', 'S.unions [T, T]', 'S.difference T T', 'S.isSubsetOf T T',
      'S.disjoint T T', 'S.filter P T', 'S.foldr (:) [] T', 'S.toDescList T', 'S.take N T', 'S.drop N T', 'S.powerSet (S.take 3 T)',
      'S.cartesianProduct (S.take 2 T) (S.take 2 T)', 'S.map (`div` 2) T', 'S.notMember N T', 'sum T', 'S.lookupMax T', 'S.findMax T'
    ].freeze

    def num
      v = @r.rand(-2..9)
      v.negative? ? "(#{v})" : v.to_s
    end

    def bottom
      @tag += 1
      "(error \"e#{@tag}\")"
    end

    def elem
      @r.rand < 0.06 ? bottom : num
    end

    def list
      "[#{Array.new(@r.rand(0..5)) { elem }.join(', ')}]"
    end

    def str
      pick(['"a b"', '"Hello, World!"', '""', '"x1 f9\\tz"', '"line1\\nline2"', '"\\955 \\8364"', '"  a  "', '"ab;c"'])
    end

    def mp
      "(M.fromList [#{Array.new(@r.rand(0..4)) { "(#{num}, #{elem})" }.join(', ')}] :: M.Map Int Int)"
    end

    def st
      "(S.fromList #{list} :: S.Set Int)"
    end

    def pred
      pick(['even', 'odd', '(> 3)', '(< 0)', '(/= 2)'])
    end

    def probe
      # A placeholder is a lone capital not followed by `.` (M.size is not one).
      pick(TEMPLATES).gsub(/\bEL\b|\bML\b|\b[NLSMTP]\b(?!\.)/) do |m|
        case m
        when 'N' then num
        when 'L' then list
        when 'S' then str
        when 'M' then mp
        when 'T' then st
        when 'P' then pred
        when 'ML' then "[#{Array.new(@r.rand(0..4)) { @r.rand < 0.4 ? 'Nothing' : "Just #{num}" }.join(', ')}]"
        else "[#{Array.new(@r.rand(0..4)) { @r.rand < 0.5 ? "Left #{num}" : "Right #{num}" }.join(', ')}]"
        end
      end
    end
  end
end
