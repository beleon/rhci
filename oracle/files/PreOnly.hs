module PreOnly where
import Prelude (map, Int, (+))
length :: [a] -> Int
length _ = 7
w = length (map (+1) [1,2])
