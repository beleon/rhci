-- A minimal, Haskell 98 stand-in for hspec, enough for the exercism tests
-- (test/exercism/README.md). It runs unchanged under GHC and rhci, so the
-- two can be compared. A failed expectation is an IO error, which ends
-- the run: the tests use fail-fast mode anyway.
module Test.Hspec
  ( Spec, SpecWith, Expectation
  , describe, context, it, specify
  , shouldBe, shouldNotBe, shouldSatisfy, shouldMatchList, shouldReturn
  , expectationFailure
  , hspec
  ) where

import Data.List (delete)

type SpecWith a = IO a
type Spec = SpecWith ()
type Expectation = IO ()

hspec :: Spec -> IO ()
hspec spec = spec >> putStrLn "all passed"

describe :: String -> Spec -> Spec
describe name body = putStrLn name >> body

context :: String -> Spec -> Spec
context = describe

it :: String -> Expectation -> Spec
it name e = e >> putStrLn ("  ok: " ++ name)

specify :: String -> Expectation -> Spec
specify = it

expectationFailure :: String -> Expectation
expectationFailure msg = ioError (userError msg)

infix 1 `shouldBe`, `shouldNotBe`, `shouldSatisfy`, `shouldMatchList`, `shouldReturn`

shouldBe :: (Show a, Eq a) => a -> a -> Expectation
shouldBe got want
  | got == want = return ()
  | otherwise = expectationFailure ("expected: " ++ show want ++ "\n but got: " ++ show got)

shouldNotBe :: (Show a, Eq a) => a -> a -> Expectation
shouldNotBe got bad
  | got /= bad = return ()
  | otherwise = expectationFailure ("not expected: " ++ show got)

shouldSatisfy :: Show a => a -> (a -> Bool) -> Expectation
shouldSatisfy x p
  | p x = return ()
  | otherwise = expectationFailure ("predicate failed on: " ++ show x)

shouldMatchList :: (Show a, Eq a) => [a] -> [a] -> Expectation
shouldMatchList xs ys
  | sameElems xs ys = return ()
  | otherwise = expectationFailure (show xs ++ " is not a permutation of " ++ show ys)
  where
    sameElems [] bs = null bs
    sameElems (a:as) bs = a `elem` bs && sameElems as (delete a bs)

shouldReturn :: (Show a, Eq a) => IO a -> a -> Expectation
shouldReturn action want = action >>= \got -> got `shouldBe` want
