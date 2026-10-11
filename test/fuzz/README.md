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

## Whole programs

`ruby test/fuzz/progs.rb --seed N [--count N] [--bottoms P] [--mruby]` (or
`rake fuzz_progs`) generates random modules (`prog_gen.rb`): a data type
with records and recursive constructors, a class with a default method and
instances (one with a context), and 6-10 functions in the shapes programs
take -- equations over literal, cons, as- and constructor patterns, guards
with `where` (local values and signed local functions), `case` with guarded
alternatives, `let`, structural and counter recursion, mutual recursion,
local helpers used at two types (let polymorphism), point-free lambdas,
some without signatures (file-mode defaulting and the monomorphism
restriction). `main` reads stdin (`getContents`, `getLine` past the end,
`readLn`, `isEOF`, `interact`), keeps an IORef, uses Data.Bits and
Data.Ratio, and prints.

GHC runs each as `runghc Main.hs < input` (cached in `build/fuzz-progs`);
rhci as `:load Main` then `main` with the same stdin -- in process, or with
`--mruby` through the binary, whose stdin the REPL and the program share.
They must print the same, raise the same exception after it, and reject
the same programs. 1 650 programs agree (including the mruby binary on
300 and a run with tagged bottoms); none has disagreed.

## On mruby

`--mruby` runs either fuzzer through the mruby build: expressions and
sessions in the mruby test interpreter (the binary's bundle plus a small
runner, `build/fuzz/mruby_runner.rb`), programs through the binary itself.
The 31 000 cached expressions, the sessions and the programs agree there
too.

## Sessions

`ruby test/fuzz/run.rb --sessions --seed N [--count N]` (`session_gen.rb`)
generates GHCi sessions: definitions and redefinitions (a definition is
recursive, so its own name in the right-hand side is the new one; `x <-
return e` is not), `let`, functions on one line or in `:{ :}` blocks,
`pat <- return e`, expressions and `it`, IO statements (`print`,
`return e`, `mapM_`), and `:t`; each section is one session. 6 000 inputs
agree. Found: GHCi changes `it` only when a statement completes (an
exception while running or printing leaves the previous one), and binds
`()` after `print`.

## Programs, extended

Half the programs are three modules (`Types` with or without an export
list; `Lib` exporting a subset; `Main` importing it qualified, by a list,
hiding some, or whole, and reusing names it cannot see), and functions
now also include a hand-rolled State monad (user Functor, Applicative and
Monad instances, `forM_`, `when`), Maybe and list `do` blocks with
`guard`, a Foldable container, class-polymorphic functions called at
several types, and record updates (`TD {} -> t { tdx = ... }`). 2 100
programs agree. Found: in a module, a top-level definition and an import
of the same name are ambiguous where used (rhci let the definition shadow
the import, which only the prompt does).


## Imports at the prompt

Half the sessions also import along the way (`session_gen.rb`): Data.Map
and Data.Set qualified under changing aliases (Data.Map.Strict under the
same one, so names it redefines become ambiguous), with import and hiding
lists; names from Data.Map unqualified; `import Prelude hiding (...)`,
`import Prelude (...)`, `import qualified Prelude as P`. Their header
imports Data.List without the Prelude names Data.Map clashes with, so that
hiding those from the Prelude means the same in GHCi as in rhci (which has
Data.List in scope regardless). Expressions then use the current aliases
(the generator's qualifiers are variables) and the bare names, in scope or
not, ambiguous or not. Found and fixed (oracle sections 46 and L12):
- the prompt ignored `import Prelude hiding (...)` and `import Prelude
  (...)`; an explicit import of the Prelude replaces the implicit one, and
  a name one import hides is back if another brings it in (`DefaultScope`
  in rename.rb, used for files too);
- a qualified import list (`import qualified Data.Map as M (fromList)`)
  did not restrict `M.`;
- `import Data.Map (insert)` made `insert` ambiguous with Data.List's,
  which rhci has in scope but the user never imported;
- files with `import Prelude (...)`, `import qualified Prelude as P`, or a
  hidden name another import provides were rejected;
- after `:load`, the prompt sees the module's scope (and no implicit
  Prelude), and the module's names do not shadow the prompt's own imports;
- GHC reports an ambiguous name (renamer) before a variable not in scope
  (type checker): rhci reported whichever came first.

## Defaulting: files versus the prompt

`ruby test/fuzz/run.rb --defaulting --seed N [--count N]`
(`default_gen.rb`) generates groups of numeric definitions, mostly
without signatures (literals, arithmetic across the group, functions bound
with and without arguments, `show`, lists, `maxBound`, `read`, ...). Each
group is loaded from a module, where Haskell 2010 defaulting and the
monomorphism restriction decide the types across the whole module, and
typed at the prompt (a `:{ :}` block or line by line), with extended
defaulting and no MR; both sections then print the definitions, ask `:t`
and use them at other types. Each side is compared with GHCi. Seeds 1
and 2 (300 groups, 7 300 inputs) agree. Found: CRuby's `Math.sqrt(-0.0)`
is `0.0`, so `sqrt (negate (sum []))` printed `0.0` (oracle section 47).

The oracle runner caps each GHCi container at 8 GB and kills it after its
time limit: a generated `2 ^ (2 ^ 70)` once grew GHCi to 84 GB.

## Numbers at the edges

`ruby test/fuzz/run.rb --numbers --seed N [--count N]` (`num_gen.rb`):
Doubles from random bit patterns (subnormals, huge values, `-0.0`, NaN,
infinities, halves), Ints and Integers clustered at 2^31, 2^53, 2^63,
2^64, powers of ten and beyond, through `show`/`read`, Numeric's
`showFFloat`/`showEFloat`/`showGFloat`/`showHex`/`floatToDigits`, the
RealFrac and RealFloat methods, conversions, Integral arithmetic (zero
divisors, `minBound \`div\` (-1)`), Data.Bits, Data.Ratio and printf.
Found (oracle section 48, `runtime_assumptions_test`):
- mruby 4.0.0's bignum arithmetic with a fixnum operand: `-18446744073709551614
  + -9` was positive, `~` of a positive bignum off by two, `&`/`^` with a
  negative bignum wrong, `>>` of a negative bignum truncated. rhci-native
  (`src/bigint_ops.c`) replaces those operators for bignum operands;
  mruby and CRuby then agree on 40 000 random pairs, every operator;
- CRuby's `Float#**` returns a Complex for a negative base and a NaN
  exponent (`(-x) ** NaN` crashed rhci), and `(-Infinity) ** 0.5` is
  `+Infinity` in C (and GHC), not NaN;
- `properFraction (-0.0)` is `(0, 0.0)`: GHC's fraction is never `-0.0`.

Seeds 1-3 (30 000 probes) agree on CRuby and on mruby.

## User data types

`ruby test/fuzz/run.rb --datatypes --seed N [--count N]` (`data_gen.rb`):
random declarations (nullary, positional and record constructors, infix
constructors with random fixities, a type parameter, newtypes, fields of
other declared types and of the type itself) deriving Show and a random
choice of Eq, Ord, Read, Enum and Bounded, then `show` at several
precedences and inside other values, `read` of shown and respaced text,
comparisons, ranges and `succ`/`pred` at the ends, `minBound`/`maxBound`,
selectors and updates on the wrong constructor, `:t` of constructors.
Found (oracle sections 49 and L13): derived Show and Read used precedence
9 for an infix constructor whose fixity is declared in the same input or
module (`-3 :| "x"` came out `(-3) :| "x"`); a record update on the wrong
constructor raises GHC 9.6's "Non-exhaustive patterns in case". `:t`
comparisons now ignore GHC2021's kind-polymorphic `forall {k} (a :: k).`
prefix (rhci has no PolyKinds). Seeds 1-3 (7 400 probes) agree.

## Read on damaged input

`ruby test/fuzz/run.rb --reads --seed N [--count N]` (`read_gen.rb`):
text `show` would give for a random value (numbers, Chars and Strings
with every escape form, lists, tuples, Maybe, Either, Ratio, a record and
an infix constructor) altered: other spacing and line breaks, redundant
or missing parentheses, other spellings of numbers (hex, octal, exponents,
signs, `1_000`), truncation, trailing text, other case, a dropped or
doubled comma; then `read`, `reads`, `readMaybe` or `readEither`. 3 000
probes (2 150 parse, 850 fail) agree; nothing found.

## Syntax variation

`ruby test/fuzz/progs.rb --relayout` (`relayout.rb`) respells every
generated module before GHC and rhci see it: lines broken into indented
continuations, `{- -}` comments (nested ones too) between tokens, `--`
comments and blank lines, tabs in the indentation (GHC's 8-column stops),
the top level in explicit braces with semicolons. 300 programs agree, on
CRuby and through the binary; nothing found.

## Type errors, tokens, laziness, classes

- `--typeerrors` (`typeerr_gen.rb`): well-typed expressions changed the
  way a slip would (an annotation or literal of another type, an argument
  dropped, doubled or swapped, a near-miss operator, a wrapping function,
  an ambiguous class use); a third asked `:t`. rhci must accept and
  reject exactly what GHCi does.
- `--tokens` (`lex_gen.rb`): operators made of comment and arrow
  characters, `..` after constructors, negation against sections,
  backticks, `Just.id`, primes, Unicode names, every numeric literal form,
  escapes and gaps, nested and unterminated comments, one-line layout,
  extension keywords as names; half respaced at random.
- `--laziness` (`lazy_gen.rb`): infinite and self-referential structures,
  knot-tying, `~` against strict patterns, failing pattern bindings,
  unused bottoms, `seq`/`$!`/`foldl'`/bang patterns, strict fields,
  newtype against data patterns, output before an exception.
- `--classes` (`class_gen.rb`): random hierarchies with defaults,
  superclass chains, a result-polymorphic method, a constructor class,
  instances with contexts and some left out; probes use them, rely on
  defaulting through them, and define polymorphic functions with `:t`.

Found and fixed (oracle sections 50-52): `let !x = e` did not force `x`
(and a dictionary-abstracted one must not be forced; GHC forces the last
binding first); `enumFromThen` on Integer lacked GHC's `seq` (`take 2 [5,
undefined ..]` printed `[5,`); a kept instance-less constraint's
superclasses are reduced into the context (`Integral [a]` adds `Ord a`)
and defaulting at the prompt sees a class's superclasses (`class Show a
=> C a`); `instance Monoid a => Monad ((,) a)` was missing; the Enum
instances of `()`, Bool, Ordering and Char raise base's messages; a `~`
not in prefix position is an operator. A ground `^` of 4 to 2^127 grew
rhci to 85 GB (now an Integer size limit), and the oracle's `:t`
normaliser looped on GHCi's wrapped answers (fixed). Nothing else
differs in 23 000 probes, on CRuby and mruby.
