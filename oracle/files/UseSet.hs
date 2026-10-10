module UseSet where

import Data.List (sort)
import MySet (insert, member, toList, empty)

built :: [Int]
built = toList (insert 3 (insert 1 (insert 2 empty)))

sorted :: [Int]
sorted = sort [3, 1, 2]

check :: Bool
check = member 2 (insert 2 empty)
