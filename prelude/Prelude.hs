-- The rhci Prelude, plus the non-clashing parts of the base modules that
-- rhci puts in scope by default (Data.Maybe, Data.Either, Data.Tuple,
-- Data.Function, Data.List).
--
-- Definitions follow GHC's base wherever the semantics are observable
-- (laziness, which argument is forced first, error messages).
--
-- Build step 4: only what needs no type classes. Anything Foldable-,
-- Num-, Eq- or Show-based arrives with classes in step 5, rather than
-- appearing here with a type GHC would not give it.
--
-- Names starting with rhci_ are internal: the Prelude and the desugarer
-- use them, user code cannot see them.
module Prelude where

data Bool = False | True
data Ordering = LT | EQ | GT
data Maybe a = Nothing | Just a
data Either a b = Left a | Right b

-- IO a is a function of a dummy world token; IORes sequences effects.
data IORes a = IORes a
newtype IO a = IO (() -> IORes a)

type String = [Char]

infixr 9 .
infixr 5 ++
infixr 3 &&
infixr 2 ||
infixl 1 &
infixr 0 $, $!, `seq`
infixl 0 `on`

foreign import prim "seq" seq :: a -> b -> b
foreign import prim "raise" rhci_raise :: [Char] -> a
foreign import prim "putChar" rhci_putChar :: Char -> ()
foreign import prim "isSpace" rhci_isSpace :: Char -> Bool
foreign import prim "charEq" rhci_charEq :: Char -> Char -> Bool

-- ---- errors -------------------------------------------------------------

error :: [Char] -> a
error s = rhci_raise s

errorWithoutStackTrace :: [Char] -> a
errorWithoutStackTrace s = rhci_raise s

undefined :: a
undefined = rhci_raise "Prelude.undefined"

-- ---- functions ----------------------------------------------------------

id :: a -> a
id x = x

const :: a -> b -> a
const x _ = x

flip :: (a -> b -> c) -> b -> a -> c
flip f x y = f y x

(.) :: (b -> c) -> (a -> b) -> a -> c
(.) f g = \x -> f (g x)

($) :: (a -> b) -> a -> b
f $ x = f x

($!) :: (a -> b) -> a -> b
f $! x = x `seq` f x

(&) :: a -> (a -> b) -> b
x & f = f x

on :: (b -> b -> c) -> (a -> b) -> a -> a -> c
(.*.) `on` f = \x y -> f x .*. f y

fix :: (a -> a) -> a
fix f = let x = f x in x

asTypeOf :: a -> a -> a
asTypeOf = const

until :: (a -> Bool) -> (a -> a) -> a -> a
until p f = go
  where
    go x | p x = x
         | otherwise = go (f x)

-- ---- Bool -----------------------------------------------------------------

otherwise :: Bool
otherwise = True

not :: Bool -> Bool
not True = False
not False = True

(&&) :: Bool -> Bool -> Bool
True && x = x
False && _ = False

(||) :: Bool -> Bool -> Bool
True || _ = True
False || x = x

bool :: a -> a -> Bool -> a
bool f _ False = f
bool _ t True = t

-- ---- tuples ---------------------------------------------------------------

fst :: (a, b) -> a
fst (x, _) = x

snd :: (a, b) -> b
snd (_, y) = y

curry :: ((a, b) -> c) -> a -> b -> c
curry f x y = f (x, y)

uncurry :: (a -> b -> c) -> (a, b) -> c
uncurry f p = f (fst p) (snd p)

swap :: (a, b) -> (b, a)
swap (a, b) = (b, a)

-- ---- Maybe and Either -------------------------------------------------------

maybe :: b -> (a -> b) -> Maybe a -> b
maybe n _ Nothing = n
maybe _ f (Just x) = f x

fromMaybe :: a -> Maybe a -> a
fromMaybe d x = case x of { Nothing -> d; Just v -> v }

isJust :: Maybe a -> Bool
isJust Nothing = False
isJust _ = True

isNothing :: Maybe a -> Bool
isNothing Nothing = True
isNothing _ = False

fromJust :: Maybe a -> a
fromJust Nothing = errorWithoutStackTrace "Maybe.fromJust: Nothing"
fromJust (Just x) = x

maybeToList :: Maybe a -> [a]
maybeToList Nothing = []
maybeToList (Just x) = [x]

listToMaybe :: [a] -> Maybe a
listToMaybe [] = Nothing
listToMaybe (a:_) = Just a

catMaybes :: [Maybe a] -> [a]
catMaybes ls = [x | Just x <- ls]

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe _ [] = []
mapMaybe f (x:xs) =
  let rs = mapMaybe f xs in
  case f x of
    Nothing -> rs
    Just r -> r : rs

either :: (a -> c) -> (b -> c) -> Either a b -> c
either f _ (Left x) = f x
either _ g (Right y) = g y

lefts :: [Either a b] -> [a]
lefts x = [a | Left a <- x]

rights :: [Either a b] -> [b]
rights x = [a | Right a <- x]

partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers = rhci_foldr (either left right) ([], [])
  where
    left a ~(l, r) = (a : l, r)
    right a ~(l, r) = (l, a : r)

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

isRight :: Either a b -> Bool
isRight (Left _) = False
isRight (Right _) = True

fromLeft :: a -> Either a b -> a
fromLeft _ (Left a) = a
fromLeft a _ = a

fromRight :: b -> Either a b -> b
fromRight _ (Right b) = b
fromRight b _ = b

-- ---- lists ----------------------------------------------------------------

rhci_foldr :: (a -> b -> b) -> b -> [a] -> b
rhci_foldr k z = go
  where
    go [] = z
    go (y:ys) = y `k` go ys

rhci_concatMap :: (a -> [b]) -> [a] -> [b]
rhci_concatMap f = rhci_foldr ((++) . f) []

map :: (a -> b) -> [a] -> [b]
map _ [] = []
map f (x:xs) = f x : map f xs

(++) :: [a] -> [a] -> [a]
(++) [] ys = ys
(++) (x:xs) ys = x : xs ++ ys

filter :: (a -> Bool) -> [a] -> [a]
filter _ [] = []
filter p (x:xs)
  | p x = x : filter p xs
  | otherwise = filter p xs

head :: [a] -> a
head (x:_) = x
head [] = errorWithoutStackTrace "Prelude.head: empty list"

last :: [a] -> a
last [x] = x
last (_:xs) = last xs
last [] = errorWithoutStackTrace "Prelude.last: empty list"

tail :: [a] -> [a]
tail (_:xs) = xs
tail [] = errorWithoutStackTrace "Prelude.tail: empty list"

init :: [a] -> [a]
init [x] = []
init (x:xs) = x : init xs
init [] = errorWithoutStackTrace "Prelude.init: empty list"

uncons :: [a] -> Maybe (a, [a])
uncons [] = Nothing
uncons (x:xs) = Just (x, xs)

reverse :: [a] -> [a]
reverse l = rev l []
  where
    rev [] a = a
    rev (x:xs) a = rev xs (x : a)

iterate :: (a -> a) -> a -> [a]
iterate f x = x : iterate f (f x)

repeat :: a -> [a]
repeat x = xs where xs = x : xs

cycle :: [a] -> [a]
cycle [] = errorWithoutStackTrace "Prelude.cycle: empty list"
cycle xs = xs' where xs' = xs ++ xs'

takeWhile :: (a -> Bool) -> [a] -> [a]
takeWhile _ [] = []
takeWhile p (x:xs)
  | p x = x : takeWhile p xs
  | otherwise = []

dropWhile :: (a -> Bool) -> [a] -> [a]
dropWhile _ [] = []
dropWhile p xs@(x:xs')
  | p x = dropWhile p xs'
  | otherwise = xs

span :: (a -> Bool) -> [a] -> ([a], [a])
span _ xs@[] = (xs, xs)
span p xs@(x:xs')
  | p x = let (ys, zs) = span p xs' in (x : ys, zs)
  | otherwise = ([], xs)

break :: (a -> Bool) -> [a] -> ([a], [a])
break p = span (not . p)

zip :: [a] -> [b] -> [(a, b)]
zip [] _ = []
zip _ [] = []
zip (a:as) (b:bs) = (a, b) : zip as bs

zip3 :: [a] -> [b] -> [c] -> [(a, b, c)]
zip3 (a:as) (b:bs) (c:cs) = (a, b, c) : zip3 as bs cs
zip3 _ _ _ = []

zipWith :: (a -> b -> c) -> [a] -> [b] -> [c]
zipWith f = go
  where
    go [] _ = []
    go _ [] = []
    go (x:xs) (y:ys) = f x y : go xs ys

zipWith3 :: (a -> b -> c -> d) -> [a] -> [b] -> [c] -> [d]
zipWith3 z = go
  where
    go (a:as) (b:bs) (c:cs) = z a b c : go as bs cs
    go _ _ _ = []

unzip :: [(a, b)] -> ([a], [b])
unzip = rhci_foldr (\(a, b) ~(as, bs) -> (a : as, b : bs)) ([], [])

unzip3 :: [(a, b, c)] -> ([a], [b], [c])
unzip3 = rhci_foldr (\(a, b, c) ~(as, bs, cs) -> (a : as, b : bs, c : cs)) ([], [], [])

scanl :: (b -> a -> b) -> b -> [a] -> [b]
scanl f q ls = q : (case ls of
                      [] -> []
                      x:xs -> scanl f (f q x) xs)

scanr :: (a -> b -> b) -> b -> [a] -> [b]
scanr _ q0 [] = [q0]
scanr f q0 (x:xs) = case scanr f q0 xs of
  qs@(q:_) -> f x q : qs

intersperse :: a -> [a] -> [a]
intersperse _ [] = []
intersperse sep (x:xs) = x : prependToAll sep xs
  where
    prependToAll _ [] = []
    prependToAll s (y:ys) = s : y : prependToAll s ys

intercalate :: [a] -> [[a]] -> [a]
intercalate xs xss = rhci_concatMap id (intersperse xs xss)

transpose :: [[a]] -> [[a]]
transpose [] = []
transpose ([] : xss) = transpose xss
transpose ((x : xs) : xss) = combine x hds xs tls
  where
    (hds, tls) = unzip [(hd, tl) | hd : tl <- xss]
    combine y h ys t = (y : h) : transpose (ys : t)

subsequences :: [a] -> [[a]]
subsequences xs = [] : nonEmptySubsequences xs

nonEmptySubsequences :: [a] -> [[a]]
nonEmptySubsequences [] = []
nonEmptySubsequences (x:xs) = [x] : rhci_foldr f [] (nonEmptySubsequences xs)
  where
    f ys r = ys : (x : ys) : r

-- ---- strings -----------------------------------------------------------------

lines :: String -> [String]
lines "" = []
lines s = cons (case break (rhci_charEq '\n') s of
                  (l, s') -> (l, case s' of
                                   [] -> []
                                   _:s'' -> lines s''))
  where
    cons ~(h, t) = h : t

unlines :: [String] -> String
unlines [] = []
unlines (l:ls) = l ++ '\n' : unlines ls

words :: String -> [String]
words s = case dropWhile rhci_isSpace s of
  "" -> []
  s' -> w : words s''
    where (w, s'') = break rhci_isSpace s'

unwords :: [String] -> String
unwords [] = ""
unwords ws = foldr1 (\w s -> w ++ ' ' : s) ws
  where
    foldr1 f = go
      where
        go [x] = x
        go (x:xs) = f x (go xs)

-- ---- IO -------------------------------------------------------------------------

rhci_unIO :: IO a -> () -> IORes a
rhci_unIO (IO m) = m

rhci_returnIO :: a -> IO a
rhci_returnIO x = IO (\_ -> IORes x)

rhci_bindIO :: IO a -> (a -> IO b) -> IO b
rhci_bindIO (IO m) k = IO (\w -> case m w of IORes a -> rhci_unIO (k a) w)

rhci_thenIO :: IO a -> IO b -> IO b
rhci_thenIO a b = rhci_bindIO a (\_ -> b)

putChar :: Char -> IO ()
putChar c = IO (\_ -> case rhci_putChar c of () -> IORes ())

putStr :: String -> IO ()
putStr [] = rhci_returnIO ()
putStr (c:cs) = putChar c `rhci_thenIO` putStr cs

putStrLn :: String -> IO ()
putStrLn s = putStr s `rhci_thenIO` putChar '\n'
