module Main where

import Geometry
import Data.List (sortOn)

shapes :: [Shape]
shapes = [Rect 2 3, Circle 1, Rect 1 1]

main :: IO ()
main = do
  mapM_ (print . area) (sortOn area shapes)
  print (map perimeter shapes)
