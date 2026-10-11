module AmbA (f, g, T(..)) where

f :: Int -> Int
f = (+ 1)

g :: Int
g = 1

data T = T Int deriving Show
