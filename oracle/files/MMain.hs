module MMain where
import MLib
main :: IO ()
main = print (pub 3 + undefinedName)
