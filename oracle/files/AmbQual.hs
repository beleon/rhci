module AmbQual where

import qualified AmbA
import AmbA hiding (f)

f :: Int -> Int
f = (* 2)

h :: (Int, Int)
h = (f 3, AmbA.f 3)
