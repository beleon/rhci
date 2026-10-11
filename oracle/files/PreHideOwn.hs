module PreHideOwn where
import Prelude hiding (lookup)
lookup :: Int -> Int
lookup x = x + 1
twice = lookup . lookup
