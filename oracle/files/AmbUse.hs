module AmbUse where

import AmbA

f :: Int -> Int
f = (* 2)

h :: Int
h = f 3
