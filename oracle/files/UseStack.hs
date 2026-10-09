module UseStack where

import Data.Stack

s3 = push 3 (push 2 (push 1 empty))
top = fmap fst (pop s3)
