module MySet (Set, empty, insert, member, toList) where

import Data.List (sort, nub)

newtype Set a = Set [a]

empty :: Set a
empty = Set []

insert :: Ord a => a -> Set a -> Set a
insert x (Set xs) = Set (sort (nub (x : xs)))

member :: Eq a => a -> Set a -> Bool
member x (Set xs) = x `elem` xs

toList :: Set a -> [a]
toList (Set xs) = xs
