-- Reference outputs for rhci's numeric primitives (see README.md).
-- One input line per case; one output line per case.
import Data.Ratio ((%))
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Numeric (showHex)
import System.IO

main :: IO ()
main = do
  hSetBuffering stdout (BlockBuffering Nothing)
  ls <- lines <$> getContents
  mapM_ (putStrLn . run . words) ls

dbl :: String -> Double
dbl h = castWord64ToDouble (read ("0x" ++ h))

hex :: Double -> String
hex x = showHex (castDoubleToWord64 x) ""

run :: [String] -> String
run ["show", h] = show (dbl h)
run ["decode", h] = show (decodeFloat (dbl h))
run ["trunc", h] =
  let x = dbl h
   in show (truncate x :: Integer, floor x :: Integer, ceiling x :: Integer, round x :: Integer)
run ["fromInteger", n] = hex (fromInteger (read n))
run ["fromRational", n, d] = hex (fromRational (read n % read d))
run ["read", s] = hex (read s)
run ["int", op, a, b] = show (intOp op (read a) (read b))
run other = error ("bad case: " ++ unwords other)

intOp :: String -> Int -> Int -> Int
intOp "+" = (+)
intOp "-" = (-)
intOp "*" = (*)
intOp "quot" = quot
intOp "rem" = rem
intOp "div" = div
intOp "mod" = mod
intOp "negate" = \a _ -> negate a
intOp "abs" = \a _ -> abs a
intOp "fromInteger" = \a _ -> a
intOp op = error ("bad op " ++ op)
