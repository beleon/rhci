-- Data.Map (lazy), ported from containers-0.6.7 (Data.Map.Internal), the
-- version GHC 9.6 ships: the same weight-balanced trees and algorithms, so
-- results, laziness (keys and spine strict, values lazy) and errors are
-- containers'. GHC-only optimisations (pointer equality, unboxed pairs,
-- rewrite rules) are left out: they never change a result. Bang patterns
-- are written with seq. The merge framework (WhenMissing/WhenMatched) is
-- not ported; differenceWith uses mergeWithKey, which computes the same.
module Data.Map.Internal where

import Prelude hiding (lookup, map, filter, foldr, foldl, null, splitAt, take, drop)
import qualified Data.List as List
import qualified Data.Foldable as Foldable
import qualified Data.Set.Internal as Set
import Data.Set.Internal (Set)
import Control.Applicative (liftA3)

infixl 9 !, !?, \\

data Map k a = Bin !Int !k a !(Map k a) !(Map k a) | Tip

(!) :: Ord k => Map k a -> k -> a
(!) m k = find k m

(!?) :: Ord k => Map k a -> k -> Maybe a
(!?) m k = lookup k m

(\\) :: Ord k => Map k a -> Map k b -> Map k a
m1 \\ m2 = difference m1 m2

-- ---- instances ---------------------------------------------------------------------

instance Ord k => Semigroup (Map k v) where
  (<>) = union

instance Ord k => Monoid (Map k v) where
  mempty = empty
  mconcat = unions

instance (Eq k, Eq a) => Eq (Map k a) where
  t1 == t2 = (size t1 == size t2) && (toAscList t1 == toAscList t2)

instance (Ord k, Ord v) => Ord (Map k v) where
  compare m1 m2 = compare (toAscList m1) (toAscList m2)

instance (Show k, Show a) => Show (Map k a) where
  showsPrec d m = showParen (d > 10) $ showString "fromList " . shows (toList m)

instance (Ord k, Read k, Read e) => Read (Map k e) where
  readPrec = parens $ prec 10 $ do
    Ident "fromList" <- lexP
    xs <- readPrec
    return (fromList xs)
  readListPrec = readListPrecDefault

instance Functor (Map k) where
  fmap f m = map f m
  _ <$ Tip = Tip
  a <$ (Bin sx kx _ l r) = Bin sx kx a (a <$ l) (a <$ r)

instance Traversable (Map k) where
  traverse f = traverseWithKey (\_ -> f)

instance Foldable (Map k) where
  foldMap f t = go t
    where
      go Tip = mempty
      go (Bin 1 _ v _ _) = f v
      go (Bin _ _ v l r) = go l `mappend` (f v `mappend` go r)
  foldr = foldr
  foldl = foldl
  foldl' = foldl'
  foldr' = foldr'
  length = size
  null = null
  toList = elems
  elem = go
    where
      go x Tip = x `seq` False
      go x (Bin _ _ v l r) = x == v || go x l || go x r
  maximum = start
    where
      start Tip = error "Data.Foldable.maximum (for Data.Map): empty map"
      start (Bin _ _ v l r) = go (go v l) r
      go m Tip = m `seq` m
      go m (Bin _ _ v l r) = m `seq` go (go (max m v) l) r
  minimum = start
    where
      start Tip = error "Data.Foldable.minimum (for Data.Map): empty map"
      start (Bin _ _ v l r) = go (go v l) r
      go m Tip = m `seq` m
      go m (Bin _ _ v l r) = m `seq` go (go (min m v) l) r
  sum = foldl' (+) 0
  product = foldl' (*) 1

-- ---- query -------------------------------------------------------------------------

null :: Map k a -> Bool
null Tip = True
null (Bin _ _ _ _ _) = False

size :: Map k a -> Int
size Tip = 0
size (Bin sz _ _ _ _) = sz

lookup :: Ord k => k -> Map k a -> Maybe a
lookup = go
  where
    go k Tip = k `seq` Nothing
    go k (Bin _ kx x l r) = case compare k kx of
      LT -> go k l
      GT -> go k r
      EQ -> Just x

member :: Ord k => k -> Map k a -> Bool
member = go
  where
    go k Tip = k `seq` False
    go k (Bin _ kx _ l r) = case compare k kx of
      LT -> go k l
      GT -> go k r
      EQ -> True

notMember :: Ord k => k -> Map k a -> Bool
notMember k m = not $ member k m

find :: Ord k => k -> Map k a -> a
find = go
  where
    go k Tip = k `seq` error "Map.!: given key is not an element in the map"
    go k (Bin _ kx x l r) = case compare k kx of
      LT -> go k l
      GT -> go k r
      EQ -> x

findWithDefault :: Ord k => a -> k -> Map k a -> a
findWithDefault = go
  where
    go def k Tip = k `seq` def
    go def k (Bin _ kx x l r) = case compare k kx of
      LT -> go def k l
      GT -> go def k r
      EQ -> x

lookupLT :: Ord k => k -> Map k v -> Maybe (k, v)
lookupLT = goNothing
  where
    goNothing k Tip = k `seq` Nothing
    goNothing k (Bin _ kx x l r) | k <= kx = goNothing k l
                                 | otherwise = goJust k kx x r
    goJust k kx' x' Tip = k `seq` Just (kx', x')
    goJust k kx' x' (Bin _ kx x l r) | k <= kx = goJust k kx' x' l
                                     | otherwise = goJust k kx x r

lookupGT :: Ord k => k -> Map k v -> Maybe (k, v)
lookupGT = goNothing
  where
    goNothing k Tip = k `seq` Nothing
    goNothing k (Bin _ kx x l r) | k < kx = goJust k kx x l
                                 | otherwise = goNothing k r
    goJust k kx' x' Tip = k `seq` Just (kx', x')
    goJust k kx' x' (Bin _ kx x l r) | k < kx = goJust k kx x l
                                     | otherwise = goJust k kx' x' r

lookupLE :: Ord k => k -> Map k v -> Maybe (k, v)
lookupLE = goNothing
  where
    goNothing k Tip = k `seq` Nothing
    goNothing k (Bin _ kx x l r) = case compare k kx of
      LT -> goNothing k l
      EQ -> Just (kx, x)
      GT -> goJust k kx x r
    goJust k kx' x' Tip = k `seq` Just (kx', x')
    goJust k kx' x' (Bin _ kx x l r) = case compare k kx of
      LT -> goJust k kx' x' l
      EQ -> Just (kx, x)
      GT -> goJust k kx x r

lookupGE :: Ord k => k -> Map k v -> Maybe (k, v)
lookupGE = goNothing
  where
    goNothing k Tip = k `seq` Nothing
    goNothing k (Bin _ kx x l r) = case compare k kx of
      LT -> goJust k kx x l
      EQ -> Just (kx, x)
      GT -> goNothing k r
    goJust k kx' x' Tip = k `seq` Just (kx', x')
    goJust k kx' x' (Bin _ kx x l r) = case compare k kx of
      LT -> goJust k kx x l
      EQ -> Just (kx, x)
      GT -> goJust k kx' x' r

-- ---- construction and insertion -------------------------------------------------------

empty :: Map k a
empty = Tip

singleton :: k -> a -> Map k a
singleton k x = Bin 1 k x Tip Tip

insert :: Ord k => k -> a -> Map k a -> Map k a
insert kx0 = go kx0 kx0
  where
    go orig kx x Tip = kx `seq` singleton orig x
    go orig kx x (Bin sz ky y l r) = kx `seq` case compare kx ky of
      LT -> balanceL ky y (go orig kx x l) r
      GT -> balanceR ky y l (go orig kx x r)
      EQ -> Bin sz orig x l r

-- Insert, keeping the entry already there (union's right argument).
insertR :: Ord k => k -> a -> Map k a -> Map k a
insertR kx0 = go kx0 kx0
  where
    go orig kx x Tip = kx `seq` singleton orig x
    go orig kx x t@(Bin _ ky y l r) = kx `seq` case compare kx ky of
      LT -> balanceL ky y (go orig kx x l) r
      GT -> balanceR ky y l (go orig kx x r)
      EQ -> t

insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWith = go
  where
    go _ kx x Tip = kx `seq` singleton kx x
    go f kx x (Bin sy ky y l r) = kx `seq` case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> Bin sy kx (f x y) l r

insertWithR :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithR = go
  where
    go _ kx x Tip = kx `seq` singleton kx x
    go f kx x (Bin sy ky y l r) = kx `seq` case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> Bin sy ky (f y x) l r

insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKey = go
  where
    go _ kx x Tip = kx `seq` singleton kx x
    go f kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> Bin sy kx (f kx x y) l r

insertWithKeyR :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKeyR = go
  where
    go _ kx x Tip = kx `seq` singleton kx x
    go f kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> Bin sy ky (f ky y x) l r

insertLookupWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> (Maybe a, Map k a)
insertLookupWithKey f0 k0 x0 = go f0 k0 x0
  where
    go _ kx x Tip = kx `seq` (Nothing, singleton kx x)
    go f kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> case go f kx x l of
        (found, l') -> let t' = balanceL ky y l' r in t' `seq` (found, t')
      GT -> case go f kx x r of
        (found, r') -> let t' = balanceR ky y l r' in t' `seq` (found, t')
      EQ -> (Just y, Bin sy kx (f kx x y) l r)

-- ---- deletion and update ---------------------------------------------------------------

delete :: Ord k => k -> Map k a -> Map k a
delete = go
  where
    go k Tip = k `seq` Tip
    go k (Bin _ kx x l r) = case compare k kx of
      LT -> balanceR kx x (go k l) r
      GT -> balanceL kx x l (go k r)
      EQ -> glue l r

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a
adjust f = adjustWithKey (\_ x -> f x)

adjustWithKey :: Ord k => (k -> a -> a) -> k -> Map k a -> Map k a
adjustWithKey = go
  where
    go _ k Tip = k `seq` Tip
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> Bin sx kx x (go f k l) r
      GT -> Bin sx kx x l (go f k r)
      EQ -> Bin sx kx (f kx x) l r

update :: Ord k => (a -> Maybe a) -> k -> Map k a -> Map k a
update f = updateWithKey (\_ x -> f x)

updateWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a -> Map k a
updateWithKey = go
  where
    go _ k Tip = k `seq` Tip
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> balanceR kx x (go f k l) r
      GT -> balanceL kx x l (go f k r)
      EQ -> case f kx x of
        Just x' -> Bin sx kx x' l r
        Nothing -> glue l r

updateLookupWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a -> (Maybe a, Map k a)
updateLookupWithKey f0 k0 = go f0 k0
  where
    go _ k Tip = k `seq` (Nothing, Tip)
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> case go f k l of
        (found, l') -> let t' = balanceR kx x l' r in t' `seq` (found, t')
      GT -> case go f k r of
        (found, r') -> let t' = balanceL kx x l r' in t' `seq` (found, t')
      EQ -> case f kx x of
        Just x' -> (Just x', Bin sx kx x' l r)
        Nothing -> let glued = glue l r in glued `seq` (Just x, glued)

alter :: Ord k => (Maybe a -> Maybe a) -> k -> Map k a -> Map k a
alter = go
  where
    go f k Tip = k `seq` case f Nothing of
      Nothing -> Tip
      Just x -> singleton k x
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> balance kx x (go f k l) r
      GT -> balance kx x l (go f k r)
      EQ -> case f (Just x) of
        Just x' -> Bin sx kx x' l r
        Nothing -> glue l r

-- alterF as containers computes it: f sees the current value; Nothing
-- deletes, Just replaces the value (keeping the key) or inserts.
alterF :: (Functor f, Ord k) => (Maybe a -> f (Maybe a)) -> k -> Map k a -> f (Map k a)
alterF f k m = k `seq` fmap choose (f mv)
  where
    mv = lookup k m
    choose Nothing = case mv of
      Nothing -> m
      Just _ -> delete k m
    choose (Just new) = case mv of
      Nothing -> insert k new m
      Just _ -> replaceValue k new m

replaceValue :: Ord k => k -> a -> Map k a -> Map k a
replaceValue _ _ Tip = Tip
replaceValue k x (Bin sz ky y l r) = case compare k ky of
  LT -> Bin sz ky y (replaceValue k x l) r
  GT -> Bin sz ky y l (replaceValue k x r)
  EQ -> Bin sz ky x l r

-- ---- indexing ----------------------------------------------------------------------

findIndex :: Ord k => k -> Map k a -> Int
findIndex = go 0
  where
    go idx k Tip = idx `seq` k `seq` error "Map.findIndex: element is not in the map"
    go idx k (Bin _ kx _ l r) = case compare k kx of
      LT -> go idx k l
      GT -> go (idx + size l + 1) k r
      EQ -> idx + size l

lookupIndex :: Ord k => k -> Map k a -> Maybe Int
lookupIndex = go 0
  where
    go idx k Tip = idx `seq` k `seq` Nothing
    go idx k (Bin _ kx _ l r) = case compare k kx of
      LT -> go idx k l
      GT -> go (idx + size l + 1) k r
      EQ -> Just $! idx + size l

elemAt :: Int -> Map k a -> (k, a)
elemAt i Tip = i `seq` error "Map.elemAt: index out of range"
elemAt i (Bin _ kx x l r) = case compare i sizeL of
  LT -> elemAt i l
  GT -> elemAt (i - sizeL - 1) r
  EQ -> (kx, x)
  where sizeL = size l

updateAt :: (k -> a -> Maybe a) -> Int -> Map k a -> Map k a
updateAt f i t = i `seq` case t of
  Tip -> error "Map.updateAt: index out of range"
  Bin sx kx x l r -> let sizeL = size l in case compare i sizeL of
    LT -> balanceR kx x (updateAt f i l) r
    GT -> balanceL kx x l (updateAt f (i - sizeL - 1) r)
    EQ -> case f kx x of
      Just x' -> Bin sx kx x' l r
      Nothing -> glue l r

deleteAt :: Int -> Map k a -> Map k a
deleteAt i t = i `seq` case t of
  Tip -> error "Map.deleteAt: index out of range"
  Bin _ kx x l r -> let sizeL = size l in case compare i sizeL of
    LT -> balanceR kx x (deleteAt i l) r
    GT -> balanceL kx x l (deleteAt (i - sizeL - 1) r)
    EQ -> glue l r

take :: Int -> Map k a -> Map k a
take i m | i >= size m = m
take i0 m0 = go i0 m0
  where
    go i m | i <= 0 = m `seq` Tip
    go i Tip = i `seq` Tip
    go i (Bin _ kx x l r) = case compare i sizeL of
      LT -> go i l
      GT -> link kx x l (go (i - sizeL - 1) r)
      EQ -> l
      where sizeL = size l

drop :: Int -> Map k a -> Map k a
drop i m | i >= size m = Tip
drop i0 m0 = go i0 m0
  where
    go i m | i <= 0 = m
    go i Tip = i `seq` Tip
    go i (Bin _ kx x l r) = case compare i sizeL of
      LT -> link kx x (go i l) r
      GT -> go (i - sizeL - 1) r
      EQ -> insertMin kx x r
      where sizeL = size l

splitAt :: Int -> Map k a -> (Map k a, Map k a)
splitAt i0 m0
  | i0 >= size m0 = (m0, Tip)
  | otherwise = go i0 m0
  where
    go i m | i <= 0 = (Tip, m)
    go i Tip = i `seq` (Tip, Tip)
    go i (Bin _ kx x l r) = case compare i sizeL of
      LT -> case go i l of
        (ll, lr) -> let b = link kx x lr r in b `seq` (ll, b)
      GT -> case go (i - sizeL - 1) r of
        (rl, rr) -> let a = link kx x l rl in a `seq` (a, rr)
      EQ -> let b = insertMin kx x r in b `seq` (l, b)
      where sizeL = size l

-- ---- minimum and maximum -----------------------------------------------------------

lookupMinSure :: k -> a -> Map k a -> (k, a)
lookupMinSure k a Tip = (k, a)
lookupMinSure _ _ (Bin _ k a l _) = lookupMinSure k a l

lookupMin :: Map k a -> Maybe (k, a)
lookupMin Tip = Nothing
lookupMin (Bin _ k x l _) = Just $! lookupMinSure k x l

findMin :: Map k a -> (k, a)
findMin t = case lookupMin t of
  Just r -> r
  Nothing -> error "Map.findMin: empty map has no minimal element"

lookupMaxSure :: k -> a -> Map k a -> (k, a)
lookupMaxSure k a Tip = (k, a)
lookupMaxSure _ _ (Bin _ k a _ r) = lookupMaxSure k a r

lookupMax :: Map k a -> Maybe (k, a)
lookupMax Tip = Nothing
lookupMax (Bin _ k x _ r) = Just $! lookupMaxSure k x r

findMax :: Map k a -> (k, a)
findMax t = case lookupMax t of
  Just r -> r
  Nothing -> error "Map.findMax: empty map has no maximal element"

deleteMin :: Map k a -> Map k a
deleteMin (Bin _ _ _ Tip r) = r
deleteMin (Bin _ kx x l r) = balanceR kx x (deleteMin l) r
deleteMin Tip = Tip

deleteMax :: Map k a -> Map k a
deleteMax (Bin _ _ _ l Tip) = l
deleteMax (Bin _ kx x l r) = balanceL kx x l (deleteMax r)
deleteMax Tip = Tip

updateMin :: (a -> Maybe a) -> Map k a -> Map k a
updateMin f m = updateMinWithKey (\_ x -> f x) m

updateMax :: (a -> Maybe a) -> Map k a -> Map k a
updateMax f m = updateMaxWithKey (\_ x -> f x) m

updateMinWithKey :: (k -> a -> Maybe a) -> Map k a -> Map k a
updateMinWithKey _ Tip = Tip
updateMinWithKey f (Bin sx kx x Tip r) = case f kx x of
  Nothing -> r
  Just x' -> Bin sx kx x' Tip r
updateMinWithKey f (Bin _ kx x l r) = balanceR kx x (updateMinWithKey f l) r

updateMaxWithKey :: (k -> a -> Maybe a) -> Map k a -> Map k a
updateMaxWithKey _ Tip = Tip
updateMaxWithKey f (Bin sx kx x l Tip) = case f kx x of
  Nothing -> l
  Just x' -> Bin sx kx x' l Tip
updateMaxWithKey f (Bin _ kx x l r) = balanceL kx x l (updateMaxWithKey f r)

data MinView k a = MinView !k a !(Map k a)

data MaxView k a = MaxView !k a !(Map k a)

minViewSure :: k -> a -> Map k a -> Map k a -> MinView k a
minViewSure = go
  where
    go k x Tip r = MinView k x r
    go k x (Bin _ kl xl ll lr) r = case go kl xl ll lr of
      MinView km xm l' -> MinView km xm (balanceR k x l' r)

maxViewSure :: k -> a -> Map k a -> Map k a -> MaxView k a
maxViewSure = go
  where
    go k x l Tip = MaxView k x l
    go k x l (Bin _ kr xr rl rr) = case go kr xr rl rr of
      MaxView km xm r' -> MaxView km xm (balanceL k x l r')

minViewWithKey :: Map k a -> Maybe ((k, a), Map k a)
minViewWithKey Tip = Nothing
minViewWithKey (Bin _ k x l r) = Just $ case minViewSure k x l r of
  MinView km xm t -> ((km, xm), t)

maxViewWithKey :: Map k a -> Maybe ((k, a), Map k a)
maxViewWithKey Tip = Nothing
maxViewWithKey (Bin _ k x l r) = Just $ case maxViewSure k x l r of
  MaxView km xm t -> ((km, xm), t)

minView :: Map k a -> Maybe (a, Map k a)
minView t = case minViewWithKey t of
  Nothing -> Nothing
  Just ~((_, x), t') -> Just (x, t')

maxView :: Map k a -> Maybe (a, Map k a)
maxView t = case maxViewWithKey t of
  Nothing -> Nothing
  Just ~((_, x), t') -> Just (x, t')

deleteFindMin :: Map k a -> ((k, a), Map k a)
deleteFindMin t = case minViewWithKey t of
  Nothing -> (error "Map.deleteFindMin: can not return the minimal element of an empty map", Tip)
  Just res -> res

deleteFindMax :: Map k a -> ((k, a), Map k a)
deleteFindMax t = case maxViewWithKey t of
  Nothing -> (error "Map.deleteFindMax: can not return the maximal element of an empty map", Tip)
  Just res -> res

-- ---- union -------------------------------------------------------------------------

unions :: (Foldable f, Ord k) => f (Map k a) -> Map k a
unions ts = Foldable.foldl' union empty ts

unionsWith :: (Foldable f, Ord k) => (a -> a -> a) -> f (Map k a) -> Map k a
unionsWith f ts = Foldable.foldl' (unionWith f) empty ts

union :: Ord k => Map k a -> Map k a -> Map k a
union t1 Tip = t1
union t1 (Bin _ k x Tip Tip) = insertR k x t1
union (Bin _ k x Tip Tip) t2 = insert k x t2
union Tip t2 = t2
union (Bin _ k1 x1 l1 r1) t2 = case split k1 t2 of
  (l2, r2) -> let l1l2 = union l1 l2
                  r1r2 = union r1 r2
              in l1l2 `seq` r1r2 `seq` link k1 x1 l1l2 r1r2

unionWith :: Ord k => (a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWith _ t1 Tip = t1
unionWith f t1 (Bin _ k x Tip Tip) = insertWithR f k x t1
unionWith f (Bin _ k x Tip Tip) t2 = insertWith f k x t2
unionWith _ Tip t2 = t2
unionWith f (Bin _ k1 x1 l1 r1) t2 = case splitLookup k1 t2 of
  (l2, mb, r2) -> let l1l2 = unionWith f l1 l2
                      r1r2 = unionWith f r1 r2
                  in l1l2 `seq` r1r2 `seq` case mb of
                       Nothing -> link k1 x1 l1l2 r1r2
                       Just x2 -> link k1 (f x1 x2) l1l2 r1r2

unionWithKey :: Ord k => (k -> a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWithKey _ t1 Tip = t1
unionWithKey f t1 (Bin _ k x Tip Tip) = insertWithKeyR f k x t1
unionWithKey f (Bin _ k x Tip Tip) t2 = insertWithKey f k x t2
unionWithKey _ Tip t2 = t2
unionWithKey f (Bin _ k1 x1 l1 r1) t2 = case splitLookup k1 t2 of
  (l2, mb, r2) -> let l1l2 = unionWithKey f l1 l2
                      r1r2 = unionWithKey f r1 r2
                  in l1l2 `seq` r1r2 `seq` case mb of
                       Nothing -> link k1 x1 l1l2 r1r2
                       Just x2 -> link k1 (f k1 x1 x2) l1l2 r1r2

-- ---- difference and intersection --------------------------------------------------------

difference :: Ord k => Map k a -> Map k b -> Map k a
difference Tip _ = Tip
difference t1 Tip = t1
difference t1 (Bin _ k _ l2 r2) = case split k t1 of
  (l1, r1) -> let l1l2 = difference l1 l2
                  r1r2 = difference r1 r2
              in l1l2 `seq` r1r2 `seq`
                   (if size l1l2 + size r1r2 == size t1 then t1 else link2 l1l2 r1r2)

withoutKeys :: Ord k => Map k a -> Set k -> Map k a
withoutKeys Tip _ = Tip
withoutKeys m Set.Tip = m
withoutKeys m (Set.Bin _ k ls rs) = case splitMember k m of
  (lm, _, rm) -> let lm' = withoutKeys lm ls
                     rm' = withoutKeys rm rs
                 in lm' `seq` rm' `seq` link2 lm' rm'

differenceWith :: Ord k => (a -> b -> Maybe a) -> Map k a -> Map k b -> Map k a
differenceWith f = differenceWithKey (\_ x y -> f x y)

differenceWithKey :: Ord k => (k -> a -> b -> Maybe a) -> Map k a -> Map k b -> Map k a
differenceWithKey f = mergeWithKey f id (const Tip)

intersection :: Ord k => Map k a -> Map k b -> Map k a
intersection Tip _ = Tip
intersection _ Tip = Tip
intersection (Bin _ k x l1 r1) t2 = case splitMember k t2 of
  (l2, mb, r2) -> let l1l2 = intersection l1 l2
                      r1r2 = intersection r1 r2
                  in l1l2 `seq` r1r2 `seq` (if mb then link k x l1l2 r1r2 else link2 l1l2 r1r2)

restrictKeys :: Ord k => Map k a -> Set k -> Map k a
restrictKeys Tip _ = Tip
restrictKeys _ Set.Tip = Tip
restrictKeys (Bin _ k x l1 r1) s = case Set.splitMember k s of
  (l2, b, r2) -> let l1l2 = restrictKeys l1 l2
                     r1r2 = restrictKeys r1 r2
                 in l1l2 `seq` r1r2 `seq` (if b then link k x l1l2 r1r2 else link2 l1l2 r1r2)

intersectionWith :: Ord k => (a -> b -> c) -> Map k a -> Map k b -> Map k c
intersectionWith _ Tip _ = Tip
intersectionWith _ _ Tip = Tip
intersectionWith f (Bin _ k x1 l1 r1) t2 = case splitLookup k t2 of
  (l2, mb, r2) -> let l1l2 = intersectionWith f l1 l2
                      r1r2 = intersectionWith f r1 r2
                  in l1l2 `seq` r1r2 `seq` case mb of
                       Just x2 -> link k (f x1 x2) l1l2 r1r2
                       Nothing -> link2 l1l2 r1r2

intersectionWithKey :: Ord k => (k -> a -> b -> c) -> Map k a -> Map k b -> Map k c
intersectionWithKey _ Tip _ = Tip
intersectionWithKey _ _ Tip = Tip
intersectionWithKey f (Bin _ k x1 l1 r1) t2 = case splitLookup k t2 of
  (l2, mb, r2) -> let l1l2 = intersectionWithKey f l1 l2
                      r1r2 = intersectionWithKey f r1 r2
                  in l1l2 `seq` r1r2 `seq` case mb of
                       Just x2 -> link k (f k x1 x2) l1l2 r1r2
                       Nothing -> link2 l1l2 r1r2

disjoint :: Ord k => Map k a -> Map k b -> Bool
disjoint Tip _ = True
disjoint _ Tip = True
disjoint (Bin 1 k _ _ _) t = k `notMember` t
disjoint (Bin _ k _ l r) t = not found && disjoint l lt && disjoint r gt
  where (lt, found, gt) = splitMember k t

compose :: Ord b => Map b c -> Map a b -> Map a c
compose bc ab = ab `seq` (if null bc then empty else mapMaybe (bc !?) ab)

mergeWithKey :: Ord k => (k -> a -> b -> Maybe c) -> (Map k a -> Map k c) -> (Map k b -> Map k c)
             -> Map k a -> Map k b -> Map k c
mergeWithKey f g1 g2 = go
  where
    go Tip t2 = g2 t2
    go t1 Tip = g1 t1
    go (Bin _ kx x l1 r1) t2 = case found of
        Nothing -> case g1 (singleton kx x) of
          Tip -> link2 l' r'
          (Bin _ _ x' Tip Tip) -> link kx x' l' r'
          _ -> error "mergeWithKey: Given function only1 does not fulfill required conditions (see documentation)"
        Just x2 -> case f kx x x2 of
          Nothing -> link2 l' r'
          Just x' -> link kx x' l' r'
      where
        (l2, found, r2) = splitLookup kx t2
        l' = go l1 l2
        r' = go r1 r2

-- ---- submaps -----------------------------------------------------------------------

isSubmapOf :: (Ord k, Eq a) => Map k a -> Map k a -> Bool
isSubmapOf m1 m2 = isSubmapOfBy (==) m1 m2

isSubmapOfBy :: Ord k => (a -> b -> Bool) -> Map k a -> Map k b -> Bool
isSubmapOfBy f t1 t2 = size t1 <= size t2 && submap' f t1 t2

submap' :: Ord a => (b -> c -> Bool) -> Map a b -> Map a c -> Bool
submap' _ Tip _ = True
submap' _ _ Tip = False
submap' f (Bin 1 kx x _ _) t = case lookup kx t of
  Just y -> f x y
  Nothing -> False
submap' f (Bin _ kx x l r) t = case found of
  Nothing -> False
  Just y -> f x y && size l <= size lt && size r <= size gt && submap' f l lt && submap' f r gt
  where (lt, found, gt) = splitLookup kx t

isProperSubmapOf :: (Ord k, Eq a) => Map k a -> Map k a -> Bool
isProperSubmapOf m1 m2 = isProperSubmapOfBy (==) m1 m2

isProperSubmapOfBy :: Ord k => (a -> b -> Bool) -> Map k a -> Map k b -> Bool
isProperSubmapOfBy f t1 t2 = size t1 < size t2 && submap' f t1 t2

-- ---- filter and partition -------------------------------------------------------------

filter :: (a -> Bool) -> Map k a -> Map k a
filter p m = filterWithKey (\_ x -> p x) m

filterWithKey :: (k -> a -> Bool) -> Map k a -> Map k a
filterWithKey _ Tip = Tip
filterWithKey p (Bin _ kx x l r) =
  let pl = filterWithKey p l
      pr = filterWithKey p r
  in pl `seq` pr `seq` (if p kx x then link kx x pl pr else link2 pl pr)

takeWhileAntitone :: (k -> Bool) -> Map k a -> Map k a
takeWhileAntitone _ Tip = Tip
takeWhileAntitone p (Bin _ kx x l r)
  | p kx = link kx x l (takeWhileAntitone p r)
  | otherwise = takeWhileAntitone p l

dropWhileAntitone :: (k -> Bool) -> Map k a -> Map k a
dropWhileAntitone _ Tip = Tip
dropWhileAntitone p (Bin _ kx x l r)
  | p kx = dropWhileAntitone p r
  | otherwise = link kx x (dropWhileAntitone p l) r

spanAntitone :: (k -> Bool) -> Map k a -> (Map k a, Map k a)
spanAntitone p0 m = go p0 m
  where
    go _ Tip = (Tip, Tip)
    go p (Bin _ kx x l r)
      | p kx = case go p r of
          (u, v) -> let a = link kx x l u in a `seq` (a, v)
      | otherwise = case go p l of
          (u, v) -> let b = link kx x v r in b `seq` (u, b)

partition :: (a -> Bool) -> Map k a -> (Map k a, Map k a)
partition p m = partitionWithKey (\_ x -> p x) m

partitionWithKey :: (k -> a -> Bool) -> Map k a -> (Map k a, Map k a)
partitionWithKey p0 t0 = go p0 t0
  where
    go _ Tip = (Tip, Tip)
    go p (Bin _ kx x l r) = case go p l of
      (l1, l2) -> case go p r of
        (r1, r2)
          | p kx x -> let a = link kx x l1 r1
                          b = link2 l2 r2
                      in a `seq` b `seq` (a, b)
          | otherwise -> let a = link2 l1 r1
                             b = link kx x l2 r2
                         in a `seq` b `seq` (a, b)

mapMaybe :: (a -> Maybe b) -> Map k a -> Map k b
mapMaybe f = mapMaybeWithKey (\_ x -> f x)

mapMaybeWithKey :: (k -> a -> Maybe b) -> Map k a -> Map k b
mapMaybeWithKey _ Tip = Tip
mapMaybeWithKey f (Bin _ kx x l r) = case f kx x of
  Just y -> link kx y (mapMaybeWithKey f l) (mapMaybeWithKey f r)
  Nothing -> link2 (mapMaybeWithKey f l) (mapMaybeWithKey f r)

mapEither :: (a -> Either b c) -> Map k a -> (Map k b, Map k c)
mapEither f m = mapEitherWithKey (\_ x -> f x) m

mapEitherWithKey :: (k -> a -> Either b c) -> Map k a -> (Map k b, Map k c)
mapEitherWithKey f0 t0 = go f0 t0
  where
    go _ Tip = (Tip, Tip)
    go f (Bin _ kx x l r) = case go f l of
      (l1, l2) -> case go f r of
        (r1, r2) -> case f kx x of
          Left y -> let a = link kx y l1 r1
                        b = link2 l2 r2
                    in a `seq` b `seq` (a, b)
          Right z -> let a = link2 l1 r1
                         b = link kx z l2 r2
                     in a `seq` b `seq` (a, b)

-- ---- map ---------------------------------------------------------------------------

map :: (a -> b) -> Map k a -> Map k b
map f = go
  where
    go Tip = Tip
    go (Bin sx kx x l r) = Bin sx kx (f x) (go l) (go r)

mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey _ Tip = Tip
mapWithKey f (Bin sx kx x l r) = Bin sx kx (f kx x) (mapWithKey f l) (mapWithKey f r)

traverseWithKey :: Applicative t => (k -> a -> t b) -> Map k a -> t (Map k b)
traverseWithKey f = go
  where
    go Tip = pure Tip
    go (Bin 1 k v _ _) = (\v' -> Bin 1 k v' Tip Tip) <$> f k v
    go (Bin s k v l r) = liftA3 (flip (Bin s k)) (go l) (f k v) (go r)

mapAccum :: (a -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccum f a m = mapAccumWithKey (\a' _ x' -> f a' x') a m

mapAccumWithKey :: (a -> k -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccumWithKey f a t = mapAccumL f a t

mapAccumL :: (a -> k -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccumL _ a Tip = (a, Tip)
mapAccumL f a (Bin sx kx x l r) =
  let (a1, l') = mapAccumL f a l
      (a2, x') = f a1 kx x
      (a3, r') = mapAccumL f a2 r
  in (a3, Bin sx kx x' l' r')

mapAccumRWithKey :: (a -> k -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccumRWithKey _ a Tip = (a, Tip)
mapAccumRWithKey f a (Bin sx kx x l r) =
  let (a1, r') = mapAccumRWithKey f a r
      (a2, x') = f a1 kx x
      (a3, l') = mapAccumRWithKey f a2 l
  in (a3, Bin sx kx x' l' r')

mapKeys :: Ord k2 => (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeys f = fromList . foldrWithKey (\k x xs -> (f k, x) : xs) []

mapKeysWith :: Ord k2 => (a -> a -> a) -> (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeysWith c f = fromListWith c . foldrWithKey (\k x xs -> (f k, x) : xs) []

mapKeysMonotonic :: (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeysMonotonic _ Tip = Tip
mapKeysMonotonic f (Bin sz k x l r) = Bin sz (f k) x (mapKeysMonotonic f l) (mapKeysMonotonic f r)

-- ---- folds -------------------------------------------------------------------------

foldr :: (a -> b -> b) -> b -> Map k a -> b
foldr f z = go z
  where
    go z' Tip = z'
    go z' (Bin _ _ x l r) = go (f x (go z' r)) l

foldr' :: (a -> b -> b) -> b -> Map k a -> b
foldr' f z = go z
  where
    go z' Tip = z' `seq` z'
    go z' (Bin _ _ x l r) = z' `seq` go (f x $! go z' r) l

foldl :: (a -> b -> a) -> a -> Map k b -> a
foldl f z = go z
  where
    go z' Tip = z'
    go z' (Bin _ _ x l r) = go (f (go z' l) x) r

foldl' :: (a -> b -> a) -> a -> Map k b -> a
foldl' f z = go z
  where
    go z' Tip = z' `seq` z'
    go z' (Bin _ _ x l r) = z' `seq` (let z'' = go z' l in z'' `seq` go (f z'' x) r)

foldrWithKey :: (k -> a -> b -> b) -> b -> Map k a -> b
foldrWithKey f z = go z
  where
    go z' Tip = z'
    go z' (Bin _ kx x l r) = go (f kx x (go z' r)) l

foldrWithKey' :: (k -> a -> b -> b) -> b -> Map k a -> b
foldrWithKey' f z = go z
  where
    go z' Tip = z' `seq` z'
    go z' (Bin _ kx x l r) = z' `seq` go (f kx x $! go z' r) l

foldlWithKey :: (a -> k -> b -> a) -> a -> Map k b -> a
foldlWithKey f z = go z
  where
    go z' Tip = z'
    go z' (Bin _ kx x l r) = go (f (go z' l) kx x) r

foldlWithKey' :: (a -> k -> b -> a) -> a -> Map k b -> a
foldlWithKey' f z = go z
  where
    go z' Tip = z' `seq` z'
    go z' (Bin _ kx x l r) = z' `seq` (let z'' = go z' l in z'' `seq` go (f z'' kx x) r)

foldMapWithKey :: Monoid m => (k -> a -> m) -> Map k a -> m
foldMapWithKey f = go
  where
    go Tip = mempty
    go (Bin 1 k v _ _) = f k v
    go (Bin _ k v l r) = go l `mappend` (f k v `mappend` go r)

-- ---- conversion ----------------------------------------------------------------------

elems :: Map k a -> [a]
elems = foldr (:) []

keys :: Map k a -> [k]
keys = foldrWithKey (\k _ ks -> k : ks) []

assocs :: Map k a -> [(k, a)]
assocs m = toAscList m

keysSet :: Map k a -> Set k
keysSet Tip = Set.Tip
keysSet (Bin sz kx _ l r) = Set.Bin sz kx (keysSet l) (keysSet r)

fromSet :: (k -> a) -> Set k -> Map k a
fromSet _ Set.Tip = Tip
fromSet f (Set.Bin sz x l r) = Bin sz x (f x) (fromSet f l) (fromSet f r)

toList :: Map k a -> [(k, a)]
toList = toAscList

toAscList :: Map k a -> [(k, a)]
toAscList = foldrWithKey (\k x xs -> (k, x) : xs) []

toDescList :: Map k a -> [(k, a)]
toDescList = foldlWithKey (\xs k x -> (k, x) : xs) []

fromList :: Ord k => [(k, a)] -> Map k a
fromList [] = Tip
fromList [(kx, x)] = Bin 1 kx x Tip Tip
fromList ((kx0, x0) : xs0)
  | not_ordered kx0 xs0 = fromList' (Bin 1 kx0 x0 Tip Tip) xs0
  | otherwise = go (1 :: Int) (Bin 1 kx0 x0 Tip Tip) xs0
  where
    not_ordered _ [] = False
    not_ordered kx ((ky, _) : _) = kx >= ky
    fromList' t0 xs = Foldable.foldl' ins t0 xs
      where ins t (k, x) = insert k x t
    go s t [] = s `seq` t
    go _ t [(kx, x)] = insertMax kx x t
    go s l xs@((kx, x) : xss)
      | not_ordered kx xss = fromList' l xs
      | otherwise = case create s xss of
          (r, ys, []) -> go (s * 2) (link kx x l r) ys
          (r, _, ys) -> fromList' (link kx x l r) ys
    create s [] = s `seq` (Tip, [], [])
    create s xs@(xp : xss)
      | s == 1 = case xp of
          (kx, x) | not_ordered kx xss -> (Bin 1 kx x Tip Tip, [], xss)
                  | otherwise -> (Bin 1 kx x Tip Tip, xss, [])
      | otherwise = case create (s `div` 2) xs of
          res@(_, [], _) -> res
          (l, [(ky, y)], zs) -> (insertMax ky y l, [], zs)
          (l, ys@((ky, y) : yss), _)
            | not_ordered ky yss -> (l, [], ys)
            | otherwise -> case create (s `div` 2) yss of
                (r, zs, ws) -> (link ky y l r, zs, ws)

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
fromListWith f xs = fromListWithKey (\_ x y -> f x y) xs

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromListWithKey f xs = Foldable.foldl' ins empty xs
  where ins t (k, x) = insertWithKey f k x t

fromAscList :: Eq k => [(k, a)] -> Map k a
fromAscList xs = fromDistinctAscList (combineEq xs)
  where
    combineEq xs' = case xs' of
      [] -> []
      [x] -> [x]
      (x : xx) -> combineEq' x xx
    combineEq' z [] = [z]
    combineEq' z@(kz, _) (x@(kx, xx) : xs')
      | kx == kz = combineEq' (kx, xx) xs'
      | otherwise = z : combineEq' x xs'

fromAscListWith :: Eq k => (a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWith f xs = fromAscListWithKey (\_ x y -> f x y) xs

fromAscListWithKey :: Eq k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWithKey f xs = fromDistinctAscList (combineEq xs)
  where
    combineEq xs' = case xs' of
      [] -> []
      [x] -> [x]
      (x : xx) -> combineEq' x xx
    combineEq' z [] = [z]
    combineEq' z@(kz, zz) (x@(kx, xx) : xs')
      | kx == kz = let yy = f kx xx zz in combineEq' (kx, yy) xs'
      | otherwise = z : combineEq' x xs'

fromDistinctAscList :: [(k, a)] -> Map k a
fromDistinctAscList [] = Tip
fromDistinctAscList ((kx0, x0) : xs0) = go (1 :: Int) (Bin 1 kx0 x0 Tip Tip) xs0
  where
    go s t [] = s `seq` t
    go s l ((kx, x) : xs) = case create s xs of
      (r, ys) -> let t' = link kx x l r in t' `seq` go (s * 2) t' ys
    create s [] = s `seq` (Tip, [])
    create s xs@(x' : xs')
      | s == 1 = case x' of (kx, x) -> (Bin 1 kx x Tip Tip, xs')
      | otherwise = case create (s `div` 2) xs of
          res@(_, []) -> res
          (l, (ky, y) : ys) -> case create (s `div` 2) ys of
            (r, zs) -> (link ky y l r, zs)

-- ---- split -------------------------------------------------------------------------

split :: Ord k => k -> Map k a -> (Map k a, Map k a)
split k0 t0 = k0 `seq` go k0 t0
  where
    go k t = case t of
      Tip -> (Tip, Tip)
      Bin _ kx x l r -> case compare k kx of
        LT -> case go k l of
          (lt, gt) -> let gt' = link kx x gt r in gt' `seq` (lt, gt')
        GT -> case go k r of
          (lt, gt) -> let lt' = link kx x l lt in lt' `seq` (lt', gt)
        EQ -> (l, r)

splitLookup :: Ord k => k -> Map k a -> (Map k a, Maybe a, Map k a)
splitLookup k0 m = go k0 m
  where
    go k t = k `seq` case t of
      Tip -> (Tip, Nothing, Tip)
      Bin _ kx x l r -> case compare k kx of
        LT -> case go k l of
          (lt, z, gt) -> let gt' = link kx x gt r in gt' `seq` (lt, z, gt')
        GT -> case go k r of
          (lt, z, gt) -> let lt' = link kx x l lt in lt' `seq` (lt', z, gt)
        EQ -> (l, Just x, r)

splitMember :: Ord k => k -> Map k a -> (Map k a, Bool, Map k a)
splitMember k0 m = go k0 m
  where
    go k t = k `seq` case t of
      Tip -> (Tip, False, Tip)
      Bin _ kx x l r -> case compare k kx of
        LT -> case go k l of
          (lt, z, gt) -> let gt' = link kx x gt r in gt' `seq` (lt, z, gt')
        GT -> case go k r of
          (lt, z, gt) -> let lt' = link kx x l lt in lt' `seq` (lt', z, gt)
        EQ -> (l, True, r)

-- ---- balancing -----------------------------------------------------------------------

link :: k -> a -> Map k a -> Map k a -> Map k a
link kx x Tip r = insertMin kx x r
link kx x l Tip = insertMax kx x l
link kx x l@(Bin sizeL ky y ly ry) r@(Bin sizeR kz z lz rz)
  | delta * sizeL < sizeR = balanceL kz z (link kx x l lz) rz
  | delta * sizeR < sizeL = balanceR ky y ly (link kx x ry r)
  | otherwise = bin kx x l r

insertMax :: k -> a -> Map k a -> Map k a
insertMax kx x t = case t of
  Tip -> singleton kx x
  Bin _ ky y l r -> balanceR ky y l (insertMax kx x r)

insertMin :: k -> a -> Map k a -> Map k a
insertMin kx x t = case t of
  Tip -> singleton kx x
  Bin _ ky y l r -> balanceL ky y (insertMin kx x l) r

link2 :: Map k a -> Map k a -> Map k a
link2 Tip r = r
link2 l Tip = l
link2 l@(Bin sizeL kx x lx rx) r@(Bin sizeR ky y ly ry)
  | delta * sizeL < sizeR = balanceL ky y (link2 l ly) ry
  | delta * sizeR < sizeL = balanceR kx x lx (link2 rx r)
  | otherwise = glue l r

glue :: Map k a -> Map k a -> Map k a
glue Tip r = r
glue l Tip = l
glue l@(Bin sl kl xl ll lr) r@(Bin sr kr xr rl rr)
  | sl > sr = case maxViewSure kl xl ll lr of MaxView km m l' -> balanceR km m l' r
  | otherwise = case minViewSure kr xr rl rr of MinView km m r' -> balanceL km m l r'

delta :: Int
delta = 3

ratio :: Int
ratio = 2

balance :: k -> a -> Map k a -> Map k a -> Map k a
balance k x l r = case l of
  Tip -> case r of
    Tip -> Bin 1 k x Tip Tip
    (Bin _ _ _ Tip Tip) -> Bin 2 k x Tip r
    (Bin _ rk rx Tip rr@(Bin _ _ _ _ _)) -> Bin 3 rk rx (Bin 1 k x Tip Tip) rr
    (Bin _ rk rx (Bin _ rlk rlx _ _) Tip) -> Bin 3 rlk rlx (Bin 1 k x Tip Tip) (Bin 1 rk rx Tip Tip)
    (Bin rs rk rx rl@(Bin rls rlk rlx rll rlr) rr@(Bin rrs _ _ _ _))
      | rls < ratio * rrs -> Bin (1 + rs) rk rx (Bin (1 + rls) k x Tip rl) rr
      | otherwise -> Bin (1 + rs) rlk rlx (Bin (1 + size rll) k x Tip rll) (Bin (1 + rrs + size rlr) rk rx rlr rr)
  (Bin ls lk lx ll lr) -> case r of
    Tip -> case (ll, lr) of
      (Tip, Tip) -> Bin 2 k x l Tip
      (Tip, (Bin _ lrk lrx _ _)) -> Bin 3 lrk lrx (Bin 1 lk lx Tip Tip) (Bin 1 k x Tip Tip)
      ((Bin _ _ _ _ _), Tip) -> Bin 3 lk lx ll (Bin 1 k x Tip Tip)
      ((Bin lls _ _ _ _), (Bin lrs lrk lrx lrl lrr))
        | lrs < ratio * lls -> Bin (1 + ls) lk lx ll (Bin (1 + lrs) k x lr Tip)
        | otherwise -> Bin (1 + ls) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl) (Bin (1 + size lrr) k x lrr Tip)
    (Bin rs rk rx rl rr)
      | rs > delta * ls -> case (rl, rr) of
          (Bin rls rlk rlx rll rlr, Bin rrs _ _ _ _)
            | rls < ratio * rrs -> Bin (1 + ls + rs) rk rx (Bin (1 + ls + rls) k x l rl) rr
            | otherwise -> Bin (1 + ls + rs) rlk rlx (Bin (1 + ls + size rll) k x l rll) (Bin (1 + rrs + size rlr) rk rx rlr rr)
          (_, _) -> error "Failure in Data.Map.balance"
      | ls > delta * rs -> case (ll, lr) of
          (Bin lls _ _ _ _, Bin lrs lrk lrx lrl lrr)
            | lrs < ratio * lls -> Bin (1 + ls + rs) lk lx ll (Bin (1 + rs + lrs) k x lr r)
            | otherwise -> Bin (1 + ls + rs) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl) (Bin (1 + rs + size lrr) k x lrr r)
          (_, _) -> error "Failure in Data.Map.balance"
      | otherwise -> Bin (1 + ls + rs) k x l r

balanceL :: k -> a -> Map k a -> Map k a -> Map k a
balanceL k x l r = case r of
  Tip -> case l of
    Tip -> Bin 1 k x Tip Tip
    (Bin _ _ _ Tip Tip) -> Bin 2 k x l Tip
    (Bin _ lk lx Tip (Bin _ lrk lrx _ _)) -> Bin 3 lrk lrx (Bin 1 lk lx Tip Tip) (Bin 1 k x Tip Tip)
    (Bin _ lk lx ll@(Bin _ _ _ _ _) Tip) -> Bin 3 lk lx ll (Bin 1 k x Tip Tip)
    (Bin ls lk lx ll@(Bin lls _ _ _ _) lr@(Bin lrs lrk lrx lrl lrr))
      | lrs < ratio * lls -> Bin (1 + ls) lk lx ll (Bin (1 + lrs) k x lr Tip)
      | otherwise -> Bin (1 + ls) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl) (Bin (1 + size lrr) k x lrr Tip)
  (Bin rs _ _ _ _) -> case l of
    Tip -> Bin (1 + rs) k x Tip r
    (Bin ls lk lx ll lr)
      | ls > delta * rs -> case (ll, lr) of
          (Bin lls _ _ _ _, Bin lrs lrk lrx lrl lrr)
            | lrs < ratio * lls -> Bin (1 + ls + rs) lk lx ll (Bin (1 + rs + lrs) k x lr r)
            | otherwise -> Bin (1 + ls + rs) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl) (Bin (1 + rs + size lrr) k x lrr r)
          (_, _) -> error "Failure in Data.Map.balanceL"
      | otherwise -> Bin (1 + ls + rs) k x l r

balanceR :: k -> a -> Map k a -> Map k a -> Map k a
balanceR k x l r = case l of
  Tip -> case r of
    Tip -> Bin 1 k x Tip Tip
    (Bin _ _ _ Tip Tip) -> Bin 2 k x Tip r
    (Bin _ rk rx Tip rr@(Bin _ _ _ _ _)) -> Bin 3 rk rx (Bin 1 k x Tip Tip) rr
    (Bin _ rk rx (Bin _ rlk rlx _ _) Tip) -> Bin 3 rlk rlx (Bin 1 k x Tip Tip) (Bin 1 rk rx Tip Tip)
    (Bin rs rk rx rl@(Bin rls rlk rlx rll rlr) rr@(Bin rrs _ _ _ _))
      | rls < ratio * rrs -> Bin (1 + rs) rk rx (Bin (1 + rls) k x Tip rl) rr
      | otherwise -> Bin (1 + rs) rlk rlx (Bin (1 + size rll) k x Tip rll) (Bin (1 + rrs + size rlr) rk rx rlr rr)
  (Bin ls _ _ _ _) -> case r of
    Tip -> Bin (1 + ls) k x l Tip
    (Bin rs rk rx rl rr)
      | rs > delta * ls -> case (rl, rr) of
          (Bin rls rlk rlx rll rlr, Bin rrs _ _ _ _)
            | rls < ratio * rrs -> Bin (1 + ls + rs) rk rx (Bin (1 + ls + rls) k x l rl) rr
            | otherwise -> Bin (1 + ls + rs) rlk rlx (Bin (1 + ls + size rll) k x l rll) (Bin (1 + rrs + size rlr) rk rx rlr rr)
          (_, _) -> error "Failure in Data.Map.balanceR"
      | otherwise -> Bin (1 + ls + rs) k x l r

bin :: k -> a -> Map k a -> Map k a -> Map k a
bin k x l r = Bin (size l + size r + 1) k x l r
