-- Data.Set, ported from containers-0.6.7 (Data.Set.Internal), the version
-- GHC 9.6 ships: the same weight-balanced trees and algorithms, so every
-- observable behaviour (results, laziness, errors) is containers'. GHC-only
-- optimisations (pointer equality, unboxed pairs, rewrite rules) are left
-- out: they never change a result. Bang patterns are written with seq.
module Data.Set.Internal where

import Prelude hiding (filter, foldl, foldr, null, map, take, drop, splitAt)
import qualified Data.List as List
import qualified Data.Foldable as Foldable

infixl 9 \\

data Set a = Bin !Int !a !(Set a) !(Set a) | Tip

(\\) :: Ord a => Set a -> Set a -> Set a
m1 \\ m2 = difference m1 m2

-- ---- instances ---------------------------------------------------------------------

instance Ord a => Semigroup (Set a) where
  (<>) = union

instance Ord a => Monoid (Set a) where
  mempty = empty
  mconcat = unions

instance Foldable Set where
  foldMap f t = go t
    where
      go Tip = mempty
      go (Bin 1 k _ _) = f k
      go (Bin _ k l r) = go l `mappend` (f k `mappend` go r)
  foldr = foldr
  foldl = foldl
  foldr' = foldr'
  foldl' = foldl'
  toList = toList
  null = null
  length = size
  elem = go
    where
      go !x Tip = False
      go x (Bin _ y l r) = x == y || go x l || go x r
  minimum = findMin
  maximum = findMax
  sum = foldl' (+) 0
  product = foldl' (*) 1

instance Eq a => Eq (Set a) where
  t1 == t2 = (size t1 == size t2) && (toAscList t1 == toAscList t2)

instance Ord a => Ord (Set a) where
  compare s1 s2 = compare (toAscList s1) (toAscList s2)

instance Show a => Show (Set a) where
  showsPrec p xs = showParen (p > 10) $ showString "fromList " . shows (toList xs)

instance (Read a, Ord a) => Read (Set a) where
  readPrec = parens $ prec 10 $ do
    Ident "fromList" <- lexP
    xs <- readPrec
    return (fromList xs)
  readListPrec = readListPrecDefault

-- ---- query -------------------------------------------------------------------------

null :: Set a -> Bool
null Tip = True
null (Bin _ _ _ _) = False

size :: Set a -> Int
size Tip = 0
size (Bin sz _ _ _) = sz

member :: Ord a => a -> Set a -> Bool
member = go
  where
    go !x Tip = False
    go x (Bin _ y l r) = case compare x y of
      LT -> go x l
      GT -> go x r
      EQ -> True

notMember :: Ord a => a -> Set a -> Bool
notMember a t = not $ member a t

lookupLT :: Ord a => a -> Set a -> Maybe a
lookupLT = goNothing
  where
    goNothing !x Tip = Nothing
    goNothing x (Bin _ y l r) | x <= y = goNothing x l
                              | otherwise = goJust x y r
    goJust !x best Tip = Just best
    goJust x best (Bin _ y l r) | x <= y = goJust x best l
                                | otherwise = goJust x y r

lookupGT :: Ord a => a -> Set a -> Maybe a
lookupGT = goNothing
  where
    goNothing !x Tip = Nothing
    goNothing x (Bin _ y l r) | x < y = goJust x y l
                              | otherwise = goNothing x r
    goJust !x best Tip = Just best
    goJust x best (Bin _ y l r) | x < y = goJust x y l
                                | otherwise = goJust x best r

lookupLE :: Ord a => a -> Set a -> Maybe a
lookupLE = goNothing
  where
    goNothing !x Tip = Nothing
    goNothing x (Bin _ y l r) = case compare x y of
      LT -> goNothing x l
      EQ -> Just y
      GT -> goJust x y r
    goJust !x best Tip = Just best
    goJust x best (Bin _ y l r) = case compare x y of
      LT -> goJust x best l
      EQ -> Just y
      GT -> goJust x y r

lookupGE :: Ord a => a -> Set a -> Maybe a
lookupGE = goNothing
  where
    goNothing !x Tip = Nothing
    goNothing x (Bin _ y l r) = case compare x y of
      LT -> goJust x y l
      EQ -> Just y
      GT -> goNothing x r
    goJust !x best Tip = Just best
    goJust x best (Bin _ y l r) = case compare x y of
      LT -> goJust x y l
      EQ -> Just y
      GT -> goJust x best r

-- ---- construction ------------------------------------------------------------------

empty :: Set a
empty = Tip

singleton :: a -> Set a
singleton x = Bin 1 x Tip Tip

insert :: Ord a => a -> Set a -> Set a
insert x0 = go x0 x0
  where
    go orig !x Tip = singleton orig
    go orig !x (Bin sz y l r) = case compare x y of
      LT -> balanceL y (go orig x l) r
      GT -> balanceR y l (go orig x r)
      EQ -> Bin sz orig l r

-- Insert, keeping the element already there (union's right argument).
insertR :: Ord a => a -> Set a -> Set a
insertR x0 = go x0 x0
  where
    go orig !x Tip = singleton orig
    go orig !x t@(Bin _ y l r) = case compare x y of
      LT -> balanceL y (go orig x l) r
      GT -> balanceR y l (go orig x r)
      EQ -> t

delete :: Ord a => a -> Set a -> Set a
delete = go
  where
    go !x Tip = Tip
    go x (Bin _ y l r) = case compare x y of
      LT -> balanceR y (go x l) r
      GT -> balanceL y l (go x r)
      EQ -> glue l r

alterF :: (Ord a, Functor f) => (Bool -> f Bool) -> a -> Set a -> f (Set a)
alterF f k s = fmap choose (f member_)
  where
    (member_, inserted, deleted) = case alteredSet k s of
      Deleted d -> (True, s, d)
      Inserted i -> (False, i, s)
    choose True = inserted
    choose False = deleted

data AlteredSet a = Deleted !(Set a) | Inserted !(Set a)

alteredSet :: Ord a => a -> Set a -> AlteredSet a
alteredSet x0 s0 = go x0 s0
  where
    go x Tip = Inserted (singleton x)
    go x (Bin _ y l r) = case compare x y of
      LT -> case go x l of
        Deleted d -> Deleted (balanceR y d r)
        Inserted i -> Inserted (balanceL y i r)
      GT -> case go x r of
        Deleted d -> Deleted (balanceL y l d)
        Inserted i -> Inserted (balanceR y l i)
      EQ -> Deleted (glue l r)

-- ---- subsets -----------------------------------------------------------------------

isProperSubsetOf :: Ord a => Set a -> Set a -> Bool
isProperSubsetOf s1 s2 = size s1 < size s2 && isSubsetOfX s1 s2

isSubsetOf :: Ord a => Set a -> Set a -> Bool
isSubsetOf t1 t2 = size t1 <= size t2 && isSubsetOfX t1 t2

isSubsetOfX :: Ord a => Set a -> Set a -> Bool
isSubsetOfX Tip _ = True
isSubsetOfX _ Tip = False
isSubsetOfX (Bin 1 x _ _) t = member x t
isSubsetOfX (Bin _ x l r) t =
  found && size l <= size lt && size r <= size gt && isSubsetOfX l lt && isSubsetOfX r gt
  where (lt, found, gt) = splitMember x t

disjoint :: Ord a => Set a -> Set a -> Bool
disjoint Tip _ = True
disjoint _ Tip = True
disjoint (Bin 1 x _ _) t = x `notMember` t
disjoint (Bin _ x l r) t = not found && disjoint l lt && disjoint r gt
  where (lt, found, gt) = splitMember x t

-- ---- minimum and maximum -----------------------------------------------------------

lookupMinSure :: a -> Set a -> a
lookupMinSure x Tip = x
lookupMinSure _ (Bin _ x l _) = lookupMinSure x l

lookupMin :: Set a -> Maybe a
lookupMin Tip = Nothing
lookupMin (Bin _ x l _) = Just $! lookupMinSure x l

findMin :: Set a -> a
findMin t = case lookupMin t of
  Just r -> r
  Nothing -> error "Set.findMin: empty set has no minimal element"

lookupMaxSure :: a -> Set a -> a
lookupMaxSure x Tip = x
lookupMaxSure _ (Bin _ x _ r) = lookupMaxSure x r

lookupMax :: Set a -> Maybe a
lookupMax Tip = Nothing
lookupMax (Bin _ x _ r) = Just $! lookupMaxSure x r

findMax :: Set a -> a
findMax t = case lookupMax t of
  Just r -> r
  Nothing -> error "Set.findMax: empty set has no maximal element"

deleteMin :: Set a -> Set a
deleteMin (Bin _ _ Tip r) = r
deleteMin (Bin _ x l r) = balanceR x (deleteMin l) r
deleteMin Tip = Tip

deleteMax :: Set a -> Set a
deleteMax (Bin _ _ l Tip) = l
deleteMax (Bin _ x l r) = balanceL x l (deleteMax r)
deleteMax Tip = Tip

-- ---- union, difference, intersection -------------------------------------------------

unions :: (Foldable f, Ord a) => f (Set a) -> Set a
unions = Foldable.foldl' union empty

union :: Ord a => Set a -> Set a -> Set a
union t1 Tip = t1
union t1 (Bin 1 x _ _) = insertR x t1
union (Bin 1 x _ _) t2 = insert x t2
union Tip t2 = t2
union (Bin _ x l1 r1) t2 = case splitS x t2 of
  (l2, r2) -> let l1l2 = union l1 l2
                  r1r2 = union r1 r2
              in l1l2 `seq` r1r2 `seq` link x l1l2 r1r2

difference :: Ord a => Set a -> Set a -> Set a
difference Tip _ = Tip
difference t1 Tip = t1
difference t1 (Bin _ x l2 r2) = case split x t1 of
  (l1, r1) -> let l1l2 = difference l1 l2
                  r1r2 = difference r1 r2
              in l1l2 `seq` r1r2 `seq` merge l1l2 r1r2

intersection :: Ord a => Set a -> Set a -> Set a
intersection Tip _ = Tip
intersection _ Tip = Tip
intersection (Bin _ x l1 r1) t2 = case splitMember x t2 of
  (l2, b, r2) -> let l1l2 = intersection l1 l2
                     r1r2 = intersection r1 r2
                 in l1l2 `seq` r1r2 `seq` (if b then link x l1l2 r1r2 else merge l1l2 r1r2)

-- ---- filter, partition, map ------------------------------------------------------------

filter :: (a -> Bool) -> Set a -> Set a
filter _ Tip = Tip
filter p (Bin _ x l r) =
  let l' = filter p l
      r' = filter p r
  in l' `seq` r' `seq` (if p x then link x l' r' else merge l' r')

partition :: (a -> Bool) -> Set a -> (Set a, Set a)
partition p0 t0 = go p0 t0
  where
    go _ Tip = (Tip, Tip)
    go p (Bin _ x l r) = case go p l of
      (l1, l2) -> case go p r of
        (r1, r2)
          | p x -> let a = link x l1 r1
                       b = merge l2 r2
                   in a `seq` b `seq` (a, b)
          | otherwise -> let a = merge l1 r1
                             b = link x l2 r2
                         in a `seq` b `seq` (a, b)

map :: Ord b => (a -> b) -> Set a -> Set b
map f = fromList . List.map f . toList

mapMonotonic :: (a -> b) -> Set a -> Set b
mapMonotonic _ Tip = Tip
mapMonotonic f (Bin sz x l r) = Bin sz (f x) (mapMonotonic f l) (mapMonotonic f r)

-- ---- folds -------------------------------------------------------------------------

fold :: (a -> b -> b) -> b -> Set a -> b
fold = foldr

foldr :: (a -> b -> b) -> b -> Set a -> b
foldr f z = go z
  where
    go z' Tip = z'
    go z' (Bin _ x l r) = go (f x (go z' r)) l

foldr' :: (a -> b -> b) -> b -> Set a -> b
foldr' f z = go z
  where
    go !z' Tip = z'
    go !z' (Bin _ x l r) = go (f x $! go z' r) l

foldl :: (a -> b -> a) -> a -> Set b -> a
foldl f z = go z
  where
    go z' Tip = z'
    go z' (Bin _ x l r) = go (f (go z' l) x) r

foldl' :: (a -> b -> a) -> a -> Set b -> a
foldl' f z = go z
  where
    go !z' Tip = z'
    go !z' (Bin _ x l r) = (let z'' = go z' l in z'' `seq` go (f z'' x) r)

-- ---- lists -------------------------------------------------------------------------

elems :: Set a -> [a]
elems = toAscList

toList :: Set a -> [a]
toList = toAscList

toAscList :: Set a -> [a]
toAscList = foldr (:) []

toDescList :: Set a -> [a]
toDescList = foldl (flip (:)) []

fromList :: Ord a => [a] -> Set a
fromList [] = Tip
fromList [x] = Bin 1 x Tip Tip
fromList (x0 : xs0)
  | not_ordered x0 xs0 = fromList' (Bin 1 x0 Tip Tip) xs0
  | otherwise = go (1 :: Int) (Bin 1 x0 Tip Tip) xs0
  where
    not_ordered _ [] = False
    not_ordered x (y : _) = x >= y
    fromList' t0 xs = Foldable.foldl' ins t0 xs
      where ins t x = insert x t
    go !s t [] = t
    go _ t [x] = insertMax x t
    go s l xs@(x : xss)
      | not_ordered x xss = fromList' l xs
      | otherwise = case create s xss of
          (r, ys, []) -> go (s * 2) (link x l r) ys
          (r, _, ys) -> fromList' (link x l r) ys
    create !s [] = (Tip, [], [])
    create s xs@(x : xss)
      | s == 1 = if not_ordered x xss then (Bin 1 x Tip Tip, [], xss) else (Bin 1 x Tip Tip, xss, [])
      | otherwise = case create (s `div` 2) xs of
          res@(_, [], _) -> res
          (l, [y], zs) -> (insertMax y l, [], zs)
          (l, ys@(y : yss), _)
            | not_ordered y yss -> (l, [], ys)
            | otherwise -> case create (s `div` 2) yss of
                (r, zs, ws) -> (link y l r, zs, ws)

fromAscList :: Eq a => [a] -> Set a
fromAscList xs = fromDistinctAscList (combineEq xs)

fromDescList :: Eq a => [a] -> Set a
fromDescList xs = fromDistinctDescList (combineEq xs)

combineEq :: Eq a => [a] -> [a]
combineEq [] = []
combineEq (x : xs) = combineEq' x xs
  where
    combineEq' z [] = [z]
    combineEq' z (y : ys)
      | z == y = combineEq' z ys
      | otherwise = z : combineEq' y ys

fromDistinctAscList :: [a] -> Set a
fromDistinctAscList [] = Tip
fromDistinctAscList (x0 : xs0) = go (1 :: Int) (Bin 1 x0 Tip Tip) xs0
  where
    go !s t [] = t
    go s l (x : xs) = case create s xs of
      (r, ys) -> let t' = link x l r in t' `seq` go (s * 2) t' ys
    create !s [] = (Tip, [])
    create s xs@(x : xs')
      | s == 1 = (Bin 1 x Tip Tip, xs')
      | otherwise = case create (s `div` 2) xs of
          res@(_, []) -> res
          (l, y : ys) -> case create (s `div` 2) ys of
            (r, zs) -> (link y l r, zs)

fromDistinctDescList :: [a] -> Set a
fromDistinctDescList [] = Tip
fromDistinctDescList (x0 : xs0) = go (1 :: Int) (Bin 1 x0 Tip Tip) xs0
  where
    go !s t [] = t
    go s r (x : xs) = case create s xs of
      (l, ys) -> let t' = link x l r in t' `seq` go (s * 2) t' ys
    create !s [] = (Tip, [])
    create s xs@(x : xs')
      | s == 1 = (Bin 1 x Tip Tip, xs')
      | otherwise = case create (s `div` 2) xs of
          res@(_, []) -> res
          (r, y : ys) -> case create (s `div` 2) ys of
            (l, zs) -> (link y l r, zs)

-- ---- split and indexing ---------------------------------------------------------------

split :: Ord a => a -> Set a -> (Set a, Set a)
split x t = splitS x t

splitS :: Ord a => a -> Set a -> (Set a, Set a)
splitS _ Tip = (Tip, Tip)
splitS x (Bin _ y l r) = case compare x y of
  LT -> case splitS x l of
    (lt, gt) -> let gt' = link y gt r in gt' `seq` (lt, gt')
  GT -> case splitS x r of
    (lt, gt) -> let lt' = link y l lt in lt' `seq` (lt', gt)
  EQ -> (l, r)

splitMember :: Ord a => a -> Set a -> (Set a, Bool, Set a)
splitMember _ Tip = (Tip, False, Tip)
splitMember x (Bin _ y l r) = case compare x y of
  LT -> let (lt, found, gt) = splitMember x l
            gt' = link y gt r
        in gt' `seq` (lt, found, gt')
  GT -> let (lt, found, gt) = splitMember x r
            lt' = link y l lt
        in lt' `seq` (lt', found, gt)
  EQ -> (l, True, r)

findIndex :: Ord a => a -> Set a -> Int
findIndex = go 0
  where
    go !idx !x Tip = error "Set.findIndex: element is not in the set"
    go idx x (Bin _ kx l r) = case compare x kx of
      LT -> go idx x l
      GT -> go (idx + size l + 1) x r
      EQ -> idx + size l

lookupIndex :: Ord a => a -> Set a -> Maybe Int
lookupIndex = go 0
  where
    go !idx !x Tip = Nothing
    go idx x (Bin _ kx l r) = case compare x kx of
      LT -> go idx x l
      GT -> go (idx + size l + 1) x r
      EQ -> Just $! idx + size l

elemAt :: Int -> Set a -> a
elemAt !i Tip = error "Set.elemAt: index out of range"
elemAt i (Bin _ x l r) = case compare i sizeL of
  LT -> elemAt i l
  GT -> elemAt (i - sizeL - 1) r
  EQ -> x
  where sizeL = size l

deleteAt :: Int -> Set a -> Set a
deleteAt !i t = case t of
  Tip -> error "Set.deleteAt: index out of range"
  Bin _ x l r -> let sizeL = size l in case compare i sizeL of
    LT -> balanceR x (deleteAt i l) r
    GT -> balanceL x l (deleteAt (i - sizeL - 1) r)
    EQ -> glue l r

take :: Int -> Set a -> Set a
take i m | i >= size m = m
take i0 m0 = go i0 m0
  where
    go i m | i <= 0 = m `seq` Tip
    go !i Tip = Tip
    go i (Bin _ x l r) = case compare i sizeL of
      LT -> go i l
      GT -> link x l (go (i - sizeL - 1) r)
      EQ -> l
      where sizeL = size l

drop :: Int -> Set a -> Set a
drop i m | i >= size m = Tip
drop i0 m0 = go i0 m0
  where
    go i m | i <= 0 = m
    go !i Tip = Tip
    go i (Bin _ x l r) = case compare i sizeL of
      LT -> link x (go i l) r
      GT -> go (i - sizeL - 1) r
      EQ -> insertMin x r
      where sizeL = size l

splitAt :: Int -> Set a -> (Set a, Set a)
splitAt i0 m0
  | i0 >= size m0 = (m0, Tip)
  | otherwise = go i0 m0
  where
    go i m | i <= 0 = (Tip, m)
    go !i Tip = (Tip, Tip)
    go i (Bin _ x l r) = case compare i sizeL of
      LT -> case go i l of
        (ll, lr) -> let b = link x lr r in b `seq` (ll, b)
      GT -> case go (i - sizeL - 1) r of
        (rl, rr) -> let a = link x l rl in a `seq` (a, rr)
      EQ -> let b = insertMin x r in b `seq` (l, b)
      where sizeL = size l

takeWhileAntitone :: (a -> Bool) -> Set a -> Set a
takeWhileAntitone _ Tip = Tip
takeWhileAntitone p (Bin _ x l r)
  | p x = link x l (takeWhileAntitone p r)
  | otherwise = takeWhileAntitone p l

dropWhileAntitone :: (a -> Bool) -> Set a -> Set a
dropWhileAntitone _ Tip = Tip
dropWhileAntitone p (Bin _ x l r)
  | p x = dropWhileAntitone p r
  | otherwise = link x (dropWhileAntitone p l) r

spanAntitone :: (a -> Bool) -> Set a -> (Set a, Set a)
spanAntitone p0 m = go p0 m
  where
    go _ Tip = (Tip, Tip)
    go p (Bin _ x l r)
      | p x = case go p r of
          (u, v) -> let a = link x l u in a `seq` (a, v)
      | otherwise = case go p l of
          (u, v) -> let b = link x v r in b `seq` (u, b)

-- ---- views -------------------------------------------------------------------------

deleteFindMin :: Set a -> (a, Set a)
deleteFindMin t = case minView t of
  Just r -> r
  Nothing -> (error "Set.deleteFindMin: can not return the minimal element of an empty set", Tip)

deleteFindMax :: Set a -> (a, Set a)
deleteFindMax t = case maxView t of
  Just r -> r
  Nothing -> (error "Set.deleteFindMax: can not return the maximal element of an empty set", Tip)

minViewSure :: a -> Set a -> Set a -> (a, Set a)
minViewSure = go
  where
    go x Tip r = (x, r)
    go x (Bin _ xl ll lr) r = case go xl ll lr of
      (xm, l') -> let t = balanceR x l' r in t `seq` (xm, t)

minView :: Set a -> Maybe (a, Set a)
minView Tip = Nothing
minView (Bin _ x l r) = Just $! minViewSure x l r

maxViewSure :: a -> Set a -> Set a -> (a, Set a)
maxViewSure = go
  where
    go x l Tip = (x, l)
    go x l (Bin _ xr rl rr) = case go xr rl rr of
      (xm, r') -> let t = balanceL x l r' in t `seq` (xm, t)

maxView :: Set a -> Maybe (a, Set a)
maxView Tip = Nothing
maxView (Bin _ x l r) = Just $! maxViewSure x l r

cartesianProduct :: Set a -> Set b -> Set (a, b)
cartesianProduct as bs
  | null as || null bs = Tip
  | otherwise = fromDistinctAscList [(a, b) | a <- toAscList as, b <- toAscList bs]

powerSet :: Set a -> Set (Set a)
powerSet xs0 = insertMin empty (foldr' step Tip xs0)
  where
    step x pxs = insertMin (singleton x) (insertMin x `mapMonotonic` pxs) `glue` pxs

disjointUnion :: Set a -> Set b -> Set (Either a b)
disjointUnion as bs = merge (mapMonotonic Left as) (mapMonotonic Right bs)

-- ---- balancing -----------------------------------------------------------------------

link :: a -> Set a -> Set a -> Set a
link x Tip r = insertMin x r
link x l Tip = insertMax x l
link x l@(Bin sizeL y ly ry) r@(Bin sizeR z lz rz)
  | delta * sizeL < sizeR = balanceL z (link x l lz) rz
  | delta * sizeR < sizeL = balanceR y ly (link x ry r)
  | otherwise = bin x l r

insertMax :: a -> Set a -> Set a
insertMax x t = case t of
  Tip -> singleton x
  Bin _ y l r -> balanceR y l (insertMax x r)

insertMin :: a -> Set a -> Set a
insertMin x t = case t of
  Tip -> singleton x
  Bin _ y l r -> balanceL y (insertMin x l) r

merge :: Set a -> Set a -> Set a
merge Tip r = r
merge l Tip = l
merge l@(Bin sizeL x lx rx) r@(Bin sizeR y ly ry)
  | delta * sizeL < sizeR = balanceL y (merge l ly) ry
  | delta * sizeR < sizeL = balanceR x lx (merge rx r)
  | otherwise = glue l r

glue :: Set a -> Set a -> Set a
glue Tip r = r
glue l Tip = l
glue l@(Bin sl xl ll lr) r@(Bin sr xr rl rr)
  | sl > sr = case maxViewSure xl ll lr of (m, l') -> balanceR m l' r
  | otherwise = case minViewSure xr rl rr of (m, r') -> balanceL m l r'

delta :: Int
delta = 3

ratio :: Int
ratio = 2

balanceL :: a -> Set a -> Set a -> Set a
balanceL x l r = case r of
  Tip -> case l of
    Tip -> Bin 1 x Tip Tip
    (Bin _ _ Tip Tip) -> Bin 2 x l Tip
    (Bin _ lx Tip (Bin _ lrx _ _)) -> Bin 3 lrx (Bin 1 lx Tip Tip) (Bin 1 x Tip Tip)
    (Bin _ lx ll@(Bin _ _ _ _) Tip) -> Bin 3 lx ll (Bin 1 x Tip Tip)
    (Bin ls lx ll@(Bin lls _ _ _) lr@(Bin lrs lrx lrl lrr))
      | lrs < ratio * lls -> Bin (1 + ls) lx ll (Bin (1 + lrs) x lr Tip)
      | otherwise -> Bin (1 + ls) lrx (Bin (1 + lls + size lrl) lx ll lrl) (Bin (1 + size lrr) x lrr Tip)
  (Bin rs _ _ _) -> case l of
    Tip -> Bin (1 + rs) x Tip r
    (Bin ls lx ll lr)
      | ls > delta * rs -> case (ll, lr) of
          (Bin lls _ _ _, Bin lrs lrx lrl lrr)
            | lrs < ratio * lls -> Bin (1 + ls + rs) lx ll (Bin (1 + rs + lrs) x lr r)
            | otherwise -> Bin (1 + ls + rs) lrx (Bin (1 + lls + size lrl) lx ll lrl) (Bin (1 + rs + size lrr) x lrr r)
          (_, _) -> error "Failure in Data.Set.balanceL"
      | otherwise -> Bin (1 + ls + rs) x l r

balanceR :: a -> Set a -> Set a -> Set a
balanceR x l r = case l of
  Tip -> case r of
    Tip -> Bin 1 x Tip Tip
    (Bin _ _ Tip Tip) -> Bin 2 x Tip r
    (Bin _ rx Tip rr@(Bin _ _ _ _)) -> Bin 3 rx (Bin 1 x Tip Tip) rr
    (Bin _ rx (Bin _ rlx _ _) Tip) -> Bin 3 rlx (Bin 1 x Tip Tip) (Bin 1 rx Tip Tip)
    (Bin rs rx rl@(Bin rls rlx rll rlr) rr@(Bin rrs _ _ _))
      | rls < ratio * rrs -> Bin (1 + rs) rx (Bin (1 + rls) x Tip rl) rr
      | otherwise -> Bin (1 + rs) rlx (Bin (1 + size rll) x Tip rll) (Bin (1 + rrs + size rlr) rx rlr rr)
  (Bin ls _ _ _) -> case r of
    Tip -> Bin (1 + ls) x l Tip
    (Bin rs rx rl rr)
      | rs > delta * ls -> case (rl, rr) of
          (Bin rls rlx rll rlr, Bin rrs _ _ _)
            | rls < ratio * rrs -> Bin (1 + ls + rs) rx (Bin (1 + ls + rls) x l rl) rr
            | otherwise -> Bin (1 + ls + rs) rlx (Bin (1 + ls + size rll) x l rll) (Bin (1 + rrs + size rlr) rx rlr rr)
          (_, _) -> error "Failure in Data.Set.balanceR"
      | otherwise -> Bin (1 + ls + rs) x l r

bin :: a -> Set a -> Set a -> Set a
bin x l r = Bin (size l + size r + 1) x l r
