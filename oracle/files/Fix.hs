module Fix where

data T = Int :| String | E deriving Show
infixr 5 :|

v :: T
v = (-3) :| "x"

w :: [T]
w = [E, 4 :| "y", (-1) :| ""]
