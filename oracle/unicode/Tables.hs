-- Prints GHC's Unicode tables as runs, for tools/gen_unicode.rb.
--   C start cat         general category runs (cat = fromEnum)
--   U/L/T start n step delta   case mapping runs: toUpper/toLower/toTitle
--   P start end         isUpperCase ranges;  Q start end  isLowerCase ranges
import Data.Char

cps :: [Int]
cps = [0 .. 0x10FFFF]

cats :: [String]
cats = go (-1) cps
  where
    go _ [] = []
    go prev (c:cs) = let k = fromEnum (generalCategory (chr c))
                     in if k == prev then go prev cs else ("C " ++ show c ++ " " ++ show k) : go k cs

-- Maximal runs of code points with the same delta, spaced by 1 or 2.
mapping :: String -> (Char -> Char) -> [String]
mapping tag f = runs [ (c, ord (f (chr c)) - c) | c <- cps, ord (f (chr c)) /= c ]
  where
    runs [] = []
    runs ((c, d):rest) = case rest of
      ((c2, d2):_) | d2 == d && (c2 - c == 1 || c2 - c == 2) ->
        let step = c2 - c
            (n, rest') = extend step (c, d) rest 1
        in emit c n step d : runs rest'
      _ -> emit c 1 1 d : runs rest
    extend step (c, d) ((c2, d2):more) n | d2 == d && c2 - c == step = extend step (c2, d) more (n + 1)
    extend _ _ more n = (n, more)
    emit c n step d = unwords [tag, show c, show n, show step, show d]

ranges :: String -> (Char -> Bool) -> [String]
ranges tag p = go cps
  where
    go [] = []
    go (c:cs) | p (chr c) = let (inn, rest) = span (p . chr) cs
                                end = if null inn then c else last inn
                            in unwords [tag, show c, show end] : go rest
              | otherwise = go cs

main :: IO ()
main = mapM_ putStrLn (cats ++ mapping "U" toUpper ++ mapping "L" toLower ++ mapping "T" toTitle
                       ++ ranges "P" isUpperCase ++ ranges "Q" isLowerCase)
