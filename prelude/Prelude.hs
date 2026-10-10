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
infixr 5 +++, <++
infixl 3 <|>
infixl 4 <$!>, <**>
infixl 8 `shift`, `rotate`, `shiftL`, `shiftR`, `rotateL`, `rotateR`, `unsafeShiftL`, `unsafeShiftR`, .<<., .>>., !<<., !>>.
infixl 7 .&.
infixl 6 `xor`, .^.
infixl 5 .|.
infixl 7 %

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
data Maybe a = Nothing | Just a deriving (Eq, Ord, Show, Read)
data Either a b = Left a | Right b deriving (Eq, Ord, Show, Read)

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

-- ---- Data.Ratio (from GHC.Real) ----------------------------------------------------

instance (Integral a) => Eq (Ratio a) where
  (x :% y) == (x' :% y') = x == x' && y == y'

(%) :: Integral a => a -> a -> Ratio a
x % y = rhci_reduceR (x * signum y) (abs y)

rhci_reduceR :: Integral a => a -> a -> Ratio a
rhci_reduceR _ 0 = rhci_raise "Ratio has zero denominator"
rhci_reduceR x y = (x `quot` d) :% (y `quot` d)
  where d = gcd x y

numerator :: Ratio a -> a
numerator (x :% _) = x

denominator :: Ratio a -> a
denominator (_ :% y) = y

instance (Integral a) => Ord (Ratio a) where
  (x :% y) <= (x' :% y') = x * y' <= x' * y
  (x :% y) < (x' :% y') = x * y' < x' * y
  compare (x :% y) (x' :% y') = compare (x * y') (x' * y)

instance (Integral a) => Num (Ratio a) where
  (x :% y) + (x' :% y') = rhci_reduceR (x * y' + x' * y) (y * y')
  (x :% y) - (x' :% y') = rhci_reduceR (x * y' - x' * y) (y * y')
  (x :% y) * (x' :% y') = rhci_reduceR (x * x') (y * y')
  negate (x :% y) = negate x :% y
  abs (x :% y) = abs x :% y
  signum (x :% _) = signum x :% 1
  fromInteger x = fromInteger x :% 1

instance (Integral a) => Fractional (Ratio a) where
  (x :% y) / (x' :% y') = (x * y') % (y * x')
  recip (x :% y)
    | x == 0 = rhci_raise "Ratio has zero denominator"
    | x < 0 = negate y :% negate x
    | otherwise = y :% x
  fromRational (x :% y) = fromInteger x % fromInteger y

instance (Integral a) => Real (Ratio a) where
  toRational (x :% y) = toInteger x :% toInteger y

instance (Integral a) => RealFrac (Ratio a) where
  properFraction (x :% y) = (fromInteger (toInteger q), r :% y)
    where (q, r) = quotRem x y
  truncate x = fst (properFraction x)
  round r =
    let (n, f) = properFraction r
        x = if r < 0 then -1 else 1
    in case (compare (abs f) (1 :% 2), odd n) of
         (LT, _) -> n
         (EQ, False) -> n
         (EQ, True) -> n + x
         (GT, _) -> n + x
  ceiling x = if r > 0 then n + 1 else n
    where (n, r) = properFraction x
  floor x = if r < 0 then n - 1 else n
    where (n, r) = properFraction x

instance (Show a) => Show (Ratio a) where
  showsPrec p (x :% y) = showParen (p > 7) $ showsPrec 8 x . showString " % " . showsPrec 8 y

instance (Integral a) => Enum (Ratio a) where
  succ x = x + 1
  pred x = x - 1
  toEnum n = fromIntegral n :% 1
  fromEnum = fromInteger . truncate
  enumFrom = numericEnumFrom
  enumFromThen = numericEnumFromThen
  enumFromTo = numericEnumFromTo
  enumFromThenTo = numericEnumFromThenTo

approxRational :: (RealFrac a) => a -> a -> Rational
approxRational rat eps = simplest (toRational rat - toRational eps) (toRational rat + toRational eps)
  where
    simplest x y
      | y < x = simplest y x
      | x == y = xr
      | x > 0 = simplest' n d n' d'
      | y < 0 = negate (simplest' (negate n') d' (negate n) d)
      | otherwise = 0 :% 1
      where
        xr = toRational x
        n = numerator xr
        d = denominator xr
        nd' = toRational y
        n' = numerator nd'
        d' = denominator nd'
    simplest' n d n' d'
      | r == 0 = q :% 1
      | q /= q' = (q + 1) :% 1
      | otherwise = (q * n'' + d'') :% n''
      where
        (q, r) = quotRem n d
        (q', r') = quotRem n' d'
        nd'' = simplest' d' r' d r
        n'' = numerator nd''
        d'' = denominator nd''

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
putChar c = hPutChar stdout c

putStr :: String -> IO ()
putStr [] = rhci_returnIO ()
putStr (c:cs) = putChar c `rhci_thenIO` putStr cs

putStrLn :: String -> IO ()
putStrLn s = putStr s `rhci_thenIO` putChar '\n'

print :: Show a => a -> IO ()
print x = putStrLn (show x)

-- ---- System.IO and input ------------------------------------------------------

foreign import prim "hPutChar" rhci_hPutChar :: Int -> Char -> ()
foreign import prim "hFlush" rhci_hFlush :: Int -> ()
foreign import prim "getChar" rhci_getChar :: () -> Char
foreign import prim "getLine" rhci_getLine :: () -> [Char]
foreign import prim "isEOF" rhci_isEOF :: () -> Bool
foreign import prim "readChar" rhci_readChar :: () -> Int
foreign import prim "getArgs" rhci_getArgs :: () -> [[Char]]
foreign import prim "getContents" rhci_getContents :: () -> ()
foreign import prim "setBuffering" rhci_setBuffering :: Int -> BufferMode -> ()
foreign import prim "getBuffering" rhci_getBuffering :: Int -> BufferMode -> BufferMode

-- A Handle is the descriptor number and the name GHC shows.
data Handle = Handle Int String

instance Show Handle where
  showsPrec _ (Handle _ n) = showString "{handle: " . showString n . showString "}"

instance Eq Handle where
  Handle a _ == Handle b _ = rhci_intEq a b

stdin, stdout, stderr :: Handle
stdin = Handle 0 "<stdin>"
stdout = Handle 1 "<stdout>"
stderr = Handle 2 "<stderr>"

data BufferMode = NoBuffering | LineBuffering | BlockBuffering (Maybe Int)
  deriving (Eq, Ord, Read, Show)

data IOMode = ReadMode | WriteMode | AppendMode | ReadWriteMode
  deriving (Eq, Ord, Enum, Read, Show)

hPutChar :: Handle -> Char -> IO ()
hPutChar (Handle h _) c = IO (\_ -> case rhci_hPutChar h c of () -> IORes ())

hPutStr :: Handle -> String -> IO ()
hPutStr _ [] = rhci_returnIO ()
hPutStr h (c:cs) = hPutChar h c `rhci_thenIO` hPutStr h cs

hPutStrLn :: Handle -> String -> IO ()
hPutStrLn h s = hPutStr h s `rhci_thenIO` hPutChar h '\n'

hPrint :: Show a => Handle -> a -> IO ()
hPrint h x = hPutStrLn h (show x)

hFlush :: Handle -> IO ()
hFlush (Handle h _) = IO (\_ -> case rhci_hFlush h of () -> IORes ())

-- The mode is remembered and reported (GHCi starts with NoBuffering), but
-- output always appears in program order: stdout is flushed at each
-- newline, before stderr is written, and before stdin is read.
hSetBuffering :: Handle -> BufferMode -> IO ()
hSetBuffering (Handle h _) m = IO (\_ -> case rhci_setBuffering h m of () -> IORes ())

hGetBuffering :: Handle -> IO BufferMode
hGetBuffering (Handle h _) = IO (\_ -> case rhci_getBuffering h NoBuffering of m -> m `seq` IORes m)

rhci_stdinOnly :: String -> Handle -> IO a -> IO a
rhci_stdinOnly what (Handle h n) act
  | rhci_intEq h 0 = act
  | otherwise = ioError (IOError (n ++ ": " ++ what ++ ": illegal operation (handle is not open for reading)"))

getChar :: IO Char
getChar = IO (\w -> case rhci_getChar w of c -> c `seq` IORes c)

getLine :: IO String
getLine = IO (\w -> case rhci_getLine w of s -> s `seq` IORes s)

isEOF :: IO Bool
isEOF = IO (\w -> case rhci_isEOF w of b -> b `seq` IORes b)

hGetChar :: Handle -> IO Char
hGetChar h = rhci_stdinOnly "hGetChar" h getChar

hGetLine :: Handle -> IO String
hGetLine h = rhci_stdinOnly "hGetLine" h getLine

hIsEOF :: Handle -> IO Bool
hIsEOF h = rhci_stdinOnly "hIsEOF" h isEOF

-- stdin as a lazy String: characters are read as the list is consumed.
rhci_lazyInput :: () -> String
rhci_lazyInput w = case rhci_readChar w of
  c -> if rhci_intLt c 0 then [] else rhci_chr c : rhci_lazyInput w

rhci_stdinContents :: String
rhci_stdinContents = rhci_lazyInput ()

getContents :: IO String
getContents = IO (\w -> case rhci_getContents w of () -> IORes (rhci_lazyInput w))

hGetContents :: Handle -> IO String
hGetContents h = rhci_stdinOnly "hGetContents" h getContents

interact :: (String -> String) -> IO ()
interact f = getContents `rhci_bindIO` \s -> putStr (f s)

-- ---- Files ----------------------------------------------------------------------

type FilePath = String

data RhciBuf
data RhciReader

foreign import prim "bufNew" rhci_bufNew :: () -> RhciBuf
foreign import prim "bufPush" rhci_bufPush :: RhciBuf -> Char -> ()
foreign import prim "openRead" rhci_openRead :: () -> RhciBuf -> RhciReader
foreign import prim "readerChar" rhci_readerChar :: RhciReader -> Int
foreign import prim "openWrite" rhci_openWrite :: RhciBuf -> Int -> ()
foreign import prim "commitWrite" rhci_commitWrite :: RhciBuf -> RhciBuf -> ()

rhci_fillBuf :: RhciBuf -> String -> RhciBuf
rhci_fillBuf b [] = b
rhci_fillBuf b (c:cs) = case rhci_bufPush b c of () -> rhci_fillBuf b cs

-- The file is opened (and its errors raised) at once; its characters
-- come as the String is consumed, and its lock goes at the end.
readFile :: FilePath -> IO String
readFile p = IO (\w -> case rhci_openRead w (rhci_fillBuf (rhci_bufNew w) p) of
  r -> r `seq` IORes (rhci_lazyFile r))

rhci_lazyFile :: RhciReader -> String
rhci_lazyFile r = case rhci_readerChar r of
  c -> if rhci_intLt c 0 then [] else rhci_chr c : rhci_lazyFile r

writeFile :: FilePath -> String -> IO ()
writeFile = rhci_writeFile 0

appendFile :: FilePath -> String -> IO ()
appendFile = rhci_writeFile 1

rhci_writeFile :: Int -> FilePath -> String -> IO ()
rhci_writeFile mode p s = IO (\w -> case rhci_fillBuf (rhci_bufNew w) p of
  pb -> case rhci_openWrite pb mode of
    () -> case rhci_shove pb (rhci_bufNew w) 0 s of () -> IORes ())

-- GHC's hPutStr (writeBlocks): characters fill a 2048-slot buffer, which is
-- committed (encoded and written) whenever a next character arrives with
-- one slot left, so a String that fails part way leaves exactly the chunks
-- committed before the failure in the file.
rhci_shove :: RhciBuf -> RhciBuf -> Int -> String -> ()
rhci_shove pb b _ [] = rhci_commitWrite pb b
rhci_shove pb b n (c:cs)
  | rhci_intGe n 2047 = case rhci_commitWrite pb b of () -> rhci_shove pb b 0 (c:cs)
  | otherwise = case rhci_bufPush b c of () -> rhci_shove pb b (rhci_intAdd n 1) cs

getArgs :: IO [String]
getArgs = IO (\w -> case rhci_getArgs w of a -> a `seq` IORes a)

getProgName :: IO String
getProgName = rhci_returnIO "<interactive>"

rhci_print :: Show a => a -> IO ()
rhci_print x = putStrLn (show x)

-- ---- Foldable and Traversable ------------------------------------------------------------

-- Data.Monoid's Endo, for Foldable's default foldr.
newtype Endo a = Endo { appEndo :: a -> a }

instance Semigroup (Endo a) where
  Endo f <> Endo g = Endo (f . g)

instance Monoid (Endo a) where
  mempty = Endo id

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
  foldr f z t = appEndo (foldMap (Endo . f) t) z
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

-- ---- Data.Char (GHC's Unicode tables) --------------------------------------------

foreign import prim "charCategory" rhci_charCategory :: Char -> Int
foreign import prim "charUpper" rhci_toUpper :: Char -> Char
foreign import prim "charLower" rhci_toLower :: Char -> Char
foreign import prim "charTitle" rhci_toTitle :: Char -> Char
foreign import prim "isUpperCase" isUpperCase :: Char -> Bool
foreign import prim "isLowerCase" isLowerCase :: Char -> Bool

data GeneralCategory
  = UppercaseLetter | LowercaseLetter | TitlecaseLetter | ModifierLetter | OtherLetter
  | NonSpacingMark | SpacingCombiningMark | EnclosingMark
  | DecimalNumber | LetterNumber | OtherNumber
  | ConnectorPunctuation | DashPunctuation | OpenPunctuation | ClosePunctuation
  | InitialQuote | FinalQuote | OtherPunctuation
  | MathSymbol | CurrencySymbol | ModifierSymbol | OtherSymbol
  | Space | LineSeparator | ParagraphSeparator
  | Control | Format | Surrogate | PrivateUse | NotAssigned
  deriving (Show, Read, Eq, Ord, Enum, Bounded)

generalCategory :: Char -> GeneralCategory
generalCategory c = toEnum (rhci_charCategory c)

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

-- By category number: 0-4 letters, 5-7 marks, 8-10 numbers, 11-17
-- punctuation, 18-21 symbols, 22-24 separators, 25 Control.
rhci_catIn :: Int -> Int -> Char -> Bool
rhci_catIn lo hi c = let k = rhci_charCategory c in rhci_intGe k lo && rhci_intLe k hi

isControl :: Char -> Bool
isControl = rhci_catIn 25 25

isPrint :: Char -> Bool
isPrint c = not (rhci_catIn 23 29 c)

isUpper :: Char -> Bool
isUpper c = let k = rhci_charCategory c in rhci_intEq k 0 || rhci_intEq k 2

isLower :: Char -> Bool
isLower = rhci_catIn 1 1

isAlpha :: Char -> Bool
isAlpha = rhci_catIn 0 4

isLetter :: Char -> Bool
isLetter = rhci_catIn 0 4

isMark :: Char -> Bool
isMark = rhci_catIn 5 7

isAlphaNum :: Char -> Bool
isAlphaNum c = let k = rhci_charCategory c in rhci_intLe k 4 || (rhci_intGe k 8 && rhci_intLe k 10)

isNumber :: Char -> Bool
isNumber = rhci_catIn 8 10

isPunctuation :: Char -> Bool
isPunctuation = rhci_catIn 11 17

isSymbol :: Char -> Bool
isSymbol = rhci_catIn 18 21

isSeparator :: Char -> Bool
isSeparator = rhci_catIn 22 24

isAsciiUpper :: Char -> Bool
isAsciiUpper c = c >= 'A' && c <= 'Z'

isAsciiLower :: Char -> Bool
isAsciiLower c = c >= 'a' && c <= 'z'

toUpper :: Char -> Char
toUpper = rhci_toUpper

toLower :: Char -> Char
toLower = rhci_toLower

toTitle :: Char -> Char
toTitle = rhci_toTitle

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

-- ---- Read -------------------------------------------------------------------------
-- Ported from base (Text.ParserCombinators.ReadP and ReadPrec, Text.Read.Lex,
-- GHC.Read, Text.Read), so what parses, what is ambiguous, and what `reads`
-- leaves over are GHC's.

type ReadS a = String -> [(a, String)]

-- ReadP's parser states. Final holds a non-empty list (NonEmpty in base).
data P a
  = Get (Char -> P a)
  | Look (String -> P a)
  | Fail
  | Result a (P a)
  | Final [(a, String)]

rhci_returnP :: a -> P a
rhci_returnP x = Result x Fail

rhci_bindP :: P a -> (a -> P b) -> P b
rhci_bindP (Get f) k = Get (\c -> rhci_bindP (f c) k)
rhci_bindP (Look f) k = Look (\s -> rhci_bindP (f s) k)
rhci_bindP Fail _ = Fail
rhci_bindP (Result x p) k = rhci_altP (k x) (rhci_bindP p k)
rhci_bindP (Final rs) k = rhci_final [ys' | (x, s) <- rs, ys' <- rhci_run (k x) s]

rhci_altP :: P a -> P a -> P a
rhci_altP (Get f1) (Get f2) = Get (\c -> rhci_altP (f1 c) (f2 c))
rhci_altP (Result x p) q = Result x (rhci_altP p q)
rhci_altP p (Result x q) = Result x (rhci_altP p q)
rhci_altP Fail p = p
rhci_altP p Fail = p
rhci_altP (Final r) (Final t) = Final (r ++ t)
rhci_altP (Final r) (Look f) = Look (\s -> Final (r ++ rhci_run (f s) s))
rhci_altP (Final r) p = Look (\s -> Final (r ++ rhci_run p s))
rhci_altP (Look f) (Final r) = Look (\s -> Final (rhci_run (f s) s ++ r))
rhci_altP p (Final r) = Look (\s -> Final (rhci_run p s ++ r))
rhci_altP (Look f) (Look g) = Look (\s -> rhci_altP (f s) (g s))
rhci_altP (Look f) p = Look (\s -> rhci_altP (f s) p)
rhci_altP p (Look f) = Look (\s -> rhci_altP p (f s))

rhci_final :: [(a, String)] -> P a
rhci_final [] = Fail
rhci_final rs = Final rs

rhci_run :: P a -> ReadS a
rhci_run (Get f) (c:s) = rhci_run (f c) s
rhci_run (Look f) s = rhci_run (f s) s
rhci_run (Result x p) s = (x, s) : rhci_run p s
rhci_run (Final rs) _ = rs
rhci_run _ _ = []

-- base's ReadP is rank-2: forall b. (a -> P b) -> P b. rhci has no rank-2
-- types, so b is fixed to () and the few places that instantiate it
-- differently (running a parser, <++, gather) coerce; the machine is
-- untyped, so the coercion is the identity.
foreign import prim "coerce" rhci_coerce :: a -> b

newtype ReadP a = R ((a -> P ()) -> P ())

rhci_runR :: ReadP a -> P a
rhci_runR (R f) = rhci_coerce (f (\a -> rhci_coerce (rhci_returnP a)))

instance Functor ReadP where
  fmap h (R f) = R (\k -> f (\a -> k (h a)))

instance Applicative ReadP where
  pure x = R (\k -> k x)
  R mf <*> R mx = R (\k -> mf (\f -> mx (\x -> k (f x))))

instance Monad ReadP where
  R m >>= f = R (\k -> m (\a -> case f a of R m' -> m' k))

instance MonadFail ReadP where
  fail _ = R (\_ -> Fail)

rhci_getP :: ReadP Char
rhci_getP = R Get

rhci_lookP :: ReadP String
rhci_lookP = R Look

rhci_pfailP :: ReadP a
rhci_pfailP = R (\_ -> Fail)

rhci_plusP :: ReadP a -> ReadP a -> ReadP a
rhci_plusP (R f1) (R f2) = R (\k -> rhci_altP (f1 k) (f2 k))

-- Left-biased choice: q only if p yields nothing.
rhci_leftP :: ReadP a -> ReadP a -> ReadP a
rhci_leftP p0 q = rhci_lookP >>= \s -> probe (rhci_runR p0) s 0
  where
    probe (Get f) (c:s) n = probe (f c) s (rhci_intAdd n 1)
    probe (Look f) s n = probe (f s) s n
    probe p@(Result _ _) _ n = discard n >> R (rhci_bindP p)
    probe (Final r) _ _ = R (rhci_bindP (Final r))
    probe _ _ _ = q
    discard n = if rhci_intEq n 0 then return () else rhci_getP >> discard (rhci_intSub n 1)

rhci_gather :: ReadP a -> ReadP (String, a)
rhci_gather (R m) =
  R (\k -> gath id (rhci_coerce (m (\a -> rhci_coerce (rhci_returnP (\s -> k (s, a)))))))
  where
    gath l (Get f) = Get (\c -> gath (l . (c:)) (f c))
    gath _ Fail = Fail
    gath l (Look f) = Look (\s -> gath l (f s))
    gath l (Result k p) = rhci_altP (k (l [])) (gath l p)
    gath _ (Final _) = errorWithoutStackTrace "do not use readS_to_P in gather!"

rhci_satisfy :: (Char -> Bool) -> ReadP Char
rhci_satisfy p = rhci_getP >>= \c -> if p c then return c else rhci_pfailP

rhci_char :: Char -> ReadP Char
rhci_char c = rhci_satisfy (c ==)

rhci_string :: String -> ReadP String
rhci_string this = rhci_lookP >>= scan this
  where
    scan [] _ = return this
    scan (x:xs) (y:ys) | x == y = rhci_getP >> scan xs ys
    scan _ _ = rhci_pfailP

rhci_munch :: (Char -> Bool) -> ReadP String
rhci_munch p = rhci_lookP >>= scan
  where
    scan (c:cs) | p c = rhci_getP >> scan cs >>= \s -> return (c : s)
    scan _ = return ""

rhci_munch1 :: (Char -> Bool) -> ReadP String
rhci_munch1 p = rhci_getP >>= \c -> if p c then rhci_munch p >>= \s -> return (c : s) else rhci_pfailP

rhci_choiceP :: [ReadP a] -> ReadP a
rhci_choiceP [] = rhci_pfailP
rhci_choiceP [p] = p
rhci_choiceP (p:ps) = rhci_plusP p (rhci_choiceP ps)

rhci_skipSpaces :: ReadP ()
rhci_skipSpaces = rhci_lookP >>= skip
  where
    skip (c:s) | isSpace c = rhci_getP >> skip s
    skip _ = return ()

rhci_readP_to_S :: ReadP a -> ReadS a
rhci_readP_to_S p = rhci_run (rhci_runR p)

rhci_readS_to_P :: ReadS a -> ReadP a
rhci_readS_to_P r = R (\k -> Look (\s -> rhci_final [bs'' | (a, s') <- r s, bs'' <- rhci_run (k a) s']))

-- ReadPrec

type Prec = Int

newtype ReadPrec a = RP (Prec -> ReadP a)

instance Functor ReadPrec where
  fmap h (RP f) = RP (\n -> fmap h (f n))

instance Applicative ReadPrec where
  pure x = RP (\_ -> pure x)
  RP ff <*> RP fx = RP (\n -> ff n <*> fx n)

instance Monad ReadPrec where
  RP f >>= k = RP (\n -> f n >>= \a -> case k a of RP f' -> f' n)

instance MonadFail ReadPrec where
  fail s = RP (\_ -> fail s)

minPrec :: Prec
minPrec = 0

lift :: ReadP a -> ReadPrec a
lift m = RP (\_ -> m)

step :: ReadPrec a -> ReadPrec a
step (RP f) = RP (\n -> f (rhci_intAdd n 1))

reset :: ReadPrec a -> ReadPrec a
reset (RP f) = RP (\_ -> f minPrec)

prec :: Prec -> ReadPrec a -> ReadPrec a
prec n (RP f) = RP (\c -> if rhci_intLe c n then f n else rhci_pfailP)

get :: ReadPrec Char
get = lift rhci_getP

look :: ReadPrec String
look = lift rhci_lookP

(+++) :: ReadPrec a -> ReadPrec a -> ReadPrec a
RP f1 +++ RP f2 = RP (\n -> rhci_plusP (f1 n) (f2 n))

(<++) :: ReadPrec a -> ReadPrec a -> ReadPrec a
RP f1 <++ RP f2 = RP (\n -> rhci_leftP (f1 n) (f2 n))

pfail :: ReadPrec a
pfail = lift rhci_pfailP

choice :: [ReadPrec a] -> ReadPrec a
choice ps = foldr (+++) pfail ps

readPrec_to_P :: ReadPrec a -> (Int -> ReadP a)
readPrec_to_P (RP f) = f

readP_to_Prec :: (Int -> ReadP a) -> ReadPrec a
readP_to_Prec f = RP f

readPrec_to_S :: ReadPrec a -> (Int -> ReadS a)
readPrec_to_S (RP f) n = rhci_readP_to_S (f n)

readS_to_Prec :: (Int -> ReadS a) -> ReadPrec a
readS_to_Prec f = RP (\n -> rhci_readS_to_P (f n))

-- Text.Read.Lex

data Lexeme
  = Char Char
  | String String
  | Punc String
  | Ident String
  | Symbol String
  | Number Number
  | EOF
  deriving (Eq, Show)

data Number
  = MkNumber Int [Int]
  | MkDecimal [Int] (Maybe [Int]) (Maybe Integer)
  deriving (Eq, Show)

rhci_val :: Integer -> [Int] -> Integer
rhci_val base = go 0
  where
    go r [] = r
    go r (d:ds) = let r' = r * base + toInteger d in r' `seq` go r' ds

rhci_numberToInteger :: Number -> Maybe Integer
rhci_numberToInteger (MkNumber base iPart) = Just (rhci_val (toInteger base) iPart)
rhci_numberToInteger (MkDecimal iPart Nothing Nothing) = Just (rhci_val 10 iPart)
rhci_numberToInteger _ = Nothing

-- numberToRational as (numerator, denominator), not reduced.
rhci_numberToRational :: Number -> (Integer, Integer)
rhci_numberToRational (MkNumber base iPart) = (rhci_val (toInteger base) iPart, 1)
rhci_numberToRational (MkDecimal iPart mFPart mExp) =
  let i = rhci_val 10 iPart
  in case (mFPart, mExp) of
       (Nothing, Nothing) -> (i, 1)
       (Nothing, Just e) -> if e >= 0 then (i * 10 ^ e, 1) else (i, 10 ^ negate e)
       (Just fPart, Nothing) -> rhci_fracExp 0 i fPart
       (Just fPart, Just e) -> rhci_fracExp e i fPart

rhci_fracExp :: Integer -> Integer -> [Int] -> (Integer, Integer)
rhci_fracExp e mant [] = if e < 0 then (mant, 10 ^ negate e) else (mant * 10 ^ e, 1)
rhci_fracExp e mant (d:ds) =
  let e' = e - 1
      mant' = mant * 10 + toInteger d
  in e' `seq` mant' `seq` rhci_fracExp e' mant' ds

-- Nothing means Infinity: the exponent is far beyond the type's range.
rhci_numberToRangedRational :: (Int, Int) -> Number -> Maybe (Integer, Integer)
rhci_numberToRangedRational (neg, pos) n@(MkDecimal iPart mFPart (Just e))
  | e > toInteger (maxBound :: Int) || e < toInteger (minBound :: Int) = Nothing
  | otherwise =
      let mFirstDigit = case dropWhile (0 ==) iPart of
            iPart'@(_ : _) -> Just (length iPart')
            [] -> case mFPart of
                    Nothing -> Nothing
                    Just fPart -> case span (0 ==) fPart of
                                    (_, []) -> Nothing
                                    (zeroes, _) -> Just (negate (length zeroes))
      in case mFirstDigit of
           Nothing -> Just (0, 1)
           Just firstDigit ->
             let firstDigit' = firstDigit + fromInteger e
             in if firstDigit' > (pos + 3)
                  then Nothing
                  else if firstDigit' < (neg - 3)
                    then Just (0, 1)
                    else Just (rhci_numberToRational n)
rhci_numberToRangedRational _ n = Just (rhci_numberToRational n)

rhci_lexL :: ReadP Lexeme
rhci_lexL = rhci_skipSpaces >> rhci_lexToken

rhci_expect :: Lexeme -> ReadP ()
rhci_expect lexeme = rhci_skipSpaces >> rhci_lexToken >>= \thing ->
  if thing == lexeme then return () else rhci_pfailP

rhci_hsLex :: ReadP String
rhci_hsLex = rhci_skipSpaces >> rhci_gather rhci_lexToken >>= \(s, _) -> return s

rhci_lexToken :: ReadP Lexeme
rhci_lexToken =
  rhci_plusP rhci_lexEOF (rhci_plusP rhci_lexLitChar (rhci_plusP rhci_lexString
    (rhci_plusP rhci_lexPunc (rhci_plusP rhci_lexSymbol (rhci_plusP rhci_lexId rhci_lexNumber)))))

rhci_lexEOF :: ReadP Lexeme
rhci_lexEOF = rhci_lookP >>= \s -> if null s then return EOF else rhci_pfailP

rhci_lexPunc :: ReadP Lexeme
rhci_lexPunc = rhci_satisfy rhci_isPuncChar >>= \c -> return (Punc [c])

rhci_isPuncChar :: Char -> Bool
rhci_isPuncChar c = c `elem` ",;()[]{}`"

rhci_lexSymbol :: ReadP Lexeme
rhci_lexSymbol = rhci_munch1 rhci_isSymbolChar >>= \s ->
  if s `elem` ["..", "::", "=", "\\", "|", "<-", "->", "@", "~", "=>"]
    then return (Punc s)
    else return (Symbol s)

-- By category number: 11 ConnectorPunctuation, 12 DashPunctuation,
-- 17 OtherPunctuation, 18-21 the symbol categories.
rhci_isSymbolChar :: Char -> Bool
rhci_isSymbolChar c = not (rhci_isPuncChar c) && symbolic (rhci_charCategory c)
  where
    symbolic k
      | rhci_intGe k 18 && rhci_intLe k 21 = True
      | rhci_intEq k 12 = True
      | rhci_intEq k 17 = not (c `elem` "'\"")
      | rhci_intEq k 11 = c /= '_'
      | otherwise = False

rhci_lexId :: ReadP Lexeme
rhci_lexId = rhci_satisfy isIdsChar >>= \c -> rhci_munch isIdfChar >>= \s -> return (Ident (c : s))
  where
    isIdsChar c = isAlpha c || c == '_'
    isIdfChar c = isAlphaNum c || c `elem` "_'"

rhci_lexLitChar :: ReadP Lexeme
rhci_lexLitChar = rhci_char '\'' >> rhci_lexCharE >>= \(c, esc) ->
  if esc || c /= '\'' then rhci_char '\'' >> return (Char c) else rhci_pfailP

rhci_lexChar :: ReadP Char
rhci_lexChar = rhci_lexCharE >>= \(c, _) -> consumeEmpties >> return c
  where
    consumeEmpties = rhci_lookP >>= \rest -> case rest of
      ('\\':'&':_) -> rhci_string "\\&" >> consumeEmpties
      _ -> return ()

rhci_lexCharE :: ReadP (Char, Bool)
rhci_lexCharE = rhci_getP >>= \c1 ->
  if c1 == '\\' then rhci_lexEsc >>= \c2 -> return (c2, True) else return (c1, False)

rhci_lexEsc :: ReadP Char
rhci_lexEsc = rhci_plusP rhci_lexEscChar (rhci_plusP rhci_lexNumeric (rhci_plusP rhci_lexCntrlChar rhci_lexAscii))

rhci_lexEscChar :: ReadP Char
rhci_lexEscChar = rhci_getP >>= \c -> case c of
  'a' -> return '\a'
  'b' -> return '\b'
  'f' -> return '\f'
  'n' -> return '\n'
  'r' -> return '\r'
  't' -> return '\t'
  'v' -> return '\v'
  '\\' -> return '\\'
  '"' -> return '"'
  '\'' -> return '\''
  _ -> rhci_pfailP

rhci_lexNumeric :: ReadP Char
rhci_lexNumeric =
  rhci_leftP rhci_lexBaseChar (return 10) >>= \base ->
  rhci_lexInteger base >>= \n ->
  if n <= 1114111 then return (chr (fromInteger n)) else rhci_pfailP

rhci_lexCntrlChar :: ReadP Char
rhci_lexCntrlChar = rhci_char '^' >> rhci_getP >>= \c ->
  if c >= '@' && c <= '_' then return (chr (rhci_intSub (ord c) 64)) else rhci_pfailP

rhci_lexAscii :: ReadP Char
rhci_lexAscii = rhci_choiceP
  (rhci_leftP (rhci_string "SOH" >> return '\1') (rhci_string "SO" >> return '\14')
   : map (\(s, c) -> rhci_string s >> return (chr c))
       [ ("NUL", 0), ("STX", 2), ("ETX", 3), ("EOT", 4), ("ENQ", 5), ("ACK", 6), ("BEL", 7)
       , ("BS", 8), ("HT", 9), ("LF", 10), ("VT", 11), ("FF", 12), ("CR", 13), ("SI", 15)
       , ("DLE", 16), ("DC1", 17), ("DC2", 18), ("DC3", 19), ("DC4", 20), ("NAK", 21)
       , ("SYN", 22), ("ETB", 23), ("CAN", 24), ("EM", 25), ("SUB", 26), ("ESC", 27)
       , ("FS", 28), ("GS", 29), ("RS", 30), ("US", 31), ("SP", 32), ("DEL", 127) ])

rhci_lexString :: ReadP Lexeme
rhci_lexString = rhci_char '"' >> body id
  where
    body f = lexStrItem >>= \(c, esc) ->
      if c /= '"' || esc then body (f . (c:)) else return (String (f ""))
    lexStrItem = rhci_plusP (lexEmpty >> lexStrItem) rhci_lexCharE
    lexEmpty = rhci_char '\\' >> rhci_getP >>= \c ->
      if c == '&' then return ()
      else if isSpace c then rhci_skipSpaces >> rhci_char '\\' >> return ()
      else rhci_pfailP

rhci_lexNumber :: ReadP Lexeme
rhci_lexNumber = rhci_leftP rhci_lexHexOct rhci_lexDecNumber

rhci_lexHexOct :: ReadP Lexeme
rhci_lexHexOct = rhci_char '0' >> rhci_lexBaseChar >>= \base ->
  rhci_lexDigits base >>= \digits -> return (Number (MkNumber base digits))

rhci_lexBaseChar :: ReadP Int
rhci_lexBaseChar = rhci_getP >>= \c -> case c of
  'o' -> return 8
  'O' -> return 8
  'x' -> return 16
  'X' -> return 16
  _ -> rhci_pfailP

rhci_lexDecNumber :: ReadP Lexeme
rhci_lexDecNumber =
  rhci_lexDigits 10 >>= \xs ->
  rhci_leftP rhci_lexFrac (return Nothing) >>= \mFrac ->
  rhci_leftP rhci_lexExp (return Nothing) >>= \mExp ->
  return (Number (MkDecimal xs mFrac mExp))

rhci_lexFrac :: ReadP (Maybe [Int])
rhci_lexFrac = rhci_char '.' >> rhci_lexDigits 10 >>= \fraction -> return (Just fraction)

rhci_lexExp :: ReadP (Maybe Integer)
rhci_lexExp = rhci_plusP (rhci_char 'e') (rhci_char 'E') >>
  rhci_plusP signedExp (rhci_lexInteger 10) >>= \e -> return (Just e)
  where
    signedExp = rhci_plusP (rhci_char '-') (rhci_char '+') >>= \c ->
      rhci_lexInteger 10 >>= \n -> return (if c == '-' then negate n else n)

rhci_lexDigits :: Int -> ReadP [Int]
rhci_lexDigits base = rhci_lookP >>= \s -> scan s id >>= \xs ->
  if null xs then rhci_pfailP else return xs
  where
    scan (c:cs) f = case rhci_valDig base c of
      Just n -> rhci_getP >> scan cs (f . (n:))
      Nothing -> return (f [])
    scan [] f = return (f [])

rhci_lexInteger :: Int -> ReadP Integer
rhci_lexInteger base = rhci_lexDigits base >>= \xs -> return (rhci_val (toInteger base) xs)

rhci_valDig :: Int -> Char -> Maybe Int
rhci_valDig base c
  | rhci_intEq base 8 = if c >= '0' && c <= '7' then Just (rhci_intSub (ord c) 48) else Nothing
  | rhci_intEq base 10 = if c >= '0' && c <= '9' then Just (rhci_intSub (ord c) 48) else Nothing
  | c >= '0' && c <= '9' = Just (rhci_intSub (ord c) 48)
  | c >= 'a' && c <= 'f' = Just (rhci_intSub (ord c) 87)
  | c >= 'A' && c <= 'F' = Just (rhci_intSub (ord c) 55)
  | otherwise = Nothing

-- GHC.Read

class Read a where
  readsPrec :: Int -> ReadS a
  readList :: ReadS [a]
  readPrec :: ReadPrec a
  readListPrec :: ReadPrec [a]
  readsPrec = readPrec_to_S readPrec
  readList = readPrec_to_S (rhci_list readPrec) 0
  readPrec = readS_to_Prec readsPrec
  readListPrec = readS_to_Prec (\_ -> readList)

readListDefault :: Read a => ReadS [a]
readListDefault = readPrec_to_S readListPrec 0

readListPrecDefault :: Read a => ReadPrec [a]
readListPrecDefault = rhci_list readPrec

readParen :: Bool -> ReadS a -> ReadS a
readParen b g = if b then mandatory else optional
  where
    optional r = g r ++ mandatory r
    mandatory r = [(x, u) | (open, s) <- lex r, open == "(", (x, t) <- optional s, (close, u) <- lex t, close == ")"]

lex :: ReadS String
lex s = rhci_readP_to_S rhci_hsLex s

lexLitChar :: ReadS String
lexLitChar = rhci_readP_to_S (rhci_gather rhci_lexChar >>= \(s, _) -> return (removeNulls s))
  where
    removeNulls [] = []
    removeNulls ('\\':'&':xs) = removeNulls xs
    removeNulls (first:rest) = first : removeNulls rest

readLitChar :: ReadS Char
readLitChar = rhci_readP_to_S rhci_lexChar

lexP :: ReadPrec Lexeme
lexP = lift rhci_lexL

rhci_expectP :: Lexeme -> ReadPrec ()
rhci_expectP lexeme = lift (rhci_expect lexeme)

rhci_expectCharP :: Char -> ReadPrec a -> ReadPrec a
rhci_expectCharP c a = get >>= \q -> if q == c then a else pfail

rhci_skipSpacesThenP :: ReadPrec a -> ReadPrec a
rhci_skipSpacesThenP m = look >>= skip
  where
    skip (c:s) | isSpace c = get >> skip s
    skip _ = m

rhci_paren :: ReadPrec a -> ReadPrec a
rhci_paren p = rhci_skipSpacesThenP (rhci_paren' p)

rhci_paren' :: ReadPrec a -> ReadPrec a
rhci_paren' p = rhci_expectCharP '(' (reset p >>= \x -> rhci_skipSpacesThenP (rhci_expectCharP ')' (pure x)))

parens :: ReadPrec a -> ReadPrec a
parens p = optional
  where
    optional = rhci_skipSpacesThenP (p +++ mandatory)
    mandatory = rhci_paren' optional

rhci_list :: ReadPrec a -> ReadPrec [a]
rhci_list readx = parens (rhci_expectP (Punc "[") >> (listRest False +++ listNext))
  where
    listRest started = lexP >>= \l -> case l of
      Punc c -> if c == "]" then return []
                else if c == "," && started then listNext
                else pfail
      _ -> pfail
    listNext = reset readx >>= \x -> listRest True >>= \xs -> return (x : xs)

rhci_choose :: [(String, ReadPrec a)] -> ReadPrec a
rhci_choose sps = foldr ((+++) . tryOne) pfail sps
  where
    tryOne (s, p) = lexP >>= \token -> case token of
      Ident s' -> if s == s' then p else pfail
      Symbol s' -> if s == s' then p else pfail
      _ -> pfail

rhci_readField :: String -> ReadPrec a -> ReadPrec a
rhci_readField fieldName readVal =
  rhci_expectP (Ident fieldName) >> rhci_expectP (Punc "=") >> readVal

rhci_readSymField :: String -> ReadPrec a -> ReadPrec a
rhci_readSymField fieldName readVal =
  rhci_expectP (Punc "(") >> rhci_expectP (Symbol fieldName) >> rhci_expectP (Punc ")")
    >> rhci_expectP (Punc "=") >> readVal

-- What derived instances call (user definitions cannot capture them).
rhci_readPrec :: Read a => ReadPrec a
rhci_readPrec = readPrec

rhci_readListDefault :: Read a => ReadS [a]
rhci_readListDefault = readListDefault

rhci_readListPrecDefault :: Read a => ReadPrec [a]
rhci_readListPrecDefault = readListPrecDefault

rhci_parens :: ReadPrec a -> ReadPrec a
rhci_parens = parens

rhci_prec :: Prec -> ReadPrec a -> ReadPrec a
rhci_prec = prec

rhci_step :: ReadPrec a -> ReadPrec a
rhci_step = step

rhci_reset :: ReadPrec a -> ReadPrec a
rhci_reset = reset

rhci_altRP :: ReadPrec a -> ReadPrec a -> ReadPrec a
rhci_altRP = (+++)

rhci_pfailRP :: ReadPrec a
rhci_pfailRP = pfail

rhci_returnRP :: a -> ReadPrec a
rhci_returnRP = return

rhci_bindRP :: ReadPrec a -> (a -> ReadPrec b) -> ReadPrec b
rhci_bindRP = (>>=)

rhci_thenRP :: ReadPrec a -> ReadPrec b -> ReadPrec b
rhci_thenRP m k = m >>= \_ -> k

rhci_identL, rhci_symbolL, rhci_puncL :: String -> Lexeme
rhci_identL = Ident
rhci_symbolL = Symbol
rhci_puncL = Punc

instance Read Char where
  readPrec = parens (lexP >>= \l -> case l of
    Char c -> return c
    _ -> pfail)
  readListPrec = parens ((lexP >>= \l -> case l of
                            String s -> return s
                            _ -> pfail)
                         +++ readListPrecDefault)
  readList = readListDefault

instance Read Bool where
  readPrec = parens (lexP >>= \l -> case l of
    Ident s -> if s == "True" then return True else if s == "False" then return False else pfail
    _ -> pfail)
  readListPrec = readListPrecDefault
  readList = readListDefault

instance Read Ordering where
  readPrec = parens (lexP >>= \l -> case l of
    Ident s -> if s == "LT" then return LT else if s == "EQ" then return EQ
               else if s == "GT" then return GT else pfail
    _ -> pfail)
  readListPrec = readListPrecDefault
  readList = readListDefault

instance Read a => Read [a] where
  readPrec = readListPrec
  readListPrec = readListPrecDefault
  readList = readListDefault

instance Read Lexeme where
  readPrec = lexP
  readListPrec = readListPrecDefault
  readList = readListDefault

rhci_readNumber :: Num a => (Lexeme -> ReadPrec a) -> ReadPrec a
rhci_readNumber convert = parens (lexP >>= \x ->
  if x == Symbol "-" then lexP >>= \y -> convert y >>= \n -> return (negate n) else convert x)

rhci_convertInt :: Num a => Lexeme -> ReadPrec a
rhci_convertInt (Number n) = case rhci_numberToInteger n of
  Just i -> return (fromInteger i)
  Nothing -> pfail
rhci_convertInt _ = pfail

rhci_convertFrac :: Lexeme -> ReadPrec Double
rhci_convertFrac (Ident s)
  | s == "NaN" = return (0 / 0)
  | s == "Infinity" = return (1 / 0)
  | otherwise = pfail
rhci_convertFrac (Number n) = case rhci_numberToRangedRational (negate 1021, 1024) n of
  Nothing -> return (1 / 0)
  Just (p, q) -> return (rhci_doubleFromRational p q)
rhci_convertFrac _ = pfail

instance Read Int where
  readPrec = rhci_readNumber rhci_convertInt
  readListPrec = readListPrecDefault
  readList = readListDefault

instance Read Integer where
  readPrec = rhci_readNumber rhci_convertInt
  readListPrec = readListPrecDefault
  readList = readListDefault

instance Read Double where
  readPrec = rhci_readNumber rhci_convertFrac
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Integral a, Read a) => Read (Ratio a) where
  readPrec = parens (prec 7 (step readPrec >>= \x -> rhci_expectP (Symbol "%") >> step readPrec >>= \y -> return (x % y)))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance Read () where
  readPrec = parens (rhci_paren (return ()))
  readListPrec = readListPrecDefault
  readList = readListDefault

rhci_wrapTup :: ReadPrec a -> ReadPrec a
rhci_wrapTup p = parens (rhci_paren p)

rhci_readComma :: ReadPrec ()
rhci_readComma = rhci_expectP (Punc ",")

rhci_readTup2 :: (Read a, Read b) => ReadPrec (a, b)
rhci_readTup2 = readPrec >>= \x -> rhci_readComma >> readPrec >>= \y -> return (x, y)

rhci_readTup4 :: (Read a, Read b, Read c, Read d) => ReadPrec (a, b, c, d)
rhci_readTup4 = rhci_readTup2 >>= \(a, b) -> rhci_readComma >> rhci_readTup2 >>= \(c, d) -> return (a, b, c, d)

instance (Read a, Read b) => Read (a, b) where
  readPrec = rhci_wrapTup rhci_readTup2
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Read a, Read b, Read c) => Read (a, b, c) where
  readPrec = rhci_wrapTup (rhci_readTup2 >>= \(a, b) -> rhci_readComma >> readPrec >>= \c -> return (a, b, c))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Read a, Read b, Read c, Read d) => Read (a, b, c, d) where
  readPrec = rhci_wrapTup rhci_readTup4
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Read a, Read b, Read c, Read d, Read e) => Read (a, b, c, d, e) where
  readPrec = rhci_wrapTup (rhci_readTup4 >>= \(a, b, c, d) -> rhci_readComma >> readPrec >>= \e ->
                             return (a, b, c, d, e))
  readListPrec = readListPrecDefault
  readList = readListDefault

-- Text.Read

reads :: Read a => ReadS a
reads = readsPrec minPrec

readEither :: Read a => String -> Either String a
readEither s = case [x | (x, rest) <- readPrec_to_S read' minPrec s, null rest] of
    [x] -> Right x
    [] -> Left "Prelude.read: no parse"
    _ -> Left "Prelude.read: ambiguous parse"
  where
    read' = readPrec >>= \x -> lift rhci_skipSpaces >> return x

readMaybe :: Read a => String -> Maybe a
readMaybe s = case readEither s of
  Left _ -> Nothing
  Right a -> Just a

read :: Read a => String -> a
read s = either errorWithoutStackTrace id (readEither s)

readIO :: Read a => String -> IO a
readIO s = case [x | (x, t) <- reads s, (a, b) <- lex t, null a, null b] of
  [x] -> return x
  [] -> ioError (userError "Prelude.readIO: no parse")
  _ -> ioError (userError "Prelude.readIO: ambiguous parse")

readLn :: Read a => IO a
readLn = getLine >>= readIO

-- ---- Alternative, MonadPlus and the rest of Control.Monad ---------------------------

class Applicative f => Alternative f where
  empty :: f a
  (<|>) :: f a -> f a -> f a
  some :: f a -> f [a]
  many :: f a -> f [a]
  some v = some_v
    where
      many_v = some_v <|> pure []
      some_v = liftA2 (:) v many_v
  many v = many_v
    where
      many_v = some_v <|> pure []
      some_v = liftA2 (:) v many_v

instance Alternative Maybe where
  empty = Nothing
  Nothing <|> r = r
  l <|> _ = l

instance Alternative [] where
  empty = []
  (<|>) = (++)

instance Alternative ReadP where
  empty = rhci_pfailP
  (<|>) = rhci_plusP

instance Alternative ReadPrec where
  empty = pfail
  (<|>) = (+++)

class (Alternative m, Monad m) => MonadPlus m where
  mzero :: m a
  mplus :: m a -> m a -> m a
  mzero = empty
  mplus = (<|>)

instance MonadPlus Maybe
instance MonadPlus []
instance MonadPlus ReadP
instance MonadPlus ReadPrec

guard :: Alternative f => Bool -> f ()
guard True = pure ()
guard False = empty

asum :: (Foldable t, Alternative f) => t (f a) -> f a
asum = foldr (<|>) empty

msum :: (Foldable t, MonadPlus m) => t (m a) -> m a
msum = asum

mfilter :: MonadPlus m => (a -> Bool) -> m a -> m a
mfilter p ma = do
  a <- ma
  if p a then return a else mzero

optional :: Alternative f => f a -> f (Maybe a)
optional v = Just <$> v <|> pure Nothing

forever :: Applicative f => f a -> f b
forever a = let a' = a *> a' in a'

foldM_ :: (Foldable t, Monad m) => (b -> a -> m b) -> b -> t a -> m ()
foldM_ f a xs = foldM f a xs >> return ()

foldrM :: (Foldable t, Monad m) => (a -> b -> m b) -> b -> t a -> m b
foldrM f z0 xs = foldl c return xs z0
  where c k x z = f x z >>= k

foldlM :: (Foldable t, Monad m) => (b -> a -> m b) -> b -> t a -> m b
foldlM f z0 xs = foldr c return xs z0
  where c x k z = f z x >>= k

for_ :: (Foldable t, Applicative f) => t a -> (a -> f b) -> f ()
for_ = flip traverse_

liftA :: Applicative f => (a -> b) -> f a -> f b
liftA f a = pure f <*> a

liftA3 :: Applicative f => (a -> b -> c -> d) -> f a -> f b -> f c -> f d
liftA3 f a b c = liftA2 f a b <*> c

liftM3 :: Monad m => (a1 -> a2 -> a3 -> r) -> m a1 -> m a2 -> m a3 -> m r
liftM3 f m1 m2 m3 = do { x1 <- m1; x2 <- m2; x3 <- m3; return (f x1 x2 x3) }

liftM4 :: Monad m => (a1 -> a2 -> a3 -> a4 -> r) -> m a1 -> m a2 -> m a3 -> m a4 -> m r
liftM4 f m1 m2 m3 m4 = do { x1 <- m1; x2 <- m2; x3 <- m3; x4 <- m4; return (f x1 x2 x3 x4) }

liftM5 :: Monad m => (a1 -> a2 -> a3 -> a4 -> a5 -> r) -> m a1 -> m a2 -> m a3 -> m a4 -> m a5 -> m r
liftM5 f m1 m2 m3 m4 m5 = do { x1 <- m1; x2 <- m2; x3 <- m3; x4 <- m4; x5 <- m5; return (f x1 x2 x3 x4 x5) }

mapAndUnzipM :: Applicative m => (a -> m (b, c)) -> [a] -> m ([b], [c])
mapAndUnzipM f xs = unzip <$> traverse f xs

(<$!>) :: Monad m => (a -> b) -> m a -> m b
f <$!> m = do
  x <- m
  let z = f x
  z `seq` return z

(<**>) :: Applicative f => f a -> f (a -> b) -> f b
(<**>) = liftA2 (\a f -> f a)

-- mapAccumL/R (Data.Traversable's, which Data.List exports): base's state
-- applicatives, so they stay as lazy as GHC's.
newtype StateL s a = StateL (s -> (s, a))
newtype StateR s a = StateR (s -> (s, a))

rhci_runStateL :: StateL s a -> s -> (s, a)
rhci_runStateL (StateL f) = f

rhci_runStateR :: StateR s a -> s -> (s, a)
rhci_runStateR (StateR f) = f

instance Functor (StateL s) where
  fmap f (StateL k) = StateL (\s -> let (s', v) = k s in (s', f v))

instance Applicative (StateL s) where
  pure x = StateL (\s -> (s, x))
  StateL kf <*> StateL kv = StateL (\s -> let (s', f) = kf s
                                              (s'', v) = kv s'
                                          in (s'', f v))
  liftA2 f (StateL kx) (StateL ky) = StateL (\s -> let (s', x) = kx s
                                                       (s'', y) = ky s'
                                                   in (s'', f x y))

instance Functor (StateR s) where
  fmap f (StateR k) = StateR (\s -> let (s', v) = k s in (s', f v))

instance Applicative (StateR s) where
  pure x = StateR (\s -> (s, x))
  StateR kf <*> StateR kv = StateR (\s -> let (s', v) = kv s
                                              (s'', f) = kf s'
                                          in (s'', f v))
  liftA2 f (StateR kx) (StateR ky) = StateR (\s -> let (s', y) = ky s
                                                       (s'', x) = kx s'
                                                   in (s'', f x y))

mapAccumL :: Traversable t => (s -> a -> (s, b)) -> s -> t a -> (s, t b)
mapAccumL f s t = rhci_runStateL (traverse (\a -> StateL (\s' -> f s' a)) t) s

mapAccumR :: Traversable t => (s -> a -> (s, b)) -> s -> t a -> (s, t b)
mapAccumR f s t = rhci_runStateR (traverse (\a -> StateR (\s' -> f s' a)) t) s

-- ---- the rest of Data.List -------------------------------------------------------

singleton :: a -> [a]
singleton x = [x]

foldl1' :: (a -> a -> a) -> [a] -> a
foldl1' f (x:xs) = foldl' f x xs
foldl1' _ [] = errorWithoutStackTrace "Prelude.foldl1': empty list"

deleteFirstsBy :: (a -> a -> Bool) -> [a] -> [a] -> [a]
deleteFirstsBy eq = foldl (flip (deleteBy eq))

genericTake :: Integral i => i -> [a] -> [a]
genericTake n _ | n <= 0 = []
genericTake _ [] = []
genericTake n (x:xs) = x : genericTake (n - 1) xs

genericDrop :: Integral i => i -> [a] -> [a]
genericDrop n xs | n <= 0 = xs
genericDrop _ [] = []
genericDrop n (_:xs) = genericDrop (n - 1) xs

genericSplitAt :: Integral i => i -> [a] -> ([a], [a])
genericSplitAt n xs | n <= 0 = ([], xs)
genericSplitAt _ [] = ([], [])
genericSplitAt n (x:xs) = (x : xs', xs'')
  where (xs', xs'') = genericSplitAt (n - 1) xs

genericIndex :: Integral i => [a] -> i -> a
genericIndex (x:_) 0 = x
genericIndex (_:xs) n
  | n > 0 = genericIndex xs (n - 1)
  | otherwise = errorWithoutStackTrace "List.genericIndex: negative argument."
genericIndex _ _ = errorWithoutStackTrace "List.genericIndex: index too large."

genericReplicate :: Integral i => i -> a -> [a]
genericReplicate n x = genericTake n (repeat x)

zip5 :: [a] -> [b] -> [c] -> [d] -> [e] -> [(a, b, c, d, e)]
zip5 = zipWith5 (,,,,)

zip6 :: [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [(a, b, c, d, e, f)]
zip6 = zipWith6 (,,,,,)

zip7 :: [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [g] -> [(a, b, c, d, e, f, g)]
zip7 = zipWith7 (,,,,,,)

zipWith4 :: (a -> b -> c -> d -> e) -> [a] -> [b] -> [c] -> [d] -> [e]
zipWith4 z (a:as) (b:bs) (c:cs) (d:ds) = z a b c d : zipWith4 z as bs cs ds
zipWith4 _ _ _ _ _ = []

zipWith5 :: (a -> b -> c -> d -> e -> f) -> [a] -> [b] -> [c] -> [d] -> [e] -> [f]
zipWith5 z (a:as) (b:bs) (c:cs) (d:ds) (e:es) = z a b c d e : zipWith5 z as bs cs ds es
zipWith5 _ _ _ _ _ _ = []

zipWith6 :: (a -> b -> c -> d -> e -> f -> g) -> [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [g]
zipWith6 z (a:as) (b:bs) (c:cs) (d:ds) (e:es) (f:fs) = z a b c d e f : zipWith6 z as bs cs ds es fs
zipWith6 _ _ _ _ _ _ _ = []

zipWith7 :: (a -> b -> c -> d -> e -> f -> g -> h) -> [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [g] -> [h]
zipWith7 z (a:as) (b:bs) (c:cs) (d:ds) (e:es) (f:fs) (g:gs) = z a b c d e f g : zipWith7 z as bs cs ds es fs gs
zipWith7 _ _ _ _ _ _ _ _ = []

unzip4 :: [(a, b, c, d)] -> ([a], [b], [c], [d])
unzip4 = rhci_foldr (\(a, b, c, d) ~(as, bs, cs, ds) -> (a : as, b : bs, c : cs, d : ds)) ([], [], [], [])

unzip5 :: [(a, b, c, d, e)] -> ([a], [b], [c], [d], [e])
unzip5 = rhci_foldr (\(a, b, c, d, e) ~(as, bs, cs, ds, es) -> (a : as, b : bs, c : cs, d : ds, e : es))
                    ([], [], [], [], [])

unzip6 :: [(a, b, c, d, e, f)] -> ([a], [b], [c], [d], [e], [f])
unzip6 = rhci_foldr (\(a, b, c, d, e, f) ~(as, bs, cs, ds, es, fs) ->
                       (a : as, b : bs, c : cs, d : ds, e : es, f : fs)) ([], [], [], [], [], [])

unzip7 :: [(a, b, c, d, e, f, g)] -> ([a], [b], [c], [d], [e], [f], [g])
unzip7 = rhci_foldr (\(a, b, c, d, e, f, g) ~(as, bs, cs, ds, es, fs, gs) ->
                       (a : as, b : bs, c : cs, d : ds, e : es, f : fs, g : gs)) ([], [], [], [], [], [], [])

-- ---- Data.Bits (from base) -------------------------------------------------------------

foreign import prim "intAnd" rhci_intAnd :: Int -> Int -> Int
foreign import prim "intOr" rhci_intOr :: Int -> Int -> Int
foreign import prim "intXor" rhci_intXor :: Int -> Int -> Int
foreign import prim "intComplement" rhci_intComplement :: Int -> Int
foreign import prim "intShiftL" rhci_intShiftL :: Int -> Int -> Int
foreign import prim "intShiftRA" rhci_intShiftRA :: Int -> Int -> Int
foreign import prim "intShiftRL" rhci_intShiftRL :: Int -> Int -> Int
foreign import prim "intPopCount" rhci_intPopCount :: Int -> Int
foreign import prim "intClz" rhci_intClz :: Int -> Int
foreign import prim "intCtz" rhci_intCtz :: Int -> Int
foreign import prim "integerAnd" rhci_integerAnd :: Integer -> Integer -> Integer
foreign import prim "integerOr" rhci_integerOr :: Integer -> Integer -> Integer
foreign import prim "integerXor" rhci_integerXor :: Integer -> Integer -> Integer
foreign import prim "integerComplement" rhci_integerComplement :: Integer -> Integer
foreign import prim "integerShiftL" rhci_integerShiftL :: Integer -> Int -> Integer
foreign import prim "integerShiftR" rhci_integerShiftR :: Integer -> Int -> Integer
foreign import prim "integerPopCount" rhci_integerPopCount :: Integer -> Int
foreign import prim "integerTestBit" rhci_integerTestBit :: Integer -> Int -> Bool

class Eq a => Bits a where
  (.&.) :: a -> a -> a
  (.|.) :: a -> a -> a
  xor :: a -> a -> a
  complement :: a -> a
  shift :: a -> Int -> a
  rotate :: a -> Int -> a
  zeroBits :: a
  bit :: Int -> a
  setBit :: a -> Int -> a
  clearBit :: a -> Int -> a
  complementBit :: a -> Int -> a
  testBit :: a -> Int -> Bool
  bitSizeMaybe :: a -> Maybe Int
  bitSize :: a -> Int
  isSigned :: a -> Bool
  shiftL :: a -> Int -> a
  unsafeShiftL :: a -> Int -> a
  shiftR :: a -> Int -> a
  unsafeShiftR :: a -> Int -> a
  rotateL :: a -> Int -> a
  rotateR :: a -> Int -> a
  popCount :: a -> Int
  x `shift` i | i < 0 = x `shiftR` (negate i)
              | i > 0 = x `shiftL` i
              | otherwise = x
  x `rotate` i | i < 0 = x `rotateR` (negate i)
               | i > 0 = x `rotateL` i
               | otherwise = x
  zeroBits = clearBit (bit 0) 0
  bitSize b = fromMaybe (errorWithoutStackTrace "bitSize is undefined") (bitSizeMaybe b)
  x `setBit` i = x .|. bit i
  x `clearBit` i = x .&. complement (bit i)
  x `complementBit` i = x `xor` bit i
  x `shiftL` i = x `shift` i
  unsafeShiftL = shiftL
  x `shiftR` i = x `shift` (negate i)
  unsafeShiftR = shiftR
  x `rotateL` i = x `rotate` i
  x `rotateR` i = x `rotate` (negate i)

class Bits b => FiniteBits b where
  finiteBitSize :: b -> Int
  countLeadingZeros :: b -> Int
  countTrailingZeros :: b -> Int
  countLeadingZeros x = (w - 1) - go (w - 1)
    where
      go i | i < 0 = i
           | testBit x i = i
           | otherwise = go (i - 1)
      w = finiteBitSize x
  countTrailingZeros x = go 0
    where
      go i | i >= w = i
           | testBit x i = i
           | otherwise = go (i + 1)
      w = finiteBitSize x

bitDefault :: (Bits a, Num a) => Int -> a
bitDefault = \i -> 1 `shiftL` i

testBitDefault :: (Bits a, Num a) => a -> Int -> Bool
testBitDefault = \x i -> (x .&. bit i) /= 0

popCountDefault :: (Bits a, Num a) => a -> Int
popCountDefault = go 0
  where
    go c 0 = c
    go c w = c `seq` go (c + 1) (w .&. (w - 1))

toIntegralSized :: (Integral a, Integral b, Bits a, Bits b) => a -> Maybe b
toIntegralSized x = let y = fromIntegral x in if toInteger y == toInteger x then Just y else Nothing

oneBits :: Bits a => a
oneBits = complement zeroBits

(.^.) :: Bits a => a -> a -> a
(.^.) = xor

(.>>.) :: Bits a => a -> Int -> a
(.>>.) = shiftR

(.<<.) :: Bits a => a -> Int -> a
(.<<.) = shiftL

(!>>.) :: Bits a => a -> Int -> a
(!>>.) = unsafeShiftR

(!<<.) :: Bits a => a -> Int -> a
(!<<.) = unsafeShiftL

-- unsafeShift with a count outside 0..63 is undefined in GHC (the result
-- depends on the machine): rhci refuses it.
rhci_unsafeShiftCount :: Int -> Int
rhci_unsafeShiftCount i
  | i >= 0 && i < 64 = i
  | otherwise = errorWithoutStackTrace "rhci: unsafeShiftL/unsafeShiftR by a count outside 0..63 is undefined in GHC"

instance Bits Int where
  (.&.) = rhci_intAnd
  (.|.) = rhci_intOr
  xor = rhci_intXor
  complement = rhci_intComplement
  zeroBits = 0
  x `shift` i | i >= 0 = rhci_intShiftL x i
              | otherwise = rhci_intShiftRA x (negate i)
  x `shiftL` i | i >= 0 = rhci_intShiftL x i
               | otherwise = overflowError
  x `unsafeShiftL` i = rhci_intShiftL x (rhci_unsafeShiftCount i)
  x `shiftR` i | i >= 0 = rhci_intShiftRA x i
               | otherwise = overflowError
  x `unsafeShiftR` i = rhci_intShiftRA x (rhci_unsafeShiftCount i)
  x `rotate` i = let r = i .&. 63
                 in if r == 0 then x else rhci_intShiftL x r .|. rhci_intShiftRL x (64 - r)
  bit = bitDefault
  testBit = testBitDefault
  bitSizeMaybe _ = Just 64
  bitSize _ = 64
  isSigned _ = True
  popCount = rhci_intPopCount

instance FiniteBits Int where
  finiteBitSize _ = 64
  countLeadingZeros = rhci_intClz
  countTrailingZeros = rhci_intCtz

instance Bits Integer where
  (.&.) = rhci_integerAnd
  (.|.) = rhci_integerOr
  xor = rhci_integerXor
  complement = rhci_integerComplement
  zeroBits = 0
  x `shift` i | i >= 0 = rhci_integerShiftL x i
              | otherwise = rhci_integerShiftR x (negate i)
  x `shiftL` i | i >= 0 = rhci_integerShiftL x i
               | otherwise = overflowError
  x `unsafeShiftL` i = rhci_integerShiftL x (rhci_unsafeShiftCount i)
  x `shiftR` i | i >= 0 = rhci_integerShiftR x i
               | otherwise = overflowError
  x `unsafeShiftR` i = rhci_integerShiftR x (rhci_unsafeShiftCount i)
  x `rotate` i = shift x i
  bit i | i >= 0 = rhci_integerShiftL 1 i
        | otherwise = overflowError
  testBit x i = i >= 0 && rhci_integerTestBit x i
  bitSizeMaybe _ = Nothing
  bitSize _ = errorWithoutStackTrace "Data.Bits.bitSize(Integer)"
  isSigned _ = True
  popCount = rhci_integerPopCount

instance Bits Bool where
  (.&.) = (&&)
  (.|.) = (||)
  xor = (/=)
  complement = not
  shift x 0 = x
  shift _ _ = False
  rotate x _ = x
  bit 0 = True
  bit _ = False
  testBit x 0 = x
  testBit _ _ = False
  bitSizeMaybe _ = Just 1
  bitSize _ = 1
  isSigned _ = False
  popCount False = 0
  popCount True = 1

instance FiniteBits Bool where
  finiteBitSize _ = 1
  countTrailingZeros x = if x then 0 else 1
  countLeadingZeros x = if x then 0 else 1

-- ---- Data.IORef ----------------------------------------------------------------------

-- The reference itself is a machine object; the box keeps the value lazy.
data IORef a
data RhciBox a = RhciBox a

foreign import prim "newRef" rhci_newRef :: () -> RhciBox a -> IORef a
foreign import prim "readRef" rhci_readRef :: () -> IORef a -> RhciBox a
foreign import prim "writeRef" rhci_writeRef :: IORef a -> RhciBox a -> ()
foreign import prim "refEq" rhci_refEq :: IORef a -> IORef a -> Bool

instance Eq (IORef a) where
  a == b = rhci_refEq a b

newIORef :: a -> IO (IORef a)
newIORef v = IO (\w -> case rhci_newRef w (RhciBox v) of r -> r `seq` IORes r)

readIORef :: IORef a -> IO a
readIORef r = IO (\w -> case rhci_readRef w r of RhciBox v -> IORes v)

writeIORef :: IORef a -> a -> IO ()
writeIORef r v = IO (\_ -> case rhci_writeRef r (RhciBox v) of () -> IORes ())

modifyIORef :: IORef a -> (a -> a) -> IO ()
modifyIORef ref f = readIORef ref >>= writeIORef ref . f

modifyIORef' :: IORef a -> (a -> a) -> IO ()
modifyIORef' ref f = do
  x <- readIORef ref
  let x' = f x
  x' `seq` writeIORef ref x'

atomicModifyIORef :: IORef a -> (a -> (a, b)) -> IO b
atomicModifyIORef ref f = do
  x <- readIORef ref
  let r = f x
  writeIORef ref (fst r)
  return (snd r)

atomicModifyIORef' :: IORef a -> (a -> (a, b)) -> IO b
atomicModifyIORef' ref f = do
  x <- readIORef ref
  case f x of
    (a, b) -> a `seq` b `seq` (writeIORef ref a >> return b)

atomicWriteIORef :: IORef a -> a -> IO ()
atomicWriteIORef = writeIORef

-- ---- Numeric (from base: Numeric, GHC.Float) ----------------------------------------

showSigned :: Real a => (a -> ShowS) -> Int -> a -> ShowS
showSigned showPos p x
  | x < 0 = showParen (p > 6) (showChar '-' . showPos (negate x))
  | otherwise = showPos x

showInt :: Integral a => a -> ShowS
showInt n0 cs0
  | n0 < 0 = errorWithoutStackTrace "Numeric.showInt: can't show negative numbers"
  | otherwise = go n0 cs0
  where
    go n cs
      | n < 10 = chr (ord '0' + fromIntegral n) : cs
      | otherwise = case n `quotRem` 10 of (q, r) -> go q (chr (ord '0' + fromIntegral r) : cs)

showIntAtBase :: Integral a => a -> (Int -> Char) -> a -> ShowS
showIntAtBase base toChr n0 r0
  | base <= 1 = errorWithoutStackTrace ("Numeric.showIntAtBase: applied to unsupported base " ++ show (toInteger base))
  | n0 < 0 = errorWithoutStackTrace ("Numeric.showIntAtBase: applied to negative number " ++ show (toInteger n0))
  | otherwise = showIt (quotRem n0 base) r0
  where
    showIt (n, d) r = seq c $ case n of
        0 -> r'
        _ -> showIt (quotRem n base) r'
      where
        c = toChr (fromIntegral d)
        r' = c : r

showHex :: Integral a => a -> ShowS
showHex = showIntAtBase 16 intToDigit

showOct :: Integral a => a -> ShowS
showOct = showIntAtBase 8 intToDigit

showBin :: Integral a => a -> ShowS
showBin = showIntAtBase 2 intToDigit

data RhciFFFormat = RhciFFExponent | RhciFFFixed | RhciFFGeneric

showEFloat :: RealFloat a => Maybe Int -> a -> ShowS
showEFloat d x = showString (rhci_formatRealFloatAlt RhciFFExponent d False x)

showFFloat :: RealFloat a => Maybe Int -> a -> ShowS
showFFloat d x = showString (rhci_formatRealFloatAlt RhciFFFixed d False x)

showGFloat :: RealFloat a => Maybe Int -> a -> ShowS
showGFloat d x = showString (rhci_formatRealFloatAlt RhciFFGeneric d False x)

showFFloatAlt :: RealFloat a => Maybe Int -> a -> ShowS
showFFloatAlt d x = showString (rhci_formatRealFloatAlt RhciFFFixed d True x)

showGFloatAlt :: RealFloat a => Maybe Int -> a -> ShowS
showGFloatAlt d x = showString (rhci_formatRealFloatAlt RhciFFGeneric d True x)

showFloat :: RealFloat a => a -> ShowS
showFloat x = showString (rhci_formatRealFloatAlt RhciFFGeneric Nothing False x)

rhci_formatRealFloatAlt :: RealFloat a => RhciFFFormat -> Maybe Int -> Bool -> a -> String
rhci_formatRealFloatAlt fmt decs alt x
  | isNaN x = "NaN"
  | isInfinite x = if x < 0 then "-Infinity" else "Infinity"
  | x < 0 || isNegativeZero x = '-' : doFmt fmt (floatToDigits (toInteger base) (negate x))
  | otherwise = doFmt fmt (floatToDigits (toInteger base) x)
  where
    base = 10

    doFmt format (is, e) =
      let ds = map intToDigit is in
      case format of
        RhciFFGeneric ->
          doFmt (if e < 0 || e > 7 then RhciFFExponent else RhciFFFixed) (is, e)
        RhciFFExponent ->
          case decs of
            Nothing ->
              let show_e' = show (e - 1) in
              case ds of
                "0" -> "0.0e0"
                [d] -> d : ".0e" ++ show_e'
                (d:ds') -> d : '.' : ds' ++ "e" ++ show_e'
                [] -> errorWithoutStackTrace "formatRealFloat/doFmt/FFExponent: []"
            Just d | d <= 0 ->
              case is of
                [0] -> "0e0"
                _ ->
                  let (ei, is') = rhci_roundTo base 1 is
                      n:_ = map intToDigit (if ei > 0 then init is' else is')
                  in n : 'e' : show (e - 1 + ei)
            Just dec ->
              let dec' = max dec 1 in
              case is of
                [0] -> '0' : '.' : take dec' (repeat '0') ++ "e0"
                _ ->
                  let (ei, is') = rhci_roundTo base (dec' + 1) is
                      (d:ds') = map intToDigit (if ei > 0 then init is' else is')
                  in d : '.' : ds' ++ 'e' : show (e - 1 + ei)
        RhciFFFixed ->
          let mk0 ls = case ls of { "" -> "0" ; _ -> ls } in
          case decs of
            Nothing
              | e <= 0 -> "0." ++ replicate (negate e) '0' ++ ds
              | otherwise ->
                  let f 0 s rs = mk0 (reverse s) ++ '.' : mk0 rs
                      f n s "" = f (n - 1) ('0' : s) ""
                      f n s (r:rs) = f (n - 1) (r : s) rs
                  in f e "" ds
            Just dec ->
              let dec' = max dec 0 in
              if e >= 0
                then
                  let (ei, is') = rhci_roundTo base (dec' + e) is
                      (ls, rs) = splitAt (e + ei) (map intToDigit is')
                  in mk0 ls ++ (if null rs && not alt then "" else '.' : rs)
                else
                  let (ei, is') = rhci_roundTo base dec' (replicate (negate e) 0 ++ is)
                      d:ds' = map intToDigit (if ei > 0 then is' else 0 : is')
                  in d : (if null ds' && not alt then "" else '.' : ds')

rhci_roundTo :: Int -> Int -> [Int] -> (Int, [Int])
rhci_roundTo base d is =
  case f d True is of
    x@(0, _) -> x
    (1, xs) -> (1, 1 : xs)
    _ -> errorWithoutStackTrace "roundTo: bad Value"
  where
    b2 = base `quot` 2
    f n _ [] = (0, replicate n 0)
    f 0 e (x:xs)
      | x == b2 && e && all (== 0) xs = (0, [])
      | otherwise = (if x >= b2 then 1 else 0, [])
    f n _ (i:xs)
      | i' == base = (1, 0 : ds)
      | otherwise = (0, i' : ds)
      where
        (c, ds) = f (n - 1) (even i) xs
        i' = c + i

-- GHC.Float's floatToDigits. Where GHC estimates the exponent k with Float
-- logarithms (bases other than 10), this starts below the estimate and
-- counts up, which gives the exact k.
floatToDigits :: RealFloat a => Integer -> a -> ([Int], Int)
floatToDigits _ 0 = ([0], 0)
floatToDigits base x =
  let
    (f0, e0) = decodeFloat x
    (minExp0, _) = floatRange x
    p = floatDigits x
    b = floatRadix x
    minExp = minExp0 - p
    (f, e) =
      let n = minExp - e0 in
      if n > 0 then (f0 `quot` (b ^ n), e0 + n) else (f0, e0)
    (r, s, mUp, mDn) =
      if e >= 0
        then
          let be = b ^ e in
          if f == b ^ (p - 1)
            then (f * be * b * 2, 2 * b, be * b, be)
            else (f * be * 2, 2, be, be)
        else
          if e > minExp && f == b ^ (p - 1)
            then (f * b * 2, b ^ (negate e + 1) * 2, b, 1)
            else (f * 2, b ^ negate e * 2, 1, 1)
    k :: Int
    k =
      let
        k0 :: Int
        k0 =
          if b == 2 && base == 10
            then
              let lx = p - 1 + e0
                  k1 = (lx * 8651) `quot` 28738
              in if lx >= 0 then k1 + 1 else k1
            else
              ceiling ((log (fromInteger (f + 1) :: Double) + fromIntegral e * log (fromInteger b))
                         / log (fromInteger base)) - 2
        fixup n =
          if n >= 0
            then if r + mUp <= base ^ n * s then n else fixup (n + 1)
            else if base ^ negate n * (r + mUp) <= s then n else fixup (n + 1)
      in fixup k0
    gen ds rn sN mUpN mDnN =
      let
        (dn, rn') = (rn * base) `quotRem` sN
        mUpN' = mUpN * base
        mDnN' = mDnN * base
      in
      case (rn' < mDnN', rn' + mUpN' > sN) of
        (True, False) -> dn : ds
        (False, True) -> dn + 1 : ds
        (True, True) -> if rn' * 2 < sN then dn : ds else dn + 1 : ds
        (False, False) -> gen (dn : ds) rn' sN mUpN' mDnN'
    rds =
      if k >= 0
        then gen [] r (s * base ^ k) mUp mDn
        else
          let bk = base ^ negate k in
          gen [] (r * bk) s (mUp * bk) (mDn * bk)
  in
  (map fromIntegral (reverse rds), k)

showHFloat :: RealFloat a => a -> ShowS
showHFloat = showString . fmt
  where
    fmt x
      | isNaN x = "NaN"
      | isInfinite x = (if x < 0 then "-" else "") ++ "Infinity"
      | x < 0 || isNegativeZero x = '-' : cvt (negate x)
      | otherwise = cvt x
    cvt x
      | x == 0 = "0x0p+0"
      | otherwise =
          case floatToDigits 2 x of
            r@([], _) -> error $ "Impossible happened: showHFloat: " ++ show r
            (d:ds, e) -> "0x" ++ show d ++ frac ds ++ "p" ++ show (e - 1)
    frac digits
      | allZ digits = ""
      | otherwise = "." ++ hex digits
      where
        hex ds =
          case ds of
            [] -> ""
            [a] -> hexDigit a 0 0 0 ""
            [a, b] -> hexDigit a b 0 0 ""
            [a, b, c] -> hexDigit a b c 0 ""
            a : b : c : d : r -> hexDigit a b c d (hex r)
    hexDigit a b c d = showHex (8 * a + 4 * b + 2 * c + d)
    allZ xs = case xs of
      x : more -> x == 0 && allZ more
      [] -> True

readInt :: Num a => a -> (Char -> Bool) -> (Char -> Int) -> ReadS a
readInt base isDig valDigit = rhci_readP_to_S (rhci_readIntP base isDig valDigit)

rhci_readIntP :: Num a => a -> (Char -> Bool) -> (Char -> Int) -> ReadP a
rhci_readIntP base isDig valDigit =
  rhci_munch1 isDig >>= \s -> return (foldl (\n d -> n * base + fromIntegral d) 0 (map valDigit s))

rhci_readIntP' :: (Eq a, Num a) => Int -> ReadP a
rhci_readIntP' base = rhci_readIntP (fromIntegral base) isDig valDigit
  where
    isDig c = maybe False (const True) (rhci_valDigit base c)
    valDigit c = maybe 0 id (rhci_valDigit base c)

rhci_valDigit :: Int -> Char -> Maybe Int
rhci_valDigit 2 c
  | c == '0' || c == '1' = Just (ord c - ord '0')
  | otherwise = Nothing
rhci_valDigit base c = rhci_valDig base c

readBin :: (Eq a, Num a) => ReadS a
readBin = rhci_readP_to_S (rhci_readIntP' 2)

readOct :: (Eq a, Num a) => ReadS a
readOct = rhci_readP_to_S (rhci_readIntP' 8)

readDec :: (Eq a, Num a) => ReadS a
readDec = rhci_readP_to_S (rhci_readIntP' 10)

readHex :: (Eq a, Num a) => ReadS a
readHex = rhci_readP_to_S (rhci_readIntP' 16)

readSigned :: Real a => ReadS a -> ReadS a
readSigned readPos = readParen False read'
  where
    read' r = read'' r ++ [(negate x, t) | ("-", s) <- lex r, (x, t) <- read'' s]
    read'' r = [(n, s) | (str, s) <- lex r, (n, "") <- readPos str]

lexDigits :: ReadS String
lexDigits = rhci_readP_to_S (rhci_munch1 isDigit)

-- ---- Text.Printf (from base) -----------------------------------------------------------

printf :: PrintfType r => String -> r
printf fmts = spr fmts []

hPrintf :: HPrintfType r => Handle -> String -> r
hPrintf hdl fmts = hspr hdl fmts []

class PrintfType t where
  spr :: String -> [UPrintf] -> t

class HPrintfType t where
  hspr :: Handle -> String -> [UPrintf] -> t

instance IsChar c => PrintfType [c] where
  spr fmts args = map fromChar (uprintf fmts (reverse args))

instance (a ~ ()) => PrintfType (IO a) where
  spr fmts args = putStr $ map fromChar $ uprintf fmts $ reverse args

instance (a ~ ()) => HPrintfType (IO a) where
  hspr hdl fmts args = hPutStr hdl (uprintf fmts (reverse args))

instance (PrintfArg a, PrintfType r) => PrintfType (a -> r) where
  spr fmts args = \a -> spr fmts ((parseFormat a, formatArg a) : args)

instance (PrintfArg a, HPrintfType r) => HPrintfType (a -> r) where
  hspr hdl fmts args = \a -> hspr hdl fmts ((parseFormat a, formatArg a) : args)

class PrintfArg a where
  formatArg :: a -> FieldFormatter
  parseFormat :: a -> ModifierParser
  parseFormat _ (c : cs) = FormatParse "" c cs
  parseFormat _ "" = errorShortFormat

instance PrintfArg Char where
  formatArg = formatChar
  parseFormat _ cf = parseIntFormat (undefined :: Int) cf

instance IsChar c => PrintfArg [c] where
  formatArg = formatString

instance PrintfArg Int where
  formatArg = formatInt
  parseFormat = parseIntFormat

instance PrintfArg Integer where
  formatArg = formatInteger
  parseFormat = parseIntFormat

instance PrintfArg Double where
  formatArg = formatRealFloat

class IsChar c where
  toChar :: c -> Char
  fromChar :: Char -> c

instance IsChar Char where
  toChar c = c
  fromChar c = c

data FormatAdjustment = LeftAdjust | ZeroPad

data FormatSign = SignPlus | SignSpace

data FieldFormat = FieldFormat {
  fmtWidth :: Maybe Int,
  fmtPrecision :: Maybe Int,
  fmtAdjust :: Maybe FormatAdjustment,
  fmtSign :: Maybe FormatSign,
  fmtAlternate :: Bool,
  fmtModifiers :: String,
  fmtChar :: Char
  }

data FormatParse = FormatParse {
  fpModifiers :: String,
  fpChar :: Char,
  fpRest :: String
  }

rhci_intModifierMap :: [(String, Integer)]
rhci_intModifierMap = [
  ("hh", negate 128),
  ("h", negate 32768),
  ("l", negate 2147483648),
  ("ll", toInteger (minBound :: Int)),
  ("L", toInteger (minBound :: Int)) ]

parseIntFormat :: a -> String -> FormatParse
parseIntFormat _ s =
  case foldr matchPrefix Nothing rhci_intModifierMap of
    Just m -> m
    Nothing ->
      case s of
        c : cs -> FormatParse "" c cs
        "" -> errorShortFormat
  where
    matchPrefix (p, _) m@(Just (FormatParse p0 _ _))
      | length p0 >= length p = m
      | otherwise = case getFormat p of
          Nothing -> m
          Just fp -> Just fp
    matchPrefix (p, _) Nothing = getFormat p
    getFormat p = stripPrefix p s >>= fp
      where
        fp (c : cs) = Just $ FormatParse p c cs
        fp "" = errorShortFormat

type FieldFormatter = FieldFormat -> ShowS

type ModifierParser = String -> FormatParse

vFmt :: Char -> FieldFormat -> FieldFormat
vFmt c ufmt@(FieldFormat {fmtChar = 'v'}) = ufmt {fmtChar = c}
vFmt _ ufmt = ufmt

formatChar :: Char -> FieldFormatter
formatChar x ufmt = formatIntegral (Just 0) (toInteger $ ord x) $ vFmt 'c' ufmt

formatString :: IsChar a => [a] -> FieldFormatter
formatString x ufmt =
  case fmtChar $ vFmt 's' ufmt of
    's' -> map toChar . (adjust ufmt ("", ts) ++)
      where
        ts = map toChar $ trunc $ fmtPrecision ufmt
          where
            trunc Nothing = x
            trunc (Just n) = take n x
    c -> errorBadFormat c

rhci_fixupMods :: FieldFormat -> Maybe Integer -> Maybe Integer
rhci_fixupMods ufmt m =
  let mods = fmtModifiers ufmt in
  case mods of
    "" -> m
    _ -> case lookup mods rhci_intModifierMap of
      Just m0 -> Just m0
      Nothing -> perror "unknown format modifier"

formatInt :: (Integral a, Bounded a) => a -> FieldFormatter
formatInt x ufmt =
  let lb = toInteger $ minBound `asTypeOf` x
      m = rhci_fixupMods ufmt (Just lb)
      ufmt' = case lb of
        0 -> vFmt 'u' ufmt
        _ -> ufmt
  in formatIntegral m (toInteger x) ufmt'

formatInteger :: Integer -> FieldFormatter
formatInteger x ufmt =
  let m = rhci_fixupMods ufmt Nothing in
  formatIntegral m x ufmt

formatIntegral :: Maybe Integer -> Integer -> FieldFormatter
formatIntegral m x ufmt0 =
  let prec = fmtPrecision ufmt0 in
  case fmtChar ufmt of
    'd' -> (adjustSigned ufmt (fmti prec x) ++)
    'i' -> (adjustSigned ufmt (fmti prec x) ++)
    'x' -> (adjust ufmt (fmtu 16 (alt "0x" x) prec m x) ++)
    'X' -> (adjust ufmt (upcase $ fmtu 16 (alt "0X" x) prec m x) ++)
    'b' -> (adjust ufmt (fmtu 2 (alt "0b" x) prec m x) ++)
    'o' -> (adjust ufmt (fmtu 8 (alt "0" x) prec m x) ++)
    'u' -> (adjust ufmt (fmtu 10 Nothing prec m x) ++)
    'c' | x >= fromIntegral (ord (minBound :: Char)) &&
          x <= fromIntegral (ord (maxBound :: Char)) &&
          fmtPrecision ufmt == Nothing &&
          fmtModifiers ufmt == "" ->
            formatString [chr $ fromIntegral x] (ufmt { fmtChar = 's' })
    'c' -> perror "illegal char conversion"
    c -> errorBadFormat c
  where
    ufmt = vFmt 'd' $ case ufmt0 of
      FieldFormat { fmtPrecision = Just _, fmtAdjust = Just ZeroPad } ->
        ufmt0 { fmtAdjust = Nothing }
      _ -> ufmt0
    alt _ 0 = Nothing
    alt p _ = case fmtAlternate ufmt of
      True -> Just p
      False -> Nothing
    upcase (s1, s2) = (s1, map toUpper s2)

formatRealFloat :: RealFloat a => a -> FieldFormatter
formatRealFloat x ufmt =
  let c = fmtChar $ vFmt 'g' ufmt
      prec = fmtPrecision ufmt
      alt = fmtAlternate ufmt
  in
  case c of
    'e' -> (adjustSigned ufmt (dfmt c prec alt x) ++)
    'E' -> (adjustSigned ufmt (dfmt c prec alt x) ++)
    'f' -> (adjustSigned ufmt (dfmt c prec alt x) ++)
    'F' -> (adjustSigned ufmt (dfmt c prec alt x) ++)
    'g' -> (adjustSigned ufmt (dfmt c prec alt x) ++)
    'G' -> (adjustSigned ufmt (dfmt c prec alt x) ++)
    _ -> errorBadFormat c

type UPrintf = (ModifierParser, FieldFormatter)

uprintf :: String -> [UPrintf] -> String
uprintf s us = uprintfs s us ""

uprintfs :: String -> [UPrintf] -> ShowS
uprintfs "" [] = id
uprintfs "" (_:_) = errorShortFormat
uprintfs ('%':'%':cs) us = ('%' :) . uprintfs cs us
uprintfs ('%':_) [] = errorMissingArgument
uprintfs ('%':cs) us@(_:_) = fmt cs us
uprintfs (c:cs) us = (c :) . uprintfs cs us

fmt :: String -> [UPrintf] -> ShowS
fmt cs0 us0 =
  case getSpecs False False Nothing False cs0 us0 of
    (_, _, []) -> errorMissingArgument
    (ufmt, cs, (_, u) : us) -> u ufmt . uprintfs cs us

adjust :: FieldFormat -> (String, String) -> String
adjust ufmt (pre, str) =
  let naturalWidth = length pre + length str
      zero = case fmtAdjust ufmt of
        Just ZeroPad -> True
        _ -> False
      left = case fmtAdjust ufmt of
        Just LeftAdjust -> True
        _ -> False
      fill = case fmtWidth ufmt of
        Just width | naturalWidth < width ->
          let fillchar = if zero then '0' else ' ' in
          replicate (width - naturalWidth) fillchar
        _ -> ""
  in
  if left
    then pre ++ str ++ fill
    else if zero
      then pre ++ fill ++ str
      else fill ++ pre ++ str

adjustSigned :: FieldFormat -> (String, String) -> String
adjustSigned ufmt@(FieldFormat {fmtSign = Just SignPlus}) ("", str) = adjust ufmt ("+", str)
adjustSigned ufmt@(FieldFormat {fmtSign = Just SignSpace}) ("", str) = adjust ufmt (" ", str)
adjustSigned ufmt ps = adjust ufmt ps

fmti :: Maybe Int -> Integer -> (String, String)
fmti prec i
  | i < 0 = ("-", integral_prec prec (show (negate i)))
  | otherwise = ("", integral_prec prec (show i))

fmtu :: Integer -> Maybe String -> Maybe Int -> Maybe Integer -> Integer -> (String, String)
fmtu b (Just pre) prec m i =
  let ("", s) = fmtu b Nothing prec m i in
  case pre of
    "0" -> case s of
      '0' : _ -> ("", s)
      _ -> (pre, s)
    _ -> (pre, s)
fmtu b Nothing prec0 m0 i0 =
  case fmtu' prec0 m0 i0 of
    Just s -> ("", s)
    Nothing -> errorBadArgument
  where
    fmtu' :: Maybe Int -> Maybe Integer -> Integer -> Maybe String
    fmtu' prec (Just m) i | i < 0 = fmtu' prec Nothing (-2 * m + i)
    fmtu' (Just prec) _ i | i >= 0 = fmap (integral_prec (Just prec)) $ fmtu' Nothing Nothing i
    fmtu' Nothing _ i | i >= 0 = Just $ showIntAtBase b intToDigit i ""
    fmtu' _ _ _ = Nothing

integral_prec :: Maybe Int -> String -> String
integral_prec Nothing integral = integral
integral_prec (Just 0) "0" = ""
integral_prec (Just prec) integral = replicate (prec - length integral) '0' ++ integral

stoi :: String -> (Int, String)
stoi cs =
  let (as, cs') = span isDigit cs in
  case as of
    "" -> (0, cs')
    _ -> (read as, cs')

adjustment :: Maybe Int -> Maybe a -> Bool -> Bool -> Maybe FormatAdjustment
adjustment w p l z =
  case w of
    Just n | n < 0 -> adjl p True z
    _ -> adjl p l z
  where
    adjl _ True _ = Just LeftAdjust
    adjl _ False True = Just ZeroPad
    adjl _ _ _ = Nothing

getSpecs :: Bool -> Bool -> Maybe FormatSign -> Bool -> String -> [UPrintf] -> (FieldFormat, String, [UPrintf])
getSpecs _ z s a ('-' : cs0) us = getSpecs True z s a cs0 us
getSpecs l z _ a ('+' : cs0) us = getSpecs l z (Just SignPlus) a cs0 us
getSpecs l z s a (' ' : cs0) us = getSpecs l z ss a cs0 us
  where
    ss = case s of
      Just SignPlus -> Just SignPlus
      _ -> Just SignSpace
getSpecs l _ s a ('0' : cs0) us = getSpecs l True s a cs0 us
getSpecs l z s _ ('#' : cs0) us = getSpecs l z s True cs0 us
getSpecs l z s a ('*' : cs0) us =
  let (us', n) = getStar us
      ((p, cs''), us'') = case cs0 of
        '.':'*':r ->
          let (us''', p') = getStar us' in ((Just p', r), us''')
        '.':r ->
          let (p', r') = stoi r in ((Just p', r'), us')
        _ ->
          ((Nothing, cs0), us')
      FormatParse ms c cs =
        case us'' of
          (ufmt, _) : _ -> ufmt cs''
          [] -> errorMissingArgument
  in
  (FieldFormat {
      fmtWidth = Just (abs n),
      fmtPrecision = p,
      fmtAdjust = adjustment (Just n) p l z,
      fmtSign = s,
      fmtAlternate = a,
      fmtModifiers = ms,
      fmtChar = c}, cs, us'')
getSpecs l z s a ('.' : cs0) us =
  let ((p, cs'), us') = case cs0 of
        '*':cs'' -> let (us'', p') = getStar us in ((p', cs''), us'')
        _ -> (stoi cs0, us)
      FormatParse ms c cs =
        case us' of
          (ufmt, _) : _ -> ufmt cs'
          [] -> errorMissingArgument
  in
  (FieldFormat {
      fmtWidth = Nothing,
      fmtPrecision = Just p,
      fmtAdjust = adjustment Nothing (Just p) l z,
      fmtSign = s,
      fmtAlternate = a,
      fmtModifiers = ms,
      fmtChar = c}, cs, us')
getSpecs l z s a cs0@(c0 : _) us | isDigit c0 =
  let (n, cs') = stoi cs0
      ((p, cs''), us') = case cs' of
        '.' : '*' : r ->
          let (us'', p') = getStar us in ((Just p', r), us'')
        '.' : r ->
          let (p', r') = stoi r in ((Just p', r'), us)
        _ ->
          ((Nothing, cs'), us)
      FormatParse ms c cs =
        case us' of
          (ufmt, _) : _ -> ufmt cs''
          [] -> errorMissingArgument
  in
  (FieldFormat {
      fmtWidth = Just (abs n),
      fmtPrecision = p,
      fmtAdjust = adjustment (Just n) p l z,
      fmtSign = s,
      fmtAlternate = a,
      fmtModifiers = ms,
      fmtChar = c}, cs, us')
getSpecs l z s a cs0@(_ : _) us =
  let FormatParse ms c cs =
        case us of
          (ufmt, _) : _ -> ufmt cs0
          [] -> errorMissingArgument
  in
  (FieldFormat {
      fmtWidth = Nothing,
      fmtPrecision = Nothing,
      fmtAdjust = adjustment Nothing Nothing l z,
      fmtSign = s,
      fmtAlternate = a,
      fmtModifiers = ms,
      fmtChar = c}, cs, us)
getSpecs _ _ _ _ "" _ = errorShortFormat

getStar :: [UPrintf] -> ([UPrintf], Int)
getStar us =
  let ufmt = FieldFormat {
        fmtWidth = Nothing,
        fmtPrecision = Nothing,
        fmtAdjust = Nothing,
        fmtSign = Nothing,
        fmtAlternate = False,
        fmtModifiers = "",
        fmtChar = 'd' } in
  case us of
    [] -> errorMissingArgument
    (_, nu) : us' -> (us', read (nu ufmt ""))

dfmt :: RealFloat a => Char -> Maybe Int -> Bool -> a -> (String, String)
dfmt c p a d =
  let caseConvert = if isUpper c then map toUpper else id
      showFunction = case toLower c of
        'e' -> showEFloat
        'f' -> if a then showFFloatAlt else showFFloat
        'g' -> if a then showGFloatAlt else showGFloat
        _ -> perror "internal error: impossible dfmt"
      result = caseConvert $ showFunction p d ""
  in
  case result of
    '-' : cs -> ("-", cs)
    cs -> ("", cs)

perror :: String -> a
perror s = errorWithoutStackTrace $ "printf: " ++ s

errorBadFormat :: Char -> a
errorBadFormat c = perror $ "bad formatting char " ++ show c

errorShortFormat, errorMissingArgument, errorBadArgument :: a
errorShortFormat = perror "formatting string ended prematurely"
errorMissingArgument = perror "argument list ended prematurely"
errorBadArgument = perror "bad argument"

-- ---- larger tuples (generated by tools/gen_tuples.rb; do not edit) ----

instance (Bounded a1, Bounded a2, Bounded a3) => Bounded (a1, a2, a3) where
  minBound = (minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound)

instance (Semigroup a1, Semigroup a2, Semigroup a3) => Semigroup (a1, a2, a3) where
  (a1, a2, a3) <> (b1, b2, b3) = (a1 <> b1, a2 <> b2, a3 <> b3)

instance (Monoid a1, Monoid a2, Monoid a3) => Monoid (a1, a2, a3) where
  mempty = (mempty, mempty, mempty)

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4) => Bounded (a1, a2, a3, a4) where
  minBound = (minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound)

instance (Semigroup a1, Semigroup a2, Semigroup a3, Semigroup a4) => Semigroup (a1, a2, a3, a4) where
  (a1, a2, a3, a4) <> (b1, b2, b3, b4) = (a1 <> b1, a2 <> b2, a3 <> b3, a4 <> b4)

instance (Monoid a1, Monoid a2, Monoid a3, Monoid a4) => Monoid (a1, a2, a3, a4) where
  mempty = (mempty, mempty, mempty, mempty)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5) => Eq (a1, a2, a3, a4, a5) where
  (a1, a2, a3, a4, a5) == (b1, b2, b3, b4, b5) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5) => Ord (a1, a2, a3, a4, a5) where
  compare (a1, a2, a3, a4, a5) (b1, b2, b3, b4, b5) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (compare a5 b5))))

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5) => Bounded (a1, a2, a3, a4, a5) where
  minBound = (minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Semigroup a1, Semigroup a2, Semigroup a3, Semigroup a4, Semigroup a5) => Semigroup (a1, a2, a3, a4, a5) where
  (a1, a2, a3, a4, a5) <> (b1, b2, b3, b4, b5) = (a1 <> b1, a2 <> b2, a3 <> b3, a4 <> b4, a5 <> b5)

instance (Monoid a1, Monoid a2, Monoid a3, Monoid a4, Monoid a5) => Monoid (a1, a2, a3, a4, a5) where
  mempty = (mempty, mempty, mempty, mempty, mempty)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6) => Eq (a1, a2, a3, a4, a5, a6) where
  (a1, a2, a3, a4, a5, a6) == (b1, b2, b3, b4, b5, b6) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6) => Ord (a1, a2, a3, a4, a5, a6) where
  compare (a1, a2, a3, a4, a5, a6) (b1, b2, b3, b4, b5, b6) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (compare a6 b6)))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6) => Show (a1, a2, a3, a4, a5, a6) where
  showsPrec _ (a1, a2, a3, a4, a5, a6) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6) => Read (a1, a2, a3, a4, a5, a6) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> return (a1, a2, a3, a4, a5, a6))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6) => Bounded (a1, a2, a3, a4, a5, a6) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7) => Eq (a1, a2, a3, a4, a5, a6, a7) where
  (a1, a2, a3, a4, a5, a6, a7) == (b1, b2, b3, b4, b5, b6, b7) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7) => Ord (a1, a2, a3, a4, a5, a6, a7) where
  compare (a1, a2, a3, a4, a5, a6, a7) (b1, b2, b3, b4, b5, b6, b7) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (compare a7 b7))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7) => Show (a1, a2, a3, a4, a5, a6, a7) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7) => Read (a1, a2, a3, a4, a5, a6, a7) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> return (a1, a2, a3, a4, a5, a6, a7))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7) => Bounded (a1, a2, a3, a4, a5, a6, a7) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8) => Eq (a1, a2, a3, a4, a5, a6, a7, a8) where
  (a1, a2, a3, a4, a5, a6, a7, a8) == (b1, b2, b3, b4, b5, b6, b7, b8) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8) => Ord (a1, a2, a3, a4, a5, a6, a7, a8) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8) (b1, b2, b3, b4, b5, b6, b7, b8) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (compare a8 b8)))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8) => Show (a1, a2, a3, a4, a5, a6, a7, a8) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8) => Read (a1, a2, a3, a4, a5, a6, a7, a8) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> return (a1, a2, a3, a4, a5, a6, a7, a8))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8, Eq a9) => Eq (a1, a2, a3, a4, a5, a6, a7, a8, a9) where
  (a1, a2, a3, a4, a5, a6, a7, a8, a9) == (b1, b2, b3, b4, b5, b6, b7, b8, b9) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8 && a9 == b9

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8, Ord a9) => Ord (a1, a2, a3, a4, a5, a6, a7, a8, a9) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8, a9) (b1, b2, b3, b4, b5, b6, b7, b8, b9) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (rhci_thenCmp (compare a8 b8) (compare a9 b9))))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8, Show a9) => Show (a1, a2, a3, a4, a5, a6, a7, a8, a9) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8, a9) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8, shows a9] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8, Read a9) => Read (a1, a2, a3, a4, a5, a6, a7, a8, a9) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> rhci_readComma >> readPrec >>= \a9 -> return (a1, a2, a3, a4, a5, a6, a7, a8, a9))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8, Bounded a9) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8, a9) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8, Eq a9, Eq a10) => Eq (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) where
  (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) == (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8 && a9 == b9 && a10 == b10

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8, Ord a9, Ord a10) => Ord (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (rhci_thenCmp (compare a8 b8) (rhci_thenCmp (compare a9 b9) (compare a10 b10)))))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8, Show a9, Show a10) => Show (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8, shows a9, shows a10] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8, Read a9, Read a10) => Read (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> rhci_readComma >> readPrec >>= \a9 -> rhci_readComma >> readPrec >>= \a10 -> return (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8, Bounded a9, Bounded a10) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8, Eq a9, Eq a10, Eq a11) => Eq (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) where
  (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) == (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8 && a9 == b9 && a10 == b10 && a11 == b11

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8, Ord a9, Ord a10, Ord a11) => Ord (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (rhci_thenCmp (compare a8 b8) (rhci_thenCmp (compare a9 b9) (rhci_thenCmp (compare a10 b10) (compare a11 b11))))))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8, Show a9, Show a10, Show a11) => Show (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8, shows a9, shows a10, shows a11] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8, Read a9, Read a10, Read a11) => Read (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> rhci_readComma >> readPrec >>= \a9 -> rhci_readComma >> readPrec >>= \a10 -> rhci_readComma >> readPrec >>= \a11 -> return (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8, Bounded a9, Bounded a10, Bounded a11) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8, Eq a9, Eq a10, Eq a11, Eq a12) => Eq (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) where
  (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) == (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8 && a9 == b9 && a10 == b10 && a11 == b11 && a12 == b12

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8, Ord a9, Ord a10, Ord a11, Ord a12) => Ord (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (rhci_thenCmp (compare a8 b8) (rhci_thenCmp (compare a9 b9) (rhci_thenCmp (compare a10 b10) (rhci_thenCmp (compare a11 b11) (compare a12 b12)))))))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8, Show a9, Show a10, Show a11, Show a12) => Show (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8, shows a9, shows a10, shows a11, shows a12] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8, Read a9, Read a10, Read a11, Read a12) => Read (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> rhci_readComma >> readPrec >>= \a9 -> rhci_readComma >> readPrec >>= \a10 -> rhci_readComma >> readPrec >>= \a11 -> rhci_readComma >> readPrec >>= \a12 -> return (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8, Bounded a9, Bounded a10, Bounded a11, Bounded a12) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8, Eq a9, Eq a10, Eq a11, Eq a12, Eq a13) => Eq (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) where
  (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) == (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8 && a9 == b9 && a10 == b10 && a11 == b11 && a12 == b12 && a13 == b13

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8, Ord a9, Ord a10, Ord a11, Ord a12, Ord a13) => Ord (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (rhci_thenCmp (compare a8 b8) (rhci_thenCmp (compare a9 b9) (rhci_thenCmp (compare a10 b10) (rhci_thenCmp (compare a11 b11) (rhci_thenCmp (compare a12 b12) (compare a13 b13))))))))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8, Show a9, Show a10, Show a11, Show a12, Show a13) => Show (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8, shows a9, shows a10, shows a11, shows a12, shows a13] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8, Read a9, Read a10, Read a11, Read a12, Read a13) => Read (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> rhci_readComma >> readPrec >>= \a9 -> rhci_readComma >> readPrec >>= \a10 -> rhci_readComma >> readPrec >>= \a11 -> rhci_readComma >> readPrec >>= \a12 -> rhci_readComma >> readPrec >>= \a13 -> return (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8, Bounded a9, Bounded a10, Bounded a11, Bounded a12, Bounded a13) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8, Eq a9, Eq a10, Eq a11, Eq a12, Eq a13, Eq a14) => Eq (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) where
  (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) == (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8 && a9 == b9 && a10 == b10 && a11 == b11 && a12 == b12 && a13 == b13 && a14 == b14

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8, Ord a9, Ord a10, Ord a11, Ord a12, Ord a13, Ord a14) => Ord (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (rhci_thenCmp (compare a8 b8) (rhci_thenCmp (compare a9 b9) (rhci_thenCmp (compare a10 b10) (rhci_thenCmp (compare a11 b11) (rhci_thenCmp (compare a12 b12) (rhci_thenCmp (compare a13 b13) (compare a14 b14)))))))))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8, Show a9, Show a10, Show a11, Show a12, Show a13, Show a14) => Show (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8, shows a9, shows a10, shows a11, shows a12, shows a13, shows a14] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8, Read a9, Read a10, Read a11, Read a12, Read a13, Read a14) => Read (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> rhci_readComma >> readPrec >>= \a9 -> rhci_readComma >> readPrec >>= \a10 -> rhci_readComma >> readPrec >>= \a11 -> rhci_readComma >> readPrec >>= \a12 -> rhci_readComma >> readPrec >>= \a13 -> rhci_readComma >> readPrec >>= \a14 -> return (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8, Bounded a9, Bounded a10, Bounded a11, Bounded a12, Bounded a13, Bounded a14) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Eq a1, Eq a2, Eq a3, Eq a4, Eq a5, Eq a6, Eq a7, Eq a8, Eq a9, Eq a10, Eq a11, Eq a12, Eq a13, Eq a14, Eq a15) => Eq (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) where
  (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) == (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15) = a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 && a5 == b5 && a6 == b6 && a7 == b7 && a8 == b8 && a9 == b9 && a10 == b10 && a11 == b11 && a12 == b12 && a13 == b13 && a14 == b14 && a15 == b15

instance (Ord a1, Ord a2, Ord a3, Ord a4, Ord a5, Ord a6, Ord a7, Ord a8, Ord a9, Ord a10, Ord a11, Ord a12, Ord a13, Ord a14, Ord a15) => Ord (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) where
  compare (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15) =
    rhci_thenCmp (compare a1 b1) (rhci_thenCmp (compare a2 b2) (rhci_thenCmp (compare a3 b3) (rhci_thenCmp (compare a4 b4) (rhci_thenCmp (compare a5 b5) (rhci_thenCmp (compare a6 b6) (rhci_thenCmp (compare a7 b7) (rhci_thenCmp (compare a8 b8) (rhci_thenCmp (compare a9 b9) (rhci_thenCmp (compare a10 b10) (rhci_thenCmp (compare a11 b11) (rhci_thenCmp (compare a12 b12) (rhci_thenCmp (compare a13 b13) (rhci_thenCmp (compare a14 b14) (compare a15 b15))))))))))))))

instance (Show a1, Show a2, Show a3, Show a4, Show a5, Show a6, Show a7, Show a8, Show a9, Show a10, Show a11, Show a12, Show a13, Show a14, Show a15) => Show (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) where
  showsPrec _ (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) s = show_tuple [shows a1, shows a2, shows a3, shows a4, shows a5, shows a6, shows a7, shows a8, shows a9, shows a10, shows a11, shows a12, shows a13, shows a14, shows a15] s

instance (Read a1, Read a2, Read a3, Read a4, Read a5, Read a6, Read a7, Read a8, Read a9, Read a10, Read a11, Read a12, Read a13, Read a14, Read a15) => Read (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) where
  readPrec = rhci_wrapTup (readPrec >>= \a1 -> rhci_readComma >> readPrec >>= \a2 -> rhci_readComma >> readPrec >>= \a3 -> rhci_readComma >> readPrec >>= \a4 -> rhci_readComma >> readPrec >>= \a5 -> rhci_readComma >> readPrec >>= \a6 -> rhci_readComma >> readPrec >>= \a7 -> rhci_readComma >> readPrec >>= \a8 -> rhci_readComma >> readPrec >>= \a9 -> rhci_readComma >> readPrec >>= \a10 -> rhci_readComma >> readPrec >>= \a11 -> rhci_readComma >> readPrec >>= \a12 -> rhci_readComma >> readPrec >>= \a13 -> rhci_readComma >> readPrec >>= \a14 -> rhci_readComma >> readPrec >>= \a15 -> return (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15))
  readListPrec = readListPrecDefault
  readList = readListDefault

instance (Bounded a1, Bounded a2, Bounded a3, Bounded a4, Bounded a5, Bounded a6, Bounded a7, Bounded a8, Bounded a9, Bounded a10, Bounded a11, Bounded a12, Bounded a13, Bounded a14, Bounded a15) => Bounded (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

-- ---- end of larger tuples ----
