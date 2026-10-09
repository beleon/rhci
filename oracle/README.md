# GHCi oracle

Reference behaviour from real GHCi, recorded so rhci can be differentially
tested against it.

- `probes.txt`: the inputs, grouped into sections. Each section runs in a fresh GHCi session.
- `golden-ghc-9.6.7.txt`: GHCi 9.6.7's exact output (stdout and stderr merged).
- `run_oracle.py`: regenerates the goldens using the `docker.io/library/haskell:9.6` image.

```
uv run --no-project python run_oracle.py probes.txt > golden-ghc-9.6.7.txt
```

The probes stay inside the feature surface of the original `ghci_test.rb`.
The aim is fidelity on what we cover, not breadth.

## How to compare (semantics, not text)
- **Values**: exact match, including incremental output before an exception.
- **`:t`**: equal up to renaming of type variables, with the constraint set
  compared as a set. `p1 -> p2 -> p1` and `a -> b -> a` count as equal.
- **Errors**: match the *kind* only (parse error, scope error, type error,
  or runtime exception) and the point where it happens. The wording,
  CallStacks, source spans and warnings are ignored.
- **Imports**: rhci has the non-clashing base modules in scope already, so
  a probe that fails in GHCi only because of a missing import (`sort`,
  `fromMaybe`) should succeed in rhci.

## Properties the goldens pin down

### Typing changes what gets printed, not just what `:t` says
- `Circle 5` prints `Circle 5.0`, and `Rectangle 3 4` prints `Rectangle 3.0 4.0`.
  The literal's type comes from the constructor's field type.
- `[1.5, 2, 3]` prints `[1.5,2.0,3.0]`, because the whole list is Double.
- `10 / 3` is a Double and `2 ^ 64` is an Integer (bignum). Defaulting picks the
  type, not the shape of the literal.
- `length [1,2,3] / 2` is a type error (`No instance for ‘Fractional Int’`).
- `id`, `(+)` and `Circle` at the prompt are errors (`No instance for ‘Show (a0 -> a0)’`).
  There is no `<function>` output.
- `data Color = Red | …` without `deriving Show`, followed by `Red`, is an error.
  So is `==` without `deriving Eq`.
- The GHCi defaulting rules are ExtendedDefaultRules: `Nothing`, `[]` and `Left 3`
  print fine, and `head 5` reports `No instance for ‘Num [()]’`.

### Value representation
- Tuples and lists are different things: `zip` gives `[(1,10),…]` and `unzip` gives `([1,2],"ab")`.
- `String` is `[Char]`: `['h','i']` prints `"hi"`, and `[['a'], "b"]` prints `["a","b"]`.
- A Char shows as `'a'`. Non-ASCII characters show as decimal escapes: `"λ"` is `"\955"`
  and `"café"` is `"caf\233"`. The `\&` separator applies: `"\1234\&5"` and `"\SO\&H"`.
- `length "café"` is 4. mruby counts code points only if built with `MRB_UTF8_STRING`.
- Show for Double uses the shortest digits that round-trip, plain decimal for 0.1 ≤ |x| < 10⁷
  and `1.0e7` style otherwise: `5.0e-2`, `1.23456789e7`, `-0.0`, `Infinity`, `NaN`.
  Check that mruby's `Float#to_s` really produces shortest-round-trip digits.
- Negative numbers get parentheses inside constructors (`Just (-3)`, `Circle (-1.0)`)
  but not inside lists, tuples or record fields (`[-1,2]`, `(-1,-2)`, `P {px = 1, py = -2}`).
- Records show as `P {px = 1, py = 2}`. Infix constructors show infix (`3 :+: 4`).

### Numbers
- `Int` wraps at 64 bits (`(maxBound :: Int) + 1` gives `-9223372036854775808`).
  `Integer` is unbounded. mruby needs mruby-bigint for Integer, and Int must be
  masked explicitly on both runtimes.
- `div`/`mod` round toward −∞ and `quot`/`rem` toward 0. `-7 \`div\` 2` parses as `-(7 \`div\` 2)`, which is `-3`.
- `round` rounds half to even (`round 2.5` is `2`). `2 ^ (-1)` raises `Negative exponent`.
- `3 - -2` and `1 < 2 < 3` are fixity errors.
- Ranges over Double overshoot by half a step (`[1.0..3.5]` gives `[1.0,2.0,3.0,4.0]`).
  `[0.1,0.2..0.5]` gives exactly `[0.1,0.2,0.30000000000000004,0.4,0.5]`.

### Laziness and sharing
- `const 1 undefined`, `fst (1, undefined)`, `length [undefined, undefined]`,
  `null (undefined : undefined)`, `let (a, b) = (1, undefined)` and
  `case undefined of _ -> 1` all evaluate without error.
- Output is printed incrementally. The prefix appears before the exception:
  `[1,2,*** Exception: Prelude.undefined` and `"abc*** Exception: …`.
- Self-referential definitions like `fibs !! 1000` need sharing. With call-by-name this is exponential.
- `count 1000000` (non-tail recursion), `foldr (+) 0 [1..1000000]` and
  `sum [1..1000000]` all succeed. This rules out a recursive Ruby evaluator,
  especially on mruby.

### `:t` output format
- Lambda-bound type variables are named `p`, `p1`, `p2`, …. Variables that come from
  instantiating a signature keep the signature's names (`a`, `b`). Others get `t`, `t1`, ….
  For example: `\x y -> x :: p1 -> p2 -> p1`, `compose :: (t1 -> t2) -> (t3 -> t1) -> t3 -> t2`,
  `double :: Num a => a -> a`.
- Constraint order follows the order constraints were generated, not the alphabet:
  `factorial :: (Ord t, Num t) => …`, `xs :: (Num a, Enum a) => [a]`, but
  `[x * 2 | x <- [1..5]] :: (Enum a, Num a) => [a]`.
- The Prelude list functions are Foldable-generalised: `length :: Foldable t => t a -> Int`.
- `head`, `undefined` and `error` show `GHC.Stack.Types.HasCallStack =>`.
- The monomorphism restriction is off in GHCi: `xs = [1..10]` stays polymorphic.
- `:t` echoes the input verbatim, comments included (`1 -- comment :: Num a => a`).

### REPL semantics
- A new definition at the prompt replaces the old one, it does not extend it.
  `f 0 = …` followed by `f 1 = …` leaves `f 0` non-exhaustive. Multi-equation
  definitions need `;` or `:{ :}`.
- `it` is bound to the last expression result, and its type is kept (`:t it`).
- `sort`, `nub`, `fromMaybe`, `isJust`, `swap` etc. are not in scope without
  `import Data.List` / `Data.Maybe` / `Data.Tuple`.
- Runtime errors include the source span: `<interactive>:17:5-11: Non-exhaustive patterns in function f`.
  The line number counts every input line of the session.
- GHCi prints warnings, e.g. `-Woverlapping-patterns` on literal `case` scrutinees.

## Where the original `ghci_test.rb` contradicts GHCi
`swap (1, 2)` expecting `[2,1]`, `zip`/Pythagorean triples printing nested lists,
`sort`/`nub`/`fromMaybe` used without imports, and `data Color` printed without
`deriving Show`.

## Numeric differential suite (`numeric/`)
`cases.txt` (from `tools/gen_numeric_cases.rb`, deterministic) goes through
`Num.hs` with real GHC (`numeric/run.sh`) into `golden.txt`. About 14.5k
cases: Double `show` by bit pattern (edges, every power of ten with its
neighbours, random bits, random decimals), `decodeFloat`,
truncate/floor/ceiling/round, `fromInteger` and `fromRational` to Double
(including ties), decimal literals (`read`, which matches how literals
convert), and `Int` arithmetic on edge values. `test/unit/num_golden_test.rb`
requires an exact match on both runtimes.

