-- The rhci Prelude, plus the non-clashing parts of the base modules that
-- rhci puts in scope by default (Data.List, Data.Maybe, Data.Char,
-- Data.Either, Data.Tuple, Data.Function, Data.Ord, Control.Monad).
--
-- Definitions are ported from GHC's base wherever behaviour is observable:
-- laziness and evaluation order, error messages, the order of floating-point
-- operations, and Show output.
--
-- Only names that GHC exports (lib/rhci/base_names.rb) become visible to
-- user code. Everything else here is internal, and so are all names
-- starting with rhci_, which derived instances and the desugarer use.
module Prelude where

infixr 9 .
infixr 8 ^, ^^, **
infixl 7 *, /, `quot`, `rem`, `div`, `mod`
infixl 6 +, -
infixr 6 <>
infixr 5 ++
infix 4 ==, /=, <, <=, >=, >, `elem`, `notElem`
infixl 4 <$>, <$, $>, <*>, *>, <*
infixr 3 &&
infixr 2 ||
infixl 1 >>, >>=, &
infixr 1 =<<
infixr 0 $, $!, `seq`
infixl 0 `on`
infixl 9 !!
infix 5 \\
infixl 7 :%

-- ---- primitives -------------------------------------------------------------

foreign import prim "seq" seq :: a -> b -> b
foreign import prim "raise" rhci_raise :: [Char] -> a
foreign import prim "putChar" rhci_putChar :: Char -> ()
foreign import prim "isSpace" rhci_isSpace :: Char -> Bool
foreign import prim "conTag" rhci_conTag :: a -> Int
foreign import prim "chr" rhci_chr :: Int -> Char
foreign import prim "ord" rhci_ord :: Char -> Int

foreign import prim "integerEq" rhci_intEq :: Int -> Int -> Bool
foreign import prim "integerLt" rhci_intLt :: Int -> Int -> Bool
foreign import prim "integerLe" rhci_intLe :: Int -> Int -> Bool
foreign import prim "integerGt" rhci_intGt :: Int -> Int -> Bool
foreign import prim "integerGe" rhci_intGe :: Int -> Int -> Bool
foreign import prim "intAdd" rhci_intAdd :: Int -> Int -> Int
foreign import prim "intSub" rhci_intSub :: Int -> Int -> Int
foreign import prim "intMul" rhci_intMul :: Int -> Int -> Int
foreign import prim "intNegate" rhci_intNegate :: Int -> Int
foreign import prim "intQuot" rhci_intQuot :: Int -> Int -> Int
foreign import prim "intRem" rhci_intRem :: Int -> Int -> Int
foreign import prim "intDiv" rhci_intDiv :: Int -> Int -> Int
foreign import prim "intMod" rhci_intMod :: Int -> Int -> Int
foreign import prim "intToInteger" rhci_intToInteger :: Int -> Integer
foreign import prim "integerShow" rhci_intShow :: Int -> [Char]

foreign import prim "integerEq" rhci_integerEq :: Integer -> Integer -> Bool
foreign import prim "integerLt" rhci_integerLt :: Integer -> Integer -> Bool
foreign import prim "integerLe" rhci_integerLe :: Integer -> Integer -> Bool
foreign import prim "integerGt" rhci_integerGt :: Integer -> Integer -> Bool
foreign import prim "integerGe" rhci_integerGe :: Integer -> Integer -> Bool
foreign import prim "integerAdd" rhci_integerAdd :: Integer -> Integer -> Integer
foreign import prim "integerSub" rhci_integerSub :: Integer -> Integer -> Integer
foreign import prim "integerMul" rhci_integerMul :: Integer -> Integer -> Integer
foreign import prim "integerNegate" rhci_integerNegate :: Integer -> Integer
foreign import prim "integerQuot" rhci_integerQuot :: Integer -> Integer -> Integer
foreign import prim "integerRem" rhci_integerRem :: Integer -> Integer -> Integer
foreign import prim "integerDiv" rhci_integerDiv :: Integer -> Integer -> Integer
foreign import prim "integerMod" rhci_integerMod :: Integer -> Integer -> Integer
foreign import prim "integerToInt" rhci_integerToInt :: Integer -> Int
foreign import prim "integerToDouble" rhci_integerToDouble :: Integer -> Double
foreign import prim "integerShow" rhci_integerShow :: Integer -> [Char]

foreign import prim "doubleEq" rhci_doubleEq :: Double -> Double -> Bool
foreign import prim "doubleLt" rhci_doubleLt :: Double -> Double -> Bool
foreign import prim "doubleLe" rhci_doubleLe :: Double -> Double -> Bool
foreign import prim "doubleGt" rhci_doubleGt :: Double -> Double -> Bool
foreign import prim "doubleGe" rhci_doubleGe :: Double -> Double -> Bool
foreign import prim "doubleAdd" rhci_doubleAdd :: Double -> Double -> Double
foreign import prim "doubleSub" rhci_doubleSub :: Double -> Double -> Double
foreign import prim "doubleMul" rhci_doubleMul :: Double -> Double -> Double
foreign import prim "doubleDiv" rhci_doubleDiv :: Double -> Double -> Double
foreign import prim "doubleNegate" rhci_doubleNegate :: Double -> Double
foreign import prim "doubleAbs" rhci_doubleAbs :: Double -> Double
foreign import prim "doubleSqrt" rhci_doubleSqrt :: Double -> Double
foreign import prim "doubleExp" rhci_doubleExp :: Double -> Double
foreign import prim "doubleLog" rhci_doubleLog :: Double -> Double
foreign import prim "doublePow" rhci_doublePow :: Double -> Double -> Double
foreign import prim "doubleSin" rhci_doubleSin :: Double -> Double
foreign import prim "doubleCos" rhci_doubleCos :: Double -> Double
foreign import prim "doubleTan" rhci_doubleTan :: Double -> Double
foreign import prim "doubleAsin" rhci_doubleAsin :: Double -> Double
foreign import prim "doubleAcos" rhci_doubleAcos :: Double -> Double
foreign import prim "doubleAtan" rhci_doubleAtan :: Double -> Double
foreign import prim "doubleSinh" rhci_doubleSinh :: Double -> Double
foreign import prim "doubleCosh" rhci_doubleCosh :: Double -> Double
foreign import prim "doubleTanh" rhci_doubleTanh :: Double -> Double
foreign import prim "doubleAsinh" rhci_doubleAsinh :: Double -> Double
foreign import prim "doubleAcosh" rhci_doubleAcosh :: Double -> Double
foreign import prim "doubleAtanh" rhci_doubleAtanh :: Double -> Double
foreign import prim "doubleIsNaN" rhci_doubleIsNaN :: Double -> Bool
foreign import prim "doubleIsInfinite" rhci_doubleIsInfinite :: Double -> Bool
foreign import prim "doubleIsNegativeZero" rhci_doubleIsNegativeZero :: Double -> Bool
foreign import prim "doubleDecode" rhci_doubleDecode :: Double -> (Integer, Int)
foreign import prim "doubleEncode" rhci_doubleEncode :: Integer -> Int -> Double
foreign import prim "doubleTruncate" rhci_doubleTruncate :: Double -> Integer
foreign import prim "doubleFloor" rhci_doubleFloor :: Double -> Integer
foreign import prim "doubleCeiling" rhci_doubleCeiling :: Double -> Integer
foreign import prim "doubleRound" rhci_doubleRound :: Double -> Integer
foreign import prim "doubleFromRational" rhci_doubleFromRational :: Integer -> Integer -> Double
foreign import prim "doubleShow" rhci_doubleShow :: Double -> [Char]

-- ---- basic types ----------------------------------------------------------------

data Bool = False | True deriving (Eq, Ord, Enum, Bounded, Show)
data Ordering = LT | EQ | GT deriving (Eq, Ord, Enum, Bounded, Show)
data Maybe a = Nothing | Just a deriving (Eq, Ord, Show)
data Either a b = Left a | Right b deriving (Eq, Ord, Show)

-- IO a is a function of a dummy world token; IORes sequences effects.
data IORes a = IORes a
newtype IO a = IO (() -> IORes a)

type String = [Char]
type ShowS = String -> String

data Ratio a = !a :% !a
type Rational = Ratio Integer

-- ---- errors -----------------------------------------------------------------

error :: [Char] -> a
error s = rhci_raise s

errorWithoutStackTrace :: [Char] -> a
errorWithoutStackTrace s = rhci_raise s

undefined :: a
undefined = rhci_raise "Prelude.undefined"

rhci_error :: [Char] -> a
rhci_error s = rhci_raise s

divZeroError :: a
divZeroError = rhci_raise "divide by zero"

overflowError :: a
overflowError = rhci_raise "arithmetic overflow"

-- ---- functions ----------------------------------------------------------------

id :: a -> a
id x = x

const :: a -> b -> a
const x _ = x

flip :: (a -> b -> c) -> b -> a -> c
flip f x y = f y x

(.) :: (b -> c) -> (a -> b) -> a -> c
(.) f g = \x -> f (g x)

rhci_compose :: (b -> c) -> (a -> b) -> a -> c
rhci_compose f g = \x -> f (g x)

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

applyWhen :: Bool -> (a -> a) -> a -> a
applyWhen True f x = f x
applyWhen False _ x = x

-- ---- Bool -----------------------------------------------------------------------

otherwise :: Bool
otherwise = True

not :: Bool -> Bool
not True = False
not False = True

(&&) :: Bool -> Bool -> Bool
True && x = x
False && _ = False

rhci_and :: Bool -> Bool -> Bool
rhci_and True x = x
rhci_and False _ = False

(||) :: Bool -> Bool -> Bool
True || _ = True
False || x = x

bool :: a -> a -> Bool -> a
bool f _ False = f
bool _ t True = t

-- ---- Eq and Ord -------------------------------------------------------------------

class Eq a where
  (==), (/=) :: a -> a -> Bool
  x /= y = not (x == y)
  x == y = not (x /= y)

class Eq a => Ord a where
  compare :: a -> a -> Ordering
  (<), (<=), (>), (>=) :: a -> a -> Bool
  max, min :: a -> a -> a
  compare x y = if x == y then EQ else if x <= y then LT else GT
  x < y = case compare x y of { LT -> True; _ -> False }
  x <= y = case compare x y of { GT -> False; _ -> True }
  x > y = case compare x y of { GT -> True; _ -> False }
  x >= y = case compare x y of { LT -> False; _ -> True }
  max x y = if x <= y then y else x
  min x y = if x <= y then x else y

rhci_eq :: Eq a => a -> a -> Bool
rhci_eq = (==)

rhci_compare :: Ord a => a -> a -> Ordering
rhci_compare = compare

rhci_thenCmp :: Ordering -> Ordering -> Ordering
rhci_thenCmp EQ o = o
rhci_thenCmp o _ = o

rhci_compareInt :: Int -> Int -> Ordering
rhci_compareInt x y
  | rhci_intLt x y = LT
  | rhci_intEq x y = EQ
  | otherwise = GT

comparing :: Ord a => (b -> a) -> b -> b -> Ordering
comparing p x y = compare (p x) (p y)

clamp :: Ord a => (a, a) -> a -> a
clamp (low, high) a = min high (max a low)

newtype Down a = Down a

getDown :: Down a -> a
getDown (Down a) = a

instance Eq a => Eq (Down a) where
  Down x == Down y = x == y

instance Ord a => Ord (Down a) where
  compare (Down x) (Down y) = compare y x

instance Show a => Show (Down a) where
  showsPrec d (Down x) = showParen (d >= 11) (showString "Down " . showsPrec 11 x)

instance Eq Int where
  (==) = rhci_intEq
  x /= y = not (rhci_intEq x y)

instance Ord Int where
  compare = rhci_compareInt
  (<) = rhci_intLt
  (<=) = rhci_intLe
  (>) = rhci_intGt
  (>=) = rhci_intGe

instance Eq Integer where
  (==) = rhci_integerEq
  x /= y = not (rhci_integerEq x y)

instance Ord Integer where
  compare x y
    | rhci_integerLt x y = LT
    | rhci_integerEq x y = EQ
    | otherwise = GT
  (<) = rhci_integerLt
  (<=) = rhci_integerLe
  (>) = rhci_integerGt
  (>=) = rhci_integerGe

instance Eq Double where
  (==) = rhci_doubleEq
  x /= y = not (rhci_doubleEq x y)

-- GHC's Ord Double: compare is LT/EQ by < and ==, else GT (so NaN gives GT).
instance Ord Double where
  compare x y
    | rhci_doubleLt x y = LT
    | rhci_doubleEq x y = EQ
    | otherwise = GT
  (<) = rhci_doubleLt
  (<=) = rhci_doubleLe
  (>) = rhci_doubleGt
  (>=) = rhci_doubleGe

instance Eq Char where
  c == d = rhci_intEq (rhci_ord c) (rhci_ord d)

instance Ord Char where
  compare c d = rhci_compareInt (rhci_ord c) (rhci_ord d)
  c < d = rhci_intLt (rhci_ord c) (rhci_ord d)
  c <= d = rhci_intLe (rhci_ord c) (rhci_ord d)
  c > d = rhci_intGt (rhci_ord c) (rhci_ord d)
  c >= d = rhci_intGe (rhci_ord c) (rhci_ord d)

instance Eq () where
  () == () = True

instance Ord () where
  compare () () = EQ

instance Eq a => Eq [a] where
  [] == [] = True
  (x:xs) == (y:ys) = x == y && xs == ys
  _ == _ = False

instance Ord a => Ord [a] where
  compare [] [] = EQ
  compare [] (_:_) = LT
  compare (_:_) [] = GT
  compare (x:xs) (y:ys) = case compare x y of
    EQ -> compare xs ys
    other -> other

instance (Eq a, Eq b) => Eq (a, b) where
  (a, b) == (c, d) = a == c && b == d

instance (Ord a, Ord b) => Ord (a, b) where
  compare (a, b) (c, d) = rhci_thenCmp (compare a c) (compare b d)

instance (Eq a, Eq b, Eq c) => Eq (a, b, c) where
  (a, b, c) == (d, e, f) = a == d && b == e && c == f

instance (Ord a, Ord b, Ord c) => Ord (a, b, c) where
  compare (a, b, c) (d, e, f) = rhci_thenCmp (compare a d) (rhci_thenCmp (compare b e) (compare c f))

instance (Eq a, Eq b, Eq c, Eq d) => Eq (a, b, c, d) where
  (a, b, c, d) == (e, f, g, h) = a == e && b == f && c == g && d == h

instance (Ord a, Ord b, Ord c, Ord d) => Ord (a, b, c, d) where
  compare (a, b, c, d) (e, f, g, h) =
    rhci_thenCmp (compare a e) (rhci_thenCmp (compare b f) (rhci_thenCmp (compare c g) (compare d h)))

-- ---- Show -----------------------------------------------------------------------------

class Show a where
  showsPrec :: Int -> a -> ShowS
  show :: a -> String
  showList :: [a] -> ShowS
  showsPrec _ x s = show x ++ s
  show x = shows x ""
  showList ls s = showList__ shows ls s

rhci_showsPrec :: Show a => Int -> a -> ShowS
rhci_showsPrec = showsPrec

shows :: Show a => a -> ShowS
shows = showsPrec 0

showString :: String -> ShowS
showString = (++)

rhci_showString :: String -> ShowS
rhci_showString = (++)

showChar :: Char -> ShowS
showChar = (:)

rhci_showChar :: Char -> ShowS
rhci_showChar = (:)

rhci_showSpace :: ShowS
rhci_showSpace = \xs -> ' ' : xs

showParen :: Bool -> ShowS -> ShowS
showParen b p = if b then showChar '(' . p . showChar ')' else p

rhci_showParen :: Bool -> ShowS -> ShowS
rhci_showParen = showParen

showList__ :: (a -> ShowS) -> [a] -> ShowS
showList__ _ [] s = "[]" ++ s
showList__ showx (x:xs) s = '[' : showx x (showl xs)
  where
    showl [] = ']' : s
    showl (y:ys) = ',' : showx y (showl ys)

rhci_showInt :: Int -> String
rhci_showInt n = rhci_intShow n

instance Show Int where
  showsPrec p n r
    | rhci_intLt n 0 && rhci_intGt p 6 = '(' : rhci_intShow n ++ (')' : r)
    | otherwise = rhci_intShow n ++ r

instance Show Integer where
  showsPrec p n r
    | rhci_integerLt n 0 && rhci_intGt p 6 = '(' : rhci_integerShow n ++ (')' : r)
    | otherwise = rhci_integerShow n ++ r

-- GHC's showSignedFloat: negative numbers and -0.0 are parenthesised.
instance Show Double where
  showsPrec p x
    | rhci_doubleLt x 0.0 || rhci_doubleIsNegativeZero x = showParen (rhci_intGt p 6) (showString (rhci_doubleShow x))
    | otherwise = showString (rhci_doubleShow x)

instance Show () where
  showsPrec _ () = showString "()"

instance Show a => Show [a] where
  showsPrec _ = showList

instance Show Char where
  showsPrec _ '\'' = showString "'\\''"
  showsPrec _ c = showChar '\'' . showLitChar c . showChar '\''
  showList cs = showChar '"' . showLitString cs . showChar '"'

showLitChar :: Char -> ShowS
showLitChar c s
  | rhci_intGt (rhci_ord c) 127 = showChar '\\' (protectEsc isDigit (shows (rhci_ord c)) s)
showLitChar '\DEL' s = showString "\\DEL" s
showLitChar '\\' s = showString "\\\\" s
showLitChar c s
  | rhci_intGe (rhci_ord c) 32 = showChar c s
showLitChar '\a' s = showString "\\a" s
showLitChar '\b' s = showString "\\b" s
showLitChar '\f' s = showString "\\f" s
showLitChar '\n' s = showString "\\n" s
showLitChar '\r' s = showString "\\r" s
showLitChar '\t' s = showString "\\t" s
showLitChar '\v' s = showString "\\v" s
showLitChar '\SO' s = protectEsc (rhci_eqChar 'H') (showString "\\SO") s
showLitChar c s = showString ('\\' : rhci_index asciiTab (rhci_ord c)) s

rhci_eqChar :: Char -> Char -> Bool
rhci_eqChar c d = rhci_intEq (rhci_ord c) (rhci_ord d)

showLitString :: String -> ShowS
showLitString [] s = s
showLitString ('"' : cs) s = showString "\\\"" (showLitString cs s)
showLitString (c : cs) s = showLitChar c (showLitString cs s)

protectEsc :: (Char -> Bool) -> ShowS -> ShowS
protectEsc p f = f . cont
  where
    cont s@(c:_) | p c = "\\&" ++ s
    cont s = s

asciiTab :: [String]
asciiTab = ["NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
            "BS", "HT", "LF", "VT", "FF", "CR", "SO", "SI",
            "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
            "CAN", "EM", "SUB", "ESC", "FS", "GS", "RS", "US",
            "SP"]

rhci_index :: [a] -> Int -> a
rhci_index (x:xs) n = if rhci_intEq n 0 then x else rhci_index xs (rhci_intSub n 1)

show_tuple :: [ShowS] -> ShowS
show_tuple ss = showChar '(' . rhci_foldr1 (\s r -> s . showChar ',' . r) ss . showChar ')'

instance (Show a, Show b) => Show (a, b) where
  showsPrec _ (a, b) s = show_tuple [shows a, shows b] s

instance (Show a, Show b, Show c) => Show (a, b, c) where
  showsPrec _ (a, b, c) s = show_tuple [shows a, shows b, shows c] s

instance (Show a, Show b, Show c, Show d) => Show (a, b, c, d) where
  showsPrec _ (a, b, c, d) s = show_tuple [shows a, shows b, shows c, shows d] s

instance (Show a, Show b, Show c, Show d, Show e) => Show (a, b, c, d, e) where
  showsPrec _ (a, b, c, d, e) s = show_tuple [shows a, shows b, shows c, shows d, shows e] s

-- ---- numbers --------------------------------------------------------------------------

class Num a where
  (+), (-), (*) :: a -> a -> a
  negate, abs, signum :: a -> a
  fromInteger :: Integer -> a
  x - y = x + negate y
  negate x = 0 - x

subtract :: Num a => a -> a -> a
subtract x y = y - x

instance Num Int where
  (+) = rhci_intAdd
  (-) = rhci_intSub
  (*) = rhci_intMul
  negate = rhci_intNegate
  abs n = if rhci_intGe n 0 then n else rhci_intNegate n
  signum n
    | rhci_intLt n 0 = rhci_intNegate 1
    | rhci_intEq n 0 = 0
    | otherwise = 1
  fromInteger = rhci_integerToInt

instance Num Integer where
  (+) = rhci_integerAdd
  (-) = rhci_integerSub
  (*) = rhci_integerMul
  negate = rhci_integerNegate
  abs n = if rhci_integerGe n 0 then n else rhci_integerNegate n
  signum n
    | rhci_integerLt n 0 = rhci_integerNegate 1
    | rhci_integerEq n 0 = 0
    | otherwise = 1
  fromInteger n = n

instance Num Double where
  (+) = rhci_doubleAdd
  (-) = rhci_doubleSub
  (*) = rhci_doubleMul
  negate = rhci_doubleNegate
  abs = rhci_doubleAbs
  signum x
    | rhci_doubleGt x 0.0 = 1.0
    | rhci_doubleLt x 0.0 = rhci_doubleNegate 1.0
    | otherwise = x
  fromInteger = rhci_integerToDouble

class (Num a, Ord a) => Real a where
  toRational :: a -> Rational

class (Real a, Enum a) => Integral a where
  quot, rem, div, mod :: a -> a -> a
  quotRem, divMod :: a -> a -> (a, a)
  toInteger :: a -> Integer
  n `quot` d = fst (quotRem n d)
  n `rem` d = snd (quotRem n d)
  n `div` d = fst (divMod n d)
  n `mod` d = snd (divMod n d)
  divMod n d = if signum r == negate (signum d) then (q - 1, r + d) else qr
    where
      qr@(q, r) = quotRem n d

instance Real Int where
  toRational x = toInteger x :% 1

instance Integral Int where
  toInteger = rhci_intToInteger
  a `quot` b
    | rhci_intEq b 0 = divZeroError
    | rhci_intEq b (rhci_intNegate 1) && rhci_intEq a minBound = overflowError
    | otherwise = rhci_intQuot a b
  a `rem` b
    | rhci_intEq b 0 = divZeroError
    | rhci_intEq b (rhci_intNegate 1) = 0
    | otherwise = rhci_intRem a b
  a `div` b
    | rhci_intEq b 0 = divZeroError
    | rhci_intEq b (rhci_intNegate 1) && rhci_intEq a minBound = overflowError
    | otherwise = rhci_intDiv a b
  a `mod` b
    | rhci_intEq b 0 = divZeroError
    | rhci_intEq b (rhci_intNegate 1) = 0
    | otherwise = rhci_intMod a b
  a `quotRem` b
    | rhci_intEq b 0 = divZeroError
    | rhci_intEq b (rhci_intNegate 1) && rhci_intEq a minBound = (overflowError, 0)
    | otherwise = (rhci_intQuot a b, rhci_intRem a b)
  a `divMod` b
    | rhci_intEq b 0 = divZeroError
    | rhci_intEq b (rhci_intNegate 1) && rhci_intEq a minBound = (overflowError, 0)
    | otherwise = (rhci_intDiv a b, rhci_intMod a b)

instance Real Integer where
  toRational x = x :% 1

instance Integral Integer where
  toInteger n = n
  a `quot` b = if rhci_integerEq b 0 then divZeroError else rhci_integerQuot a b
  a `rem` b = if rhci_integerEq b 0 then divZeroError else rhci_integerRem a b
  a `div` b = if rhci_integerEq b 0 then divZeroError else rhci_integerDiv a b
  a `mod` b = if rhci_integerEq b 0 then divZeroError else rhci_integerMod a b
  a `quotRem` b = if rhci_integerEq b 0 then divZeroError else (rhci_integerQuot a b, rhci_integerRem a b)
  a `divMod` b = if rhci_integerEq b 0 then divZeroError else (rhci_integerDiv a b, rhci_integerMod a b)

class Num a => Fractional a where
  (/) :: a -> a -> a
  recip :: a -> a
  fromRational :: Rational -> a
  recip x = 1 / x
  x / y = x * recip y

class Fractional a => Floating a where
  pi :: a
  exp, log, sqrt :: a -> a
  (**), logBase :: a -> a -> a
  sin, cos, tan, asin, acos, atan :: a -> a
  sinh, cosh, tanh, asinh, acosh, atanh :: a -> a
  x ** y = exp (log x * y)
  logBase x y = log y / log x
  sqrt x = x ** 0.5
  tan x = sin x / cos x
  tanh x = sinh x / cosh x

class (Real a, Fractional a) => RealFrac a where
  properFraction :: Integral b => a -> (b, a)
  truncate, round, ceiling, floor :: Integral b => a -> b
  truncate x = fst (properFraction x)

class (RealFrac a, Floating a) => RealFloat a where
  floatRadix :: a -> Integer
  floatDigits :: a -> Int
  floatRange :: a -> (Int, Int)
  decodeFloat :: a -> (Integer, Int)
  encodeFloat :: Integer -> Int -> a
  exponent :: a -> Int
  significand :: a -> a
  scaleFloat :: Int -> a -> a
  isNaN, isInfinite, isDenormalized, isNegativeZero, isIEEE :: a -> Bool
  atan2 :: a -> a -> a
  exponent x = if m == 0 then 0 else n + floatDigits x
    where (m, n) = decodeFloat x
  significand x = encodeFloat m (negate (floatDigits x))
    where (m, _) = decodeFloat x
  atan2 y x
    | x > 0 = atan (y / x)
    | x == 0 && y > 0 = pi / 2
    | x < 0 && y > 0 = pi + atan (y / x)
    | (x <= 0 && y < 0) || (x < 0 && isNegativeZero y) || (isNegativeZero x && isNegativeZero y)
      = negate (atan2 (negate y) x)
    | y == 0 && (x < 0 || isNegativeZero x) = pi
    | x == 0 && y == 0 = y
    | otherwise = x + y

instance Real Double where
  toRational x = case rhci_doubleDecode x of
    (m, e) -> if rhci_intGe e 0
                then (m * 2 ^ e) :% 1
                else rhci_reduce m (2 ^ negate e)

rhci_reduce :: Integer -> Integer -> Rational
rhci_reduce x y = (x `quot` d) :% (y `quot` d)
  where d = gcd x y

instance Fractional Double where
  (/) = rhci_doubleDiv
  recip x = rhci_doubleDiv 1.0 x
  fromRational (n :% d) = rhci_doubleFromRational n d

instance Floating Double where
  pi = 3.141592653589793
  exp = rhci_doubleExp
  log = rhci_doubleLog
  sqrt = rhci_doubleSqrt
  (**) = rhci_doublePow
  logBase x y = log y / log x
  sin = rhci_doubleSin
  cos = rhci_doubleCos
  tan = rhci_doubleTan
  asin = rhci_doubleAsin
  acos = rhci_doubleAcos
  atan = rhci_doubleAtan
  sinh = rhci_doubleSinh
  cosh = rhci_doubleCosh
  tanh = rhci_doubleTanh
  asinh = rhci_doubleAsinh
  acosh = rhci_doubleAcosh
  atanh = rhci_doubleAtanh

instance RealFrac Double where
  properFraction x = case rhci_doubleTruncate x of
    n -> (fromInteger n, rhci_doubleSub x (rhci_integerToDouble n))
  truncate x = fromInteger (rhci_doubleTruncate x)
  round x = fromInteger (rhci_doubleRound x)
  ceiling x = fromInteger (rhci_doubleCeiling x)
  floor x = fromInteger (rhci_doubleFloor x)

instance RealFloat Double where
  floatRadix _ = 2
  floatDigits _ = 53
  floatRange _ = (negate 1021, 1024)
  decodeFloat = rhci_doubleDecode
  encodeFloat = rhci_doubleEncode
  scaleFloat n x
    | n == 0 || x == 0 || isNaN x || isInfinite x = x
    | otherwise = case decodeFloat x of (m, e) -> encodeFloat m (e + max (negate 2200) (min 2200 n))
  isNaN = rhci_doubleIsNaN
  isInfinite = rhci_doubleIsInfinite
  isDenormalized x = x /= 0 && not (isNaN x) && not (isInfinite x) && rhci_doubleLt (rhci_doubleAbs x) 2.2250738585072014e-308
  isNegativeZero = rhci_doubleIsNegativeZero
  isIEEE _ = True

even, odd :: Integral a => a -> Bool
even n = n `rem` 2 == 0
odd = not . even

gcd :: Integral a => a -> a -> a
gcd x y = gcd' (abs x) (abs y)
  where
    gcd' a 0 = a
    gcd' a b = gcd' b (a `rem` b)

lcm :: Integral a => a -> a -> a
lcm _ 0 = 0
lcm 0 _ = 0
lcm x y = abs ((x `quot` (gcd x y)) * y)

(^) :: (Num a, Integral b) => a -> b -> a
x0 ^ y0
  | y0 < 0 = errorWithoutStackTrace "Negative exponent"
  | y0 == 0 = 1
  | otherwise = powImpl x0 y0

powImpl :: (Num a, Integral b) => a -> b -> a
powImpl x y
  | even y = powImpl (x * x) (y `quot` 2)
  | y == 1 = x
  | otherwise = powImplAcc (x * x) (y `quot` 2) x

powImplAcc :: (Num a, Integral b) => a -> b -> a -> a
powImplAcc x y z
  | even y = powImplAcc (x * x) (y `quot` 2) z
  | y == 1 = x * z
  | otherwise = powImplAcc (x * x) (y `quot` 2) (x * z)

(^^) :: (Fractional a, Integral b) => a -> b -> a
x ^^ n = if n >= 0 then x ^ n else recip (x ^ negate n)

fromIntegral :: (Integral a, Num b) => a -> b
fromIntegral = fromInteger . toInteger

realToFrac :: (Real a, Fractional b) => a -> b
realToFrac = fromRational . toRational

-- Ratio: only what fractional literals and toRational need.
instance (Integral a) => Eq (Ratio a) where
  (x :% y) == (x' :% y') = x == x' && y == y'

-- ---- Enum and Bounded ---------------------------------------------------------------------

class Enum a where
  succ, pred :: a -> a
  toEnum :: Int -> a
  fromEnum :: a -> Int
  enumFrom :: a -> [a]
  enumFromThen :: a -> a -> [a]
  enumFromTo :: a -> a -> [a]
  enumFromThenTo :: a -> a -> a -> [a]
  succ = toEnum . rhci_intAdd 1 . fromEnum
  pred = toEnum . (\x -> rhci_intSub x 1) . fromEnum
  enumFrom x = map toEnum (rhci_enumFromInt (fromEnum x))
  enumFromThen x y = map toEnum (rhci_enumFromThenInt (fromEnum x) (fromEnum y))
  enumFromTo x y = map toEnum (rhci_enumFromToInt (fromEnum x) (fromEnum y))
  enumFromThenTo x1 x2 y = map toEnum (rhci_enumFromThenToInt (fromEnum x1) (fromEnum x2) (fromEnum y))

class Bounded a where
  minBound, maxBound :: a

rhci_map :: (a -> b) -> [a] -> [b]
rhci_map = map

rhci_enumFromInt :: Int -> [Int]
rhci_enumFromInt x = rhci_enumFromToInt x maxBound

rhci_enumFromToInt :: Int -> Int -> [Int]
rhci_enumFromToInt x y
  | rhci_intGt x y = []
  | otherwise = go x
  where
    go i = i : (if rhci_intEq i y then [] else go (rhci_intAdd i 1))

rhci_enumFromThenInt :: Int -> Int -> [Int]
rhci_enumFromThenInt x1 x2 =
  rhci_enumFromThenToInt x1 x2 (if rhci_intGe x2 x1 then maxBound else minBound)

-- No overflow past the limit, like GHC's efdtInt.
rhci_enumFromThenToInt :: Int -> Int -> Int -> [Int]
rhci_enumFromThenToInt x1 x2 y
  | rhci_intGe x2 x1 = if rhci_intGt x1 y then [] else up x1
  | otherwise = if rhci_intLt x1 y then [] else dn x1
  where
    delta = rhci_intSub x2 x1
    up x = x : (if rhci_intGt x (rhci_intSub y delta) then [] else up (rhci_intAdd x delta))
    dn x = x : (if rhci_intLt x (rhci_intSub y delta) then [] else dn (rhci_intAdd x delta))

instance Bounded Int where
  minBound = negate 9223372036854775808
  maxBound = 9223372036854775807

instance Enum Int where
  succ x
    | rhci_intEq x maxBound = errorWithoutStackTrace "Prelude.Enum.succ{Int}: tried to take `succ' of maxBound"
    | otherwise = rhci_intAdd x 1
  pred x
    | rhci_intEq x minBound = errorWithoutStackTrace "Prelude.Enum.pred{Int}: tried to take `pred' of minBound"
    | otherwise = rhci_intSub x 1
  toEnum x = x
  fromEnum x = x
  enumFrom = rhci_enumFromInt
  enumFromThen = rhci_enumFromThenInt
  enumFromTo = rhci_enumFromToInt
  enumFromThenTo = rhci_enumFromThenToInt

instance Enum Integer where
  succ x = x + 1
  pred x = x - 1
  toEnum x = rhci_intToInteger x
  fromEnum x = rhci_integerToInt x
  enumFrom x = x : enumFrom (x + 1)
  enumFromThen x y = rhci_enumDeltaInteger x (y - x)
  enumFromTo x lim = rhci_enumDeltaToInteger x 1 lim
  enumFromThenTo x y lim = rhci_enumDeltaToInteger x (y - x) lim

rhci_enumDeltaInteger :: Integer -> Integer -> [Integer]
rhci_enumDeltaInteger x d = x : rhci_enumDeltaInteger (x + d) d

rhci_enumDeltaToInteger :: Integer -> Integer -> Integer -> [Integer]
rhci_enumDeltaToInteger x delta lim
  | delta >= 0 = up x
  | otherwise = dn x
  where
    up y = if y > lim then [] else y : up (y + delta)
    dn y = if y < lim then [] else y : dn (y + delta)

instance Enum Double where
  succ x = x + 1
  pred x = x - 1
  toEnum = fromIntegral
  fromEnum = fromInteger . truncate
  enumFrom = numericEnumFrom
  enumFromThen = numericEnumFromThen
  enumFromTo = numericEnumFromTo
  enumFromThenTo = numericEnumFromThenTo

numericEnumFrom :: Fractional a => a -> [a]
numericEnumFrom n = go 0
  where
    go k = let n' = n + k in n' `seq` (n' : go (k + 1))

numericEnumFromThen :: Fractional a => a -> a -> [a]
numericEnumFromThen n m = go 0
  where
    step = m - n
    go k = let n' = n + k * step in n' `seq` (n' : go (k + 1))

numericEnumFromTo :: (Ord a, Fractional a) => a -> a -> [a]
numericEnumFromTo n m = takeWhile (<= m + 1 / 2) (numericEnumFrom n)

numericEnumFromThenTo :: (Ord a, Fractional a) => a -> a -> a -> [a]
numericEnumFromThenTo e1 e2 e3 = takeWhile predicate (numericEnumFromThen e1 e2)
  where
    mid = (e2 - e1) / 2
    predicate | e2 >= e1 = (<= e3 + mid)
              | otherwise = (>= e3 + mid)

instance Bounded Char where
  minBound = '\0'
  maxBound = '\1114111'

instance Enum Char where
  succ c = rhci_chr (rhci_intAdd (rhci_ord c) 1)
  pred c = rhci_chr (rhci_intSub (rhci_ord c) 1)
  toEnum = rhci_chr
  fromEnum = rhci_ord
  enumFrom c = map rhci_chr (rhci_enumFromToInt (rhci_ord c) 1114111)
  enumFromThen c d = map rhci_chr (rhci_enumFromThenToInt (rhci_ord c) (rhci_ord d)
                        (if rhci_intGe (rhci_ord d) (rhci_ord c) then 1114111 else 0))

instance Bounded () where
  minBound = ()
  maxBound = ()

instance Enum () where
  toEnum 0 = ()
  toEnum _ = errorWithoutStackTrace "Prelude.Enum.().toEnum: bad argument"
  fromEnum () = 0

instance (Bounded a, Bounded b) => Bounded (a, b) where
  minBound = (minBound, minBound)
  maxBound = (maxBound, maxBound)

-- ---- Semigroup and Monoid --------------------------------------------------------------------

class Semigroup a where
  (<>) :: a -> a -> a

class Semigroup a => Monoid a where
  mempty :: a
  mappend :: a -> a -> a
  mconcat :: [a] -> a
  mappend = (<>)
  mconcat = rhci_foldr mappend mempty

instance Semigroup [a] where
  (<>) = (++)

instance Monoid [a] where
  mempty = []

instance Semigroup Ordering where
  LT <> _ = LT
  EQ <> y = y
  GT <> _ = GT

instance Monoid Ordering where
  mempty = EQ

instance Semigroup () where
  _ <> _ = ()

instance Monoid () where
  mempty = ()

instance Semigroup a => Semigroup (Maybe a) where
  Nothing <> b = b
  a <> Nothing = a
  Just a <> Just b = Just (a <> b)

instance Semigroup a => Monoid (Maybe a) where
  mempty = Nothing

instance Semigroup b => Semigroup (a -> b) where
  f <> g = \x -> f x <> g x

instance Monoid b => Monoid (a -> b) where
  mempty _ = mempty

instance (Semigroup a, Semigroup b) => Semigroup (a, b) where
  (a, b) <> (a', b') = (a <> a', b <> b')

instance (Monoid a, Monoid b) => Monoid (a, b) where
  mempty = (mempty, mempty)

-- ---- Functor, Applicative, Monad ----------------------------------------------------------

class Functor f where
  fmap :: (a -> b) -> f a -> f b
  (<$) :: a -> f b -> f a
  (<$) = fmap . const

(<$>) :: Functor f => (a -> b) -> f a -> f b
(<$>) = fmap

($>) :: Functor f => f a -> b -> f b
($>) = flip (<$)

(<&>) :: Functor f => f a -> (a -> b) -> f b
as <&> f = f <$> as

void :: Functor f => f a -> f ()
void x = () <$ x

class Functor f => Applicative f where
  pure :: a -> f a
  (<*>) :: f (a -> b) -> f a -> f b
  liftA2 :: (a -> b -> c) -> f a -> f b -> f c
  (*>) :: f a -> f b -> f b
  (<*) :: f a -> f b -> f a
  (<*>) = liftA2 id
  liftA2 f x = (<*>) (fmap f x)
  a1 *> a2 = (id <$ a1) <*> a2
  (<*) = liftA2 const

class Applicative m => Monad m where
  (>>=) :: m a -> (a -> m b) -> m b
  (>>) :: m a -> m b -> m b
  return :: a -> m a
  m >> k = m >>= \_ -> k
  return = pure

class Monad m => MonadFail m where
  fail :: String -> m a

(=<<) :: Monad m => (a -> m b) -> m a -> m b
f =<< x = x >>= f

instance Functor [] where
  fmap = map

instance Applicative [] where
  pure x = [x]
  fs <*> xs = [f x | f <- fs, x <- xs]
  liftA2 f xs ys = [f x y | x <- xs, y <- ys]
  xs *> ys = [y | _ <- xs, y <- ys]

instance Monad [] where
  xs >>= f = [y | x <- xs, y <- f x]
  (>>) = (*>)

instance MonadFail [] where
  fail _ = []

instance Functor Maybe where
  fmap _ Nothing = Nothing
  fmap f (Just a) = Just (f a)

instance Applicative Maybe where
  pure = Just
  Just f <*> m = fmap f m
  Nothing <*> _ = Nothing
  liftA2 f (Just x) (Just y) = Just (f x y)
  liftA2 _ _ _ = Nothing
  Just _ *> m = m
  Nothing *> _ = Nothing

instance Monad Maybe where
  (Just x) >>= k = k x
  Nothing >>= _ = Nothing
  (>>) = (*>)

instance MonadFail Maybe where
  fail _ = Nothing

instance Functor (Either e) where
  fmap _ (Left x) = Left x
  fmap f (Right y) = Right (f y)

instance Applicative (Either e) where
  pure = Right
  Left e <*> _ = Left e
  Right f <*> r = fmap f r

instance Monad (Either e) where
  Left l >>= _ = Left l
  Right r >>= k = k r

instance Functor ((,) a) where
  fmap f (x, y) = (x, f y)

instance Functor ((->) r) where
  fmap = (.)

instance Applicative ((->) r) where
  pure = const
  (<*>) f g x = f x (g x)
  liftA2 q f g x = q (f x) (g x)

instance Monad ((->) r) where
  f >>= k = \r -> k (f r) r

instance Functor IO where
  fmap f x = x `rhci_bindIO` (rhci_returnIO . f)

instance Applicative IO where
  pure = rhci_returnIO
  m <*> n = m `rhci_bindIO` \f -> n `rhci_bindIO` \x -> rhci_returnIO (f x)
  liftA2 f m n = m `rhci_bindIO` \x -> n `rhci_bindIO` \y -> rhci_returnIO (f x y)
  (*>) = rhci_thenIO

instance Monad IO where
  (>>=) = rhci_bindIO
  (>>) = rhci_thenIO

instance MonadFail IO where
  fail s = ioError (userError s)

-- ---- IO ------------------------------------------------------------------------------------

rhci_unIO :: IO a -> () -> IORes a
rhci_unIO (IO m) = m

rhci_returnIO :: a -> IO a
rhci_returnIO x = IO (\_ -> IORes x)

rhci_bindIO :: IO a -> (a -> IO b) -> IO b
rhci_bindIO (IO m) k = IO (\w -> case m w of IORes a -> rhci_unIO (k a) w)

rhci_thenIO :: IO a -> IO b -> IO b
rhci_thenIO a b = rhci_bindIO a (\_ -> b)

newtype IOError = IOError String

userError :: String -> IOError
userError s = IOError ("user error (" ++ s ++ ")")

ioError :: IOError -> IO a
ioError (IOError s) = IO (\_ -> rhci_raise s)

putChar :: Char -> IO ()
putChar c = IO (\_ -> case rhci_putChar c of () -> IORes ())

putStr :: String -> IO ()
putStr [] = rhci_returnIO ()
putStr (c:cs) = putChar c `rhci_thenIO` putStr cs

putStrLn :: String -> IO ()
putStrLn s = putStr s `rhci_thenIO` putChar '\n'

print :: Show a => a -> IO ()
print x = putStrLn (show x)

rhci_print :: Show a => a -> IO ()
rhci_print x = putStrLn (show x)

-- ---- Foldable and Traversable ------------------------------------------------------------

class Foldable t where
  foldMap :: Monoid m => (a -> m) -> t a -> m
  foldr :: (a -> b -> b) -> b -> t a -> b
  foldl :: (b -> a -> b) -> b -> t a -> b
  foldr' :: (a -> b -> b) -> b -> t a -> b
  foldl' :: (b -> a -> b) -> b -> t a -> b
  foldr1 :: (a -> a -> a) -> t a -> a
  foldl1 :: (a -> a -> a) -> t a -> a
  toList :: t a -> [a]
  null :: t a -> Bool
  length :: t a -> Int
  elem :: Eq a => a -> t a -> Bool
  maximum :: Ord a => t a -> a
  minimum :: Ord a => t a -> a
  sum :: Num a => t a -> a
  product :: Num a => t a -> a
  foldMap f = foldr (mappend . f) mempty
  foldl f z t = foldr (\x k acc -> k (f acc x)) id t z
  foldr' f z0 xs = foldl (\k x z -> k $! f x z) id xs z0
  foldl' f z0 xs = foldr (\x k z -> k $! f z x) id xs z0
  foldr1 f xs = fromMaybe (errorWithoutStackTrace "foldr1: empty structure") (foldr mf Nothing xs)
    where mf x m = Just (case m of { Nothing -> x; Just y -> f x y })
  foldl1 f xs = fromMaybe (errorWithoutStackTrace "foldl1: empty structure") (foldl mf Nothing xs)
    where mf m y = Just (case m of { Nothing -> y; Just x -> f x y })
  toList t = foldr (:) [] t
  null = foldr (\_ _ -> False) True
  length = foldl' (\c _ -> c + 1) 0
  elem x = any (== x)
  maximum xs = fromMaybe (errorWithoutStackTrace "maximum: empty structure")
                 (foldl' (\m y -> Just (case m of { Nothing -> y; Just x -> max x y })) Nothing xs)
  minimum xs = fromMaybe (errorWithoutStackTrace "minimum: empty structure")
                 (foldl' (\m y -> Just (case m of { Nothing -> y; Just x -> min x y })) Nothing xs)
  sum = foldl' (+) 0
  product = foldl' (*) 1

-- The list instance uses GHC.List's definitions (and its error messages).
instance Foldable [] where
  foldr = rhci_foldr
  foldl f z0 xs = rhci_foldl f z0 xs
  foldl' f z0 xs = rhci_foldl' f z0 xs
  foldr1 f [] = errorWithoutStackTrace "Prelude.foldr1: empty list"
  foldr1 f xs = rhci_foldr1 f xs
  foldl1 f (x:xs) = rhci_foldl f x xs
  foldl1 _ [] = errorWithoutStackTrace "Prelude.foldl1: empty list"
  toList xs = xs
  null [] = True
  null (_:_) = False
  length xs = rhci_lenAcc xs 0
  elem x xs = rhci_elem x xs
  maximum [] = errorWithoutStackTrace "Prelude.maximum: empty list"
  maximum (x:xs) = rhci_foldl' max x xs
  minimum [] = errorWithoutStackTrace "Prelude.minimum: empty list"
  minimum (x:xs) = rhci_foldl' min x xs
  sum xs = rhci_foldl' (+) 0 xs
  product xs = rhci_foldl' (*) 1 xs

instance Foldable Maybe where
  foldMap f Nothing = mempty
  foldMap f (Just x) = f x
  foldr _ z Nothing = z
  foldr f z (Just x) = f x z
  foldl _ z Nothing = z
  foldl f z (Just x) = f z x

instance Foldable (Either a) where
  foldMap _ (Left _) = mempty
  foldMap f (Right y) = f y
  foldr _ z (Left _) = z
  foldr f z (Right y) = f y z
  length (Left _) = 0
  length (Right _) = 1
  null (Left _) = True
  null (Right _) = False

instance Foldable ((,) a) where
  foldMap f (_, y) = f y
  foldr f z (_, y) = f y z
  length _ = 1
  null _ = False

class (Functor t, Foldable t) => Traversable t where
  traverse :: Applicative f => (a -> f b) -> t a -> f (t b)
  sequenceA :: Applicative f => t (f a) -> f (t a)
  mapM :: Monad m => (a -> m b) -> t a -> m (t b)
  sequence :: Monad m => t (m a) -> m (t a)
  traverse f = sequenceA . fmap f
  sequenceA = traverse id
  mapM = traverse
  sequence = sequenceA

instance Traversable [] where
  traverse f = rhci_foldr cons_f (pure [])
    where cons_f x ys = liftA2 (:) (f x) ys

instance Traversable Maybe where
  traverse _ Nothing = pure Nothing
  traverse f (Just x) = Just <$> f x

instance Traversable (Either a) where
  traverse _ (Left x) = pure (Left x)
  traverse f (Right y) = Right <$> f y

instance Traversable ((,) a) where
  traverse f (x, y) = (,) x <$> f y

mapM_ :: (Foldable t, Monad m) => (a -> m b) -> t a -> m ()
mapM_ f = foldr c (return ())
  where c x k = f x >> k

forM_ :: (Foldable t, Monad m) => t a -> (a -> m b) -> m ()
forM_ = flip mapM_

forM :: (Traversable t, Monad m) => t a -> (a -> m b) -> m (t b)
forM = flip mapM

sequence_ :: (Foldable t, Monad m) => t (m a) -> m ()
sequence_ = foldr c (return ())
  where c m k = m >> k

sequenceA_ :: (Foldable t, Applicative f) => t (f a) -> f ()
sequenceA_ = foldr c (pure ())
  where c m k = m *> k

traverse_ :: (Foldable t, Applicative f) => (a -> f b) -> t a -> f ()
traverse_ f = foldr c (pure ())
  where c x k = f x *> k

concat :: Foldable t => t [a] -> [a]
concat xs = foldr (++) [] xs

concatMap :: Foldable t => (a -> [b]) -> t a -> [b]
concatMap f xs = foldr (\x b -> f x ++ b) [] xs

and :: Foldable t => t Bool -> Bool
and = foldr (&&) True

or :: Foldable t => t Bool -> Bool
or = foldr (||) False

any :: Foldable t => (a -> Bool) -> t a -> Bool
any p = foldr (\x b -> p x || b) False

all :: Foldable t => (a -> Bool) -> t a -> Bool
all p = foldr (\x b -> p x && b) True

notElem :: (Foldable t, Eq a) => a -> t a -> Bool
notElem x = not . elem x

find :: Foldable t => (a -> Bool) -> t a -> Maybe a
find p = listToMaybe . filter p . toList

maximumBy :: Foldable t => (a -> a -> Ordering) -> t a -> a
maximumBy cmp = fromMaybe (errorWithoutStackTrace "maximumBy: empty structure") . foldl' max' Nothing
  where max' mx y = Just (case mx of { Nothing -> y; Just x -> case cmp x y of { GT -> x; _ -> y } })

minimumBy :: Foldable t => (a -> a -> Ordering) -> t a -> a
minimumBy cmp = fromMaybe (errorWithoutStackTrace "minimumBy: empty structure") . foldl' min' Nothing
  where min' mx y = Just (case mx of { Nothing -> y; Just x -> case cmp x y of { GT -> y; _ -> x } })

-- ---- Control.Monad -------------------------------------------------------------------------

when :: Applicative f => Bool -> f () -> f ()
when p s = if p then s else pure ()

unless :: Applicative f => Bool -> f () -> f ()
unless p s = if p then pure () else s

replicateM :: Applicative m => Int -> m a -> m [a]
replicateM cnt0 f = loop cnt0
  where
    loop cnt
      | cnt <= 0 = pure []
      | otherwise = liftA2 (:) f (loop (cnt - 1))

replicateM_ :: Applicative m => Int -> m a -> m ()
replicateM_ cnt0 f = loop cnt0
  where
    loop cnt
      | cnt <= 0 = pure ()
      | otherwise = f *> loop (cnt - 1)

foldM :: (Foldable t, Monad m) => (b -> a -> m b) -> b -> t a -> m b
foldM f z0 xs = foldr c return xs z0
  where c x k z = f z x >>= k

zipWithM :: Applicative m => (a -> b -> m c) -> [a] -> [b] -> m [c]
zipWithM f xs ys = sequenceA (zipWith f xs ys)

zipWithM_ :: Applicative m => (a -> b -> m c) -> [a] -> [b] -> m ()
zipWithM_ f xs ys = sequenceA_ (zipWith f xs ys)

join :: Monad m => m (m a) -> m a
join x = x >>= id

liftM :: Monad m => (a1 -> r) -> m a1 -> m r
liftM f m1 = do { x1 <- m1; return (f x1) }

liftM2 :: Monad m => (a1 -> a2 -> r) -> m a1 -> m a2 -> m r
liftM2 f m1 m2 = do { x1 <- m1; x2 <- m2; return (f x1 x2) }

ap :: Monad m => m (a -> b) -> m a -> m b
ap m1 m2 = do { x1 <- m1; x2 <- m2; return (x1 x2) }

(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> a -> m c
f >=> g = \x -> f x >>= g

(<=<) :: Monad m => (b -> m c) -> (a -> m b) -> a -> m c
(<=<) = flip (>=>)

filterM :: Applicative m => (a -> m Bool) -> [a] -> m [a]
filterM p = rhci_foldr (\x -> liftA2 (\flg -> if flg then (x:) else id) (p x)) (pure [])

-- ---- tuples ------------------------------------------------------------------------

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

-- ---- Maybe and Either -------------------------------------------------------------

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

-- ---- lists (GHC.List) ------------------------------------------------------------------

rhci_foldr :: (a -> b -> b) -> b -> [a] -> b
rhci_foldr k z = go
  where
    go [] = z
    go (y:ys) = y `k` go ys

rhci_foldl :: (b -> a -> b) -> b -> [a] -> b
rhci_foldl f z [] = z
rhci_foldl f z (x:xs) = rhci_foldl f (f z x) xs

rhci_foldl' :: (b -> a -> b) -> b -> [a] -> b
rhci_foldl' f z [] = z
rhci_foldl' f z (x:xs) = let z' = f z x in z' `seq` rhci_foldl' f z' xs

rhci_foldr1 :: (a -> a -> a) -> [a] -> a
rhci_foldr1 f = go
  where
    go [x] = x
    go (x:xs) = f x (go xs)
    go [] = errorWithoutStackTrace "Prelude.foldr1: empty list"

rhci_lenAcc :: [a] -> Int -> Int
rhci_lenAcc [] n = n
rhci_lenAcc (_:ys) n = let n' = rhci_intAdd n 1 in n' `seq` rhci_lenAcc ys n'

rhci_elem :: Eq a => a -> [a] -> Bool
rhci_elem _ [] = False
rhci_elem x (y:ys) = x == y || rhci_elem x ys

rhci_concatMap :: (a -> [b]) -> [a] -> [b]
rhci_concatMap f = rhci_foldr ((++) . f) []

rhci_append :: [a] -> [a] -> [a]
rhci_append = (++)

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

(!!) :: [a] -> Int -> a
xs !! n
  | n < 0 = errorWithoutStackTrace "Prelude.!!: negative index"
  | otherwise = rhci_foldr (\x r k -> if k == 0 then x else r (k - 1))
                  (\_ -> errorWithoutStackTrace "Prelude.!!: index too large") xs n

reverse :: [a] -> [a]
reverse l = rev l []
  where
    rev [] a = a
    rev (x:xs) a = rev xs (x : a)

iterate :: (a -> a) -> a -> [a]
iterate f x = x : iterate f (f x)

iterate' :: (a -> a) -> a -> [a]
iterate' f x = let x' = f x in x' `seq` (x : iterate' f x')

repeat :: a -> [a]
repeat x = xs where xs = x : xs

replicate :: Int -> a -> [a]
replicate n x = take n (repeat x)

cycle :: [a] -> [a]
cycle [] = errorWithoutStackTrace "Prelude.cycle: empty list"
cycle xs = xs' where xs' = xs ++ xs'

take :: Int -> [a] -> [a]
take n xs
  | n <= 0 = []
  | otherwise = unsafeTake n xs
  where
    unsafeTake _ [] = []
    unsafeTake 1 (y:_) = [y]
    unsafeTake m (y:ys) = y : unsafeTake (m - 1) ys

drop :: Int -> [a] -> [a]
drop n ls
  | n <= 0 = ls
  | otherwise = unsafeDrop n ls
  where
    unsafeDrop _ [] = []
    unsafeDrop 1 (_:ys) = ys
    unsafeDrop m (_:ys) = unsafeDrop (m - 1) ys

splitAt :: Int -> [a] -> ([a], [a])
splitAt n ls
  | n <= 0 = ([], ls)
  | otherwise = splitAt' n ls
  where
    splitAt' _ [] = ([], [])
    splitAt' 1 (x:xs) = ([x], xs)
    splitAt' m (x:xs) = (x : xs', xs'')
      where (xs', xs'') = splitAt' (m - 1) xs

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

dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd p = rhci_foldr (\x xs -> if p x && null xs then [] else x : xs) []

span :: (a -> Bool) -> [a] -> ([a], [a])
span _ xs@[] = (xs, xs)
span p xs@(x:xs')
  | p x = let (ys, zs) = span p xs' in (x : ys, zs)
  | otherwise = ([], xs)

break :: (a -> Bool) -> [a] -> ([a], [a])
break p = span (not . p)

lookup :: Eq a => a -> [(a, b)] -> Maybe b
lookup _ [] = Nothing
lookup key ((x, y) : xys)
  | key == x = Just y
  | otherwise = lookup key xys

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

scanl1 :: (a -> a -> a) -> [a] -> [a]
scanl1 f (x:xs) = scanl f x xs
scanl1 _ [] = []

scanl' :: (b -> a -> b) -> b -> [a] -> [b]
scanl' f q ls = q `seq` (q : (case ls of
                               [] -> []
                               x:xs -> scanl' f (f q x) xs))

scanr :: (a -> b -> b) -> b -> [a] -> [b]
scanr _ q0 [] = [q0]
scanr f q0 (x:xs) = case scanr f q0 xs of
  qs@(q:_) -> f x q : qs

scanr1 :: (a -> a -> a) -> [a] -> [a]
scanr1 _ [] = []
scanr1 _ [x] = [x]
scanr1 f (x:xs) = case scanr1 f xs of
  qs@(q:_) -> f x q : qs

unfoldr :: (b -> Maybe (a, b)) -> b -> [a]
unfoldr f b0 = go b0
  where
    go b = case f b of
      Just (a, new_b) -> a : go new_b
      Nothing -> []

-- ---- Data.List -----------------------------------------------------------------------------

elemIndex :: Eq a => a -> [a] -> Maybe Int
elemIndex x = findIndex (x ==)

elemIndices :: Eq a => a -> [a] -> [Int]
elemIndices x = findIndices (x ==)

findIndex :: (a -> Bool) -> [a] -> Maybe Int
findIndex p = listToMaybe . findIndices p

findIndices :: (a -> Bool) -> [a] -> [Int]
findIndices p ls = [i | (x, i) <- zip ls [0 ..], p x]

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

isSuffixOf :: Eq a => [a] -> [a] -> Bool
ns `isSuffixOf` hs = reverse ns `isPrefixOf` reverse hs

isInfixOf :: Eq a => [a] -> [a] -> Bool
isInfixOf needle haystack = any (isPrefixOf needle) (tails haystack)

isSubsequenceOf :: Eq a => [a] -> [a] -> Bool
isSubsequenceOf [] _ = True
isSubsequenceOf _ [] = False
isSubsequenceOf a@(x:a') (y:b)
  | x == y = isSubsequenceOf a' b
  | otherwise = isSubsequenceOf a b

stripPrefix :: Eq a => [a] -> [a] -> Maybe [a]
stripPrefix [] ys = Just ys
stripPrefix (x:xs) (y:ys)
  | x == y = stripPrefix xs ys
stripPrefix _ _ = Nothing

nub :: Eq a => [a] -> [a]
nub l = nubBy (==) l

nubBy :: (a -> a -> Bool) -> [a] -> [a]
nubBy eq l = nubBy' l []
  where
    nubBy' [] _ = []
    nubBy' (y:ys) xs
      | elem_by eq y xs = nubBy' ys xs
      | otherwise = y : nubBy' ys (y : xs)

elem_by :: (a -> a -> Bool) -> a -> [a] -> Bool
elem_by _ _ [] = False
elem_by eq y (x:xs) = x `eq` y || elem_by eq y xs

delete :: Eq a => a -> [a] -> [a]
delete = deleteBy (==)

deleteBy :: (a -> a -> Bool) -> a -> [a] -> [a]
deleteBy _ _ [] = []
deleteBy eq x (y:ys) = if x `eq` y then ys else y : deleteBy eq x ys

(\\) :: Eq a => [a] -> [a] -> [a]
(\\) = rhci_foldl (flip delete)

union :: Eq a => [a] -> [a] -> [a]
union = unionBy (==)

unionBy :: (a -> a -> Bool) -> [a] -> [a] -> [a]
unionBy eq xs ys = xs ++ rhci_foldl (flip (deleteBy eq)) (nubBy eq ys) xs

intersect :: Eq a => [a] -> [a] -> [a]
intersect = intersectBy (==)

intersectBy :: (a -> a -> Bool) -> [a] -> [a] -> [a]
intersectBy _ [] _ = []
intersectBy _ _ [] = []
intersectBy eq xs ys = [x | x <- xs, any (eq x) ys]

insert :: Ord a => a -> [a] -> [a]
insert e ls = insertBy compare e ls

insertBy :: (a -> a -> Ordering) -> a -> [a] -> [a]
insertBy _ x [] = [x]
insertBy cmp x ys@(y:ys') = case cmp x y of
  GT -> y : insertBy cmp x ys'
  _ -> x : ys

group :: Eq a => [a] -> [[a]]
group = groupBy (==)

groupBy :: (a -> a -> Bool) -> [a] -> [[a]]
groupBy _ [] = []
groupBy eq (x:xs) = (x : ys) : groupBy eq zs
  where (ys, zs) = span (eq x) xs

partition :: (a -> Bool) -> [a] -> ([a], [a])
partition p xs = rhci_foldr (select p) ([], []) xs
  where
    select q x ~(ts, fs) | q x = (x : ts, fs)
                         | otherwise = (ts, x : fs)

inits :: [a] -> [[a]]
inits xs = [] : case xs of
  [] -> []
  x:xs' -> map (x :) (inits xs')

tails :: [a] -> [[a]]
tails lst = lst : case lst of
  [] -> []
  _:xs -> tails xs

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

permutations :: [a] -> [[a]]
permutations xs0 = xs0 : perms xs0 []
  where
    perms [] _ = []
    perms (t:ts) is' = rhci_foldr interleave (perms ts (t : is')) (permutations is')
      where
        interleave xs r = let (_, zs) = interleave' id xs r in zs
        interleave' _ [] r = (ts, r)
        interleave' f (y:ys) r = let (us, zs) = interleave' (f . (y :)) ys r
                                 in (y : us, f (t : y : us) : zs)

zip4 :: [a] -> [b] -> [c] -> [d] -> [(a, b, c, d)]
zip4 (a:as) (b:bs) (c:cs) (d:ds) = (a, b, c, d) : zip4 as bs cs ds
zip4 _ _ _ _ = []

genericLength :: Num i => [a] -> i
genericLength [] = 0
genericLength (_:l) = 1 + genericLength l

-- GHC's merge sort (Data.OldList.sortBy): stable, and as lazy as GHC's.
sort :: Ord a => [a] -> [a]
sort = sortBy compare

sortOn :: Ord b => (a -> b) -> [a] -> [a]
sortOn f = map snd . sortBy (comparing fst) . map (\x -> let y = f x in y `seq` (y, x))

sortBy :: (a -> a -> Ordering) -> [a] -> [a]
sortBy cmp = mergeAll . sequences
  where
    sequences (a:b:xs)
      | a `cmp` b == GT = descending b [a] xs
      | otherwise = ascending b (a :) xs
    sequences xs = [xs]

    descending a as (b:bs)
      | a `cmp` b == GT = descending b (a : as) bs
    descending a as bs = (a : as) : sequences bs

    ascending a as (b:bs)
      | a `cmp` b /= GT = ascending b (\ys -> as (a : ys)) bs
    ascending a as bs = let x = as [a] in x `seq` (x : sequences bs)

    mergeAll [x] = x
    mergeAll xs = mergeAll (mergePairs xs)

    mergePairs (a:b:xs) = let x = merge a b in x `seq` (x : mergePairs xs)
    mergePairs xs = xs

    merge as@(a:as') bs@(b:bs')
      | a `cmp` b == GT = b : merge as bs'
      | otherwise = a : merge as' bs
    merge [] bs = bs
    merge as [] = as

-- ---- strings ----------------------------------------------------------------------------------

lines :: String -> [String]
lines "" = []
lines s = cons (case break (== '\n') s of
                  (l, s') -> (l, case s' of
                                   [] -> []
                                   _:s'' -> lines s''))
  where
    cons ~(h, t) = h : t

unlines :: [String] -> String
unlines [] = []
unlines (l:ls) = l ++ '\n' : unlines ls

words :: String -> [String]
words s = case dropWhile isSpace s of
  "" -> []
  s' -> w : words s''
    where (w, s'') = break isSpace s'

unwords :: [String] -> String
unwords [] = ""
unwords ws = rhci_foldr1 (\w s -> w ++ ' ' : s) ws

-- ---- Data.Char (exact for Latin-1; beyond it rhci refuses) ------------------------------------

foreign import prim "charClass" rhci_charClass :: Char -> Int
foreign import prim "charUpper" rhci_toUpper :: Char -> Char
foreign import prim "charLower" rhci_toLower :: Char -> Char

ord :: Char -> Int
ord = rhci_ord

chr :: Int -> Char
chr = rhci_chr

isSpace :: Char -> Bool
isSpace = rhci_isSpace

isDigit :: Char -> Bool
isDigit c = rhci_intLe (rhci_intSub (rhci_ord c) 48) 9 && rhci_intGe (rhci_ord c) 48

isOctDigit :: Char -> Bool
isOctDigit c = rhci_intGe (rhci_ord c) 48 && rhci_intLe (rhci_ord c) 55

isHexDigit :: Char -> Bool
isHexDigit c = isDigit c || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')

isAscii :: Char -> Bool
isAscii c = c < '\x80'

isLatin1 :: Char -> Bool
isLatin1 c = c <= '\xff'

isControl :: Char -> Bool
isControl c = rhci_charClass c == 0

isPrint :: Char -> Bool
isPrint c = rhci_charClass c /= 0

isUpper :: Char -> Bool
isUpper c = rhci_charClass c == 1

isLower :: Char -> Bool
isLower c = rhci_charClass c == 2

isAlpha :: Char -> Bool
isAlpha c = let k = rhci_charClass c in k == 1 || k == 2 || k == 3

isLetter :: Char -> Bool
isLetter = isAlpha

isAlphaNum :: Char -> Bool
isAlphaNum c = let k = rhci_charClass c in k == 1 || k == 2 || k == 3 || k == 4

isNumber :: Char -> Bool
isNumber c = rhci_charClass c == 4

isPunctuation :: Char -> Bool
isPunctuation c = rhci_charClass c == 5

isSymbol :: Char -> Bool
isSymbol c = rhci_charClass c == 6

isSeparator :: Char -> Bool
isSeparator c = rhci_charClass c == 7

isAsciiUpper :: Char -> Bool
isAsciiUpper c = c >= 'A' && c <= 'Z'

isAsciiLower :: Char -> Bool
isAsciiLower c = c >= 'a' && c <= 'z'

toUpper :: Char -> Char
toUpper = rhci_toUpper

toLower :: Char -> Char
toLower = rhci_toLower

digitToInt :: Char -> Int
digitToInt c
  | isDigit c = ord c - ord '0'
  | c >= 'a' && c <= 'f' = ord c - ord 'a' + 10
  | c >= 'A' && c <= 'F' = ord c - ord 'A' + 10
  | otherwise = errorWithoutStackTrace ("Char.digitToInt: not a digit " ++ show c)

intToDigit :: Int -> Char
intToDigit i
  | i >= 0 && i <= 9 = chr (ord '0' + i)
  | i >= 10 && i <= 15 = chr (ord 'a' + i - 10)
  | otherwise = errorWithoutStackTrace ("Char.intToDigit: not a digit " ++ show i)
