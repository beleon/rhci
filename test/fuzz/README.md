# Differential fuzzing against GHCi

`ruby test/fuzz/run.rb --seed N [--count N] [--bottoms P]` (or `rake fuzz`)
generates random, well-typed expressions (`gen.rb`) over the supported
surface -- numbers and their `show`, Int wrap-around, `div`/`mod`/`quot`/
`rem`, rounding, ranges, strings and `Char`s, lists, `Maybe`, tuples,
Data.Map, Data.Set, derived instances of a sum type, a record and an
infix constructor, user classes (defaults, a superclass, instances with
contexts, a constructor class), printf with random formats, `read` of
`show`n values and `reads` -- plus `:t` of random unannotated
compositions of Prelude functions (types compared up to renaming) -- and
runs them in GHCi (the oracle's podman image; answers cached in
`build/fuzz`) and in rhci.

They must agree as the oracle requires: the same value, or the same kind of
error with the same message, after the same partial output.

`--bottoms P` makes a leaf a tagged error, `(error "e17" :: T)`, with
probability P: that finds evaluation-order differences (what is forced
first, how much is printed before an exception). Where several errors are
pending, Haskell lets an implementation raise any of them, and GHC's choice
depends on its optimiser; such cases are listed as "imprecise", not
counted.

Found and fixed so far (oracle sections 43 and 44 pin them): `:t` kept
no constraint that no instance solves (`Ord (p -> a)`, GHC2021's
FlexibleContexts), did not grow the determined variables through
constraints when defaulting, and printed `((->) a)` as `(-> a)`; Integer
`+` and `-` force their right operand first in GHC; `round`/`floor`/
`ceiling` of an infinite Double crashed rhci; `isSuffixOf` and `unwords`
forced more than GHC's; Int `quotRem`/`divMod` built their pair before
forcing the dividend, Int `rem`/`mod` checked the divisor first; Data.Map
and Data.Set forced the map before the key (containers' bang patterns,
now written as such).
