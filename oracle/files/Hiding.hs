module Hiding where

import Prelude hiding (lookup)

lookup :: Int -> String
lookup 1 = "one"
lookup _ = "other"

test = lookup 1
