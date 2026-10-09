module Geometry (Shape(..), area, perimeter, scale) where

data Shape = Circle Double | Rect Double Double deriving (Show, Eq)

area :: Shape -> Double
area (Circle r) = pi * r * r
area (Rect w h) = w * h

perimeter :: Shape -> Double
perimeter (Circle r) = 2 * pi * r
perimeter (Rect w h) = 2 * (w + h)

scale :: Double -> Shape -> Shape
scale k (Circle r) = Circle (k * r)
scale k (Rect w h) = Rect (k * w) (k * h)

helper :: Int
helper = 42
