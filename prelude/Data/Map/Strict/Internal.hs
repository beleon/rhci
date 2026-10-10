-- Data.Map.Strict's value-strict functions, ported from containers-0.6.7
-- (Data.Map.Strict.Internal). Data.Map.Strict is these definitions plus
-- the rest of Data.Map.Internal (the same Map type). Strictness is
-- containers', case by case: e.g. insert forces the value only when it
-- adds a key, as the original does.
module Data.Map.Strict.Internal where

import Prelude hiding (lookup, map, filter, foldr, foldl, null, splitAt, take, drop)
import qualified Data.Foldable as Foldable
import qualified Data.Set.Internal as Set
import Control.Applicative (liftA3)
import Data.Map.Internal (Map(..), balance, balanceL, balanceR, link, link2, glue, size, splitLookup, insertMax,
                          empty, foldrWithKey)

findWithDefault :: Ord k => a -> k -> Map k a -> a
findWithDefault def !k = go
  where
    go Tip = def
    go (Bin _ kx x l r) = case compare k kx of
      LT -> go l
      GT -> go r
      EQ -> x

singleton :: k -> a -> Map k a
singleton k !x = Bin 1 k x Tip Tip

insert :: Ord k => k -> a -> Map k a -> Map k a
insert = go
  where
    go !kx !x Tip = singleton kx x
    go kx x (Bin sz ky y l r) = case compare kx ky of
      LT -> balanceL ky y (go kx x l) r
      GT -> balanceR ky y l (go kx x r)
      EQ -> Bin sz kx x l r

insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWith = go
  where
    go _ !kx x Tip = singleton kx x
    go f !kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> let y' = f x y in y' `seq` Bin sy kx y' l r

insertWithR :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithR = go
  where
    go _ !kx x Tip = singleton kx x
    go f !kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> let y' = f y x in y' `seq` Bin sy ky y' l r

insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKey = go
  where
    go _ !kx x Tip = singleton kx x
    go f kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> let x' = f kx x y in x' `seq` Bin sy kx x' l r

insertWithKeyR :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKeyR = go
  where
    go _ !kx x Tip = singleton kx x
    go f kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> balanceL ky y (go f kx x l) r
      GT -> balanceR ky y l (go f kx x r)
      EQ -> let y' = f ky y x in y' `seq` Bin sy ky y' l r

insertLookupWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> (Maybe a, Map k a)
insertLookupWithKey f0 kx0 x0 t0 = go f0 kx0 x0 t0
  where
    go _ !kx x Tip = (Nothing, singleton kx x)
    go f kx x (Bin sy ky y l r) = case compare kx ky of
      LT -> case go f kx x l of
        (found, l') -> let t' = balanceL ky y l' r in t' `seq` (found, t')
      GT -> case go f kx x r of
        (found, r') -> let t' = balanceR ky y l r' in t' `seq` (found, t')
      EQ -> let x' = f kx x y in x' `seq` (Just y, Bin sy kx x' l r)

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a
adjust f = adjustWithKey (\_ x -> f x)

adjustWithKey :: Ord k => (k -> a -> a) -> k -> Map k a -> Map k a
adjustWithKey = go
  where
    go _ !k Tip = Tip
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> Bin sx kx x (go f k l) r
      GT -> Bin sx kx x l (go f k r)
      EQ -> let x' = f kx x in x' `seq` Bin sx kx x' l r

update :: Ord k => (a -> Maybe a) -> k -> Map k a -> Map k a
update f = updateWithKey (\_ x -> f x)

updateWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a -> Map k a
updateWithKey = go
  where
    go _ !k Tip = Tip
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> balanceR kx x (go f k l) r
      GT -> balanceL kx x l (go f k r)
      EQ -> case f kx x of
        Just x' -> x' `seq` Bin sx kx x' l r
        Nothing -> glue l r

updateLookupWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a -> (Maybe a, Map k a)
updateLookupWithKey f0 k0 t0 = go f0 k0 t0
  where
    go _ !k Tip = (Nothing, Tip)
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> case go f k l of
        (found, l') -> let t' = balanceR kx x l' r in t' `seq` (found, t')
      GT -> case go f k r of
        (found, r') -> let t' = balanceL kx x l r' in t' `seq` (found, t')
      EQ -> case f kx x of
        Just x' -> x' `seq` (Just x', Bin sx kx x' l r)
        Nothing -> let g = glue l r in g `seq` (Just x, g)

alter :: Ord k => (Maybe a -> Maybe a) -> k -> Map k a -> Map k a
alter = go
  where
    go f !k Tip = case f Nothing of
      Nothing -> Tip
      Just x -> singleton k x
    go f k (Bin sx kx x l r) = case compare k kx of
      LT -> balance kx x (go f k l) r
      GT -> balance kx x l (go f k r)
      EQ -> case f (Just x) of
        Just x' -> x' `seq` Bin sx kx x' l r
        Nothing -> glue l r

alterF :: (Functor f, Ord k) => (Maybe a -> f (Maybe a)) -> k -> Map k a -> f (Map k a)
alterF f !k m = fmap choose (f mv)
  where
    mv = lookupL k m
    choose Nothing = case mv of
      Nothing -> m
      Just _ -> deleteL k m
    choose (Just new) = new `seq` case mv of
      Nothing -> insert k new m
      Just _ -> replaceL k new m

lookupL :: Ord k => k -> Map k a -> Maybe a
lookupL !k Tip = Nothing
lookupL k (Bin _ kx x l r) = case compare k kx of
  LT -> lookupL k l
  GT -> lookupL k r
  EQ -> Just x

deleteL :: Ord k => k -> Map k a -> Map k a
deleteL !k Tip = Tip
deleteL k (Bin _ kx x l r) = case compare k kx of
  LT -> balanceR kx x (deleteL k l) r
  GT -> balanceL kx x l (deleteL k r)
  EQ -> glue l r

replaceL :: Ord k => k -> a -> Map k a -> Map k a
replaceL _ _ Tip = Tip
replaceL k x (Bin sz ky y l r) = case compare k ky of
  LT -> Bin sz ky y (replaceL k x l) r
  GT -> Bin sz ky y l (replaceL k x r)
  EQ -> Bin sz ky x l r

updateAt :: (k -> a -> Maybe a) -> Int -> Map k a -> Map k a
updateAt f !i t = case t of
  Tip -> error "Map.updateAt: index out of range"
  Bin sx kx x l r -> let sizeL = size l in case compare i sizeL of
    LT -> balanceR kx x (updateAt f i l) r
    GT -> balanceL kx x l (updateAt f (i - sizeL - 1) r)
    EQ -> case f kx x of
      Just x' -> x' `seq` Bin sx kx x' l r
      Nothing -> glue l r

updateMin :: (a -> Maybe a) -> Map k a -> Map k a
updateMin f m = updateMinWithKey (\_ x -> f x) m

updateMax :: (a -> Maybe a) -> Map k a -> Map k a
updateMax f m = updateMaxWithKey (\_ x -> f x) m

updateMinWithKey :: (k -> a -> Maybe a) -> Map k a -> Map k a
updateMinWithKey _ Tip = Tip
updateMinWithKey f (Bin sx kx x Tip r) = case f kx x of
  Nothing -> r
  Just x' -> x' `seq` Bin sx kx x' Tip r
updateMinWithKey f (Bin _ kx x l r) = balanceR kx x (updateMinWithKey f l) r

updateMaxWithKey :: (k -> a -> Maybe a) -> Map k a -> Map k a
updateMaxWithKey _ Tip = Tip
updateMaxWithKey f (Bin sx kx x l Tip) = case f kx x of
  Nothing -> l
  Just x' -> x' `seq` Bin sx kx x' l Tip
updateMaxWithKey f (Bin _ kx x l r) = balanceL kx x l (updateMaxWithKey f r)

unionsWith :: (Foldable f, Ord k) => (a -> a -> a) -> f (Map k a) -> Map k a
unionsWith f ts = Foldable.foldl' (unionWith f) empty ts

unionWith :: Ord k => (a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWith _ t1 Tip = t1
unionWith f t1 (Bin _ k x Tip Tip) = insertWithR f k x t1
unionWith f (Bin _ k x Tip Tip) t2 = insertWith f k x t2
unionWith _ Tip t2 = t2
unionWith f (Bin _ k1 x1 l1 r1) t2 = case splitLookup k1 t2 of
  (l2, mb, r2) -> let x1' = maybe x1 (f x1) mb
                  in x1' `seq` link k1 x1' (unionWith f l1 l2) (unionWith f r1 r2)

unionWithKey :: Ord k => (k -> a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWithKey _ t1 Tip = t1
unionWithKey f t1 (Bin _ k x Tip Tip) = insertWithKeyR f k x t1
unionWithKey f (Bin _ k x Tip Tip) t2 = insertWithKey f k x t2
unionWithKey _ Tip t2 = t2
unionWithKey f (Bin _ k1 x1 l1 r1) t2 = case splitLookup k1 t2 of
  (l2, mb, r2) -> let x1' = maybe x1 (f k1 x1) mb
                  in x1' `seq` link k1 x1' (unionWithKey f l1 l2) (unionWithKey f r1 r2)

differenceWith :: Ord k => (a -> b -> Maybe a) -> Map k a -> Map k b -> Map k a
differenceWith f = differenceWithKey (\_ x y -> f x y)

-- containers builds this with its (strict) merge tactics, which force
-- every value the function returns.
differenceWithKey :: Ord k => (k -> a -> b -> Maybe a) -> Map k a -> Map k b -> Map k a
differenceWithKey f = mergeWithKey (\k x y -> case f k x y of
                                       Nothing -> Nothing
                                       Just v -> v `seq` Just v) id (const Tip)

intersectionWith :: Ord k => (a -> b -> c) -> Map k a -> Map k b -> Map k c
intersectionWith _ Tip _ = Tip
intersectionWith _ _ Tip = Tip
intersectionWith f (Bin _ k x1 l1 r1) t2 = case splitLookup k t2 of
  (l2, mb, r2) -> let l1l2 = intersectionWith f l1 l2
                      r1r2 = intersectionWith f r1 r2
                  in l1l2 `seq` r1r2 `seq` case mb of
                       Just x2 -> let x1' = f x1 x2 in x1' `seq` link k x1' l1l2 r1r2
                       Nothing -> link2 l1l2 r1r2

intersectionWithKey :: Ord k => (k -> a -> b -> c) -> Map k a -> Map k b -> Map k c
intersectionWithKey _ Tip _ = Tip
intersectionWithKey _ _ Tip = Tip
intersectionWithKey f (Bin _ k x1 l1 r1) t2 = case splitLookup k t2 of
  (l2, mb, r2) -> let l1l2 = intersectionWithKey f l1 l2
                      r1r2 = intersectionWithKey f r1 r2
                  in l1l2 `seq` r1r2 `seq` case mb of
                       Just x2 -> let x1' = f k x1 x2 in x1' `seq` link k x1' l1l2 r1r2
                       Nothing -> link2 l1l2 r1r2

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

mapMaybe :: (a -> Maybe b) -> Map k a -> Map k b
mapMaybe f = mapMaybeWithKey (\_ x -> f x)

mapMaybeWithKey :: (k -> a -> Maybe b) -> Map k a -> Map k b
mapMaybeWithKey _ Tip = Tip
mapMaybeWithKey f (Bin _ kx x l r) = case f kx x of
  Just y -> y `seq` link kx y (mapMaybeWithKey f l) (mapMaybeWithKey f r)
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
          Left y -> y `seq` (let a = link kx y l1 r1
                                 b = link2 l2 r2
                             in a `seq` b `seq` (a, b))
          Right z -> z `seq` (let a = link2 l1 r1
                                  b = link kx z l2 r2
                              in a `seq` b `seq` (a, b))

map :: (a -> b) -> Map k a -> Map k b
map f = go
  where
    go Tip = Tip
    go (Bin sx kx x l r) = let x' = f x in x' `seq` Bin sx kx x' (go l) (go r)

mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey _ Tip = Tip
mapWithKey f (Bin sx kx x l r) =
  let x' = f kx x in x' `seq` Bin sx kx x' (mapWithKey f l) (mapWithKey f r)

traverseWithKey :: Applicative t => (k -> a -> t b) -> Map k a -> t (Map k b)
traverseWithKey f = go
  where
    go Tip = pure Tip
    go (Bin 1 k v _ _) = (\v' -> v' `seq` Bin 1 k v' Tip Tip) <$> f k v
    go (Bin s k v l r) = liftA3 (\l' v' r' -> v' `seq` Bin s k v' l' r') (go l) (f k v) (go r)

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
  in x' `seq` (a3, Bin sx kx x' l' r')

mapAccumRWithKey :: (a -> k -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccumRWithKey _ a Tip = (a, Tip)
mapAccumRWithKey f a (Bin sx kx x l r) =
  let (a1, r') = mapAccumRWithKey f a r
      (a2, x') = f a1 kx x
      (a3, l') = mapAccumRWithKey f a2 l
  in x' `seq` (a3, Bin sx kx x' l' r')

mapKeysWith :: Ord k2 => (a -> a -> a) -> (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeysWith c f = fromListWith c . foldrWithKey (\k x xs -> (f k, x) : xs) []

fromSet :: (k -> a) -> Set.Set k -> Map k a
fromSet _ Set.Tip = Tip
fromSet f (Set.Bin sz x l r) = case f x of v -> v `seq` Bin sz x v (fromSet f l) (fromSet f r)

fromList :: Ord k => [(k, a)] -> Map k a
fromList [] = Tip
fromList [(kx, x)] = x `seq` Bin 1 kx x Tip Tip
fromList ((kx0, x0) : xs0)
  | not_ordered kx0 xs0 = x0 `seq` fromList' (Bin 1 kx0 x0 Tip Tip) xs0
  | otherwise = x0 `seq` go (1 :: Int) (Bin 1 kx0 x0 Tip Tip) xs0
  where
    not_ordered _ [] = False
    not_ordered kx ((ky, _) : _) = kx >= ky
    fromList' t0 xs = Foldable.foldl' ins t0 xs
      where ins t (k, x) = insert k x t
    go !s t [] = t
    go _ t [(kx, x)] = x `seq` insertMax kx x t
    go s l xs@((kx, x) : xss)
      | not_ordered kx xss = fromList' l xs
      | otherwise = case create s xss of
          (r, ys, []) -> x `seq` go (s * 2) (link kx x l r) ys
          (r, _, ys) -> x `seq` fromList' (link kx x l r) ys
    create !s [] = (Tip, [], [])
    create s xs@(xp : xss)
      | s == 1 = case xp of
          (kx, x) | not_ordered kx xss -> x `seq` (Bin 1 kx x Tip Tip, [], xss)
                  | otherwise -> x `seq` (Bin 1 kx x Tip Tip, xss, [])
      | otherwise = case create (s `div` 2) xs of
          res@(_, [], _) -> res
          (l, [(ky, y)], zs) -> y `seq` (insertMax ky y l, [], zs)
          (l, ys@((ky, y) : yss), _)
            | not_ordered ky yss -> (l, [], ys)
            | otherwise -> case create (s `div` 2) yss of
                (r, zs, ws) -> y `seq` (link ky y l r, zs, ws)

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
fromListWith f xs = fromListWithKey (\_ x y -> f x y) xs

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromListWithKey f xs = Foldable.foldl' ins empty xs
  where ins t (k, x) = insertWithKey f k x t

fromAscList :: Eq k => [(k, a)] -> Map k a
fromAscList xs = fromAscListWithKey (\_ x _ -> x) xs

fromAscListWith :: Eq k => (a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWith f xs = fromAscListWithKey (\_ x y -> f x y) xs

fromAscListWithKey :: Eq k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWithKey f xs = fromDistinctAscList (combine xs)
  where
    combine xs' = case xs' of
      [] -> []
      [x] -> [x]
      (x : xx) -> combine' x xx
    combine' z [] = [z]
    combine' z@(kz, zz) (x@(kx, xx) : xs')
      | kx == kz = let yy = f kx xx zz in yy `seq` combine' (kx, yy) xs'
      | otherwise = z : combine' x xs'

fromDistinctAscList :: [(k, a)] -> Map k a
fromDistinctAscList [] = Tip
fromDistinctAscList ((kx0, x0) : xs0) = x0 `seq` go (1 :: Int) (Bin 1 kx0 x0 Tip Tip) xs0
  where
    go !s t [] = t
    go s l ((kx, x) : xs) = case create s xs of
      (r, ys) -> x `seq` (let t' = link kx x l r in t' `seq` go (s * 2) t' ys)
    create !s [] = (Tip, [])
    create s xs@(x' : xs')
      | s == 1 = case x' of (kx, x) -> x `seq` (Bin 1 kx x Tip Tip, xs')
      | otherwise = case create (s `div` 2) xs of
          res@(_, []) -> res
          (l, (ky, y) : ys) -> case create (s `div` 2) ys of
            (r, zs) -> y `seq` (link ky y l r, zs)
