# Differential fuzzing against GHCi

`ruby test/fuzz/run.rb --seed N [--count N] [--bottoms P]` (or `rake fuzz`)
generates random, well-typed expressions (`gen.rb`) over the supported
surface -- numbers and their `show`, Int wrap-around, `div`/`mod`/`quot`/
`rem`, rounding, ranges, strings and `Char`s, lists, `Maybe`, tuples,
Data.Map, Data.Set, and derived instances of a sum type, a record and an
infix constructor -- and runs them in GHCi (the oracle's podman image;
answers cached in `build/fuzz`) and in rhci.

They must agree as the oracle requires: the same value, or the same kind of
error with the same message, after the same partial output.

`--bottoms P` makes a leaf a tagged error, `(error "e17" :: T)`, with
probability P: that finds evaluation-order differences (what is forced
first, how much is printed before an exception). Where several errors are
pending, Haskell lets an implementation raise any of them, and GHC's choice
depends on its optimiser; such cases are listed as "imprecise", not
counted.

Found and fixed so far (oracle section 43 pins them): `round`/`floor`/
`ceiling` of an infinite Double crashed rhci; `isSuffixOf` and `unwords`
forced more than GHC's; Int `quotRem`/`divMod` built their pair before
forcing the dividend, Int `rem`/`mod` checked the divisor first; Data.Map
and Data.Set forced the map before the key (containers' bang patterns,
now written as such).
