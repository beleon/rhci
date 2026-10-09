# rghci architecture (draft for review)

Status: **proposal, nothing implemented.** The scope it serves is in
`CLAUDE.md`: GHCi *semantics* (values, `show` output, what type-checks,
laziness, the syntax users write), not GHCi's text. It must run on CRuby 3.4
and on mruby 4.0, in the lean `mruby_build_config.rb` build.

## 1. Pipeline

```
 input line(s)
    │  REPL: :{ :} grouping, :t / :q dispatch
    ▼
 Lexer + layout ──► tokens with explicit { ; } (Haskell 2010 §10.3)
    ▼
 Parser ──► surface AST; operator chains kept flat (unresolved)
    ▼
 Renamer ──► unique names, GHCi shadowing, fixity resolution,
    │        dependency analysis (SCCs) of binding groups,
    │        `deriving` expanded into ordinary instance declarations
    ▼
 Desugarer ──► Core: λ, app, var, lit, con, letrec groups, flat case
    │          (match compiler; guards, where, if, comprehensions,
    │           sections, ranges, literals → class methods)
    ▼
 Type checker ──► HM + type classes; elaborates Core with explicit
    │             dictionary λ/app; defaulting; answers :t
    ▼
 Lowering ──► machine Core: A-normal form, env slots resolved
    ▼
 Machine ──► lazy graph reduction on an explicit stack
    ▼
 REPL runs `print it` (or the IO action) and streams the characters out
```

Every input is checked in full before anything runs or any binding is added.
A type error leaves the session unchanged, as in GHCi.

## 2. Front end

### Lexer and layout
- Unicode-aware, working on code points (`String#codepoints`, which both runtimes have).
- Implements the full Haskell 2010 escape set for chars and strings
  (`\SOH`, `\^A`, `\&`, string gaps). The goldens rely on it.
- **Numeric literals are parsed by us** into an exact `Integer` or an exact
  rational. A Fractional literal is converted to Double with correct
  rounding by our own code: mruby's parser flushes `5e-324` to `0.0`, and
  only its parser is broken (`Math.ldexp`/`frexp` handle subnormals fine on both runtimes).
- Layout is the Report's algorithm *L*, implemented as a token-stream
  transformer. It includes the parse-error(t) rule (`let x = 1 in …`
  closes the implicit block on `in`), handled by having the parser ask the
  layout stage to close the innermost implicit block.

### Parser
- Hand-written recursive descent. Recursion follows **syntactic nesting
  only**. Anything that grows with input length is a loop: list
  literals, application spines `f a b c`, operator chains, declarations,
  case alternatives.
- An operator chain `a + b * - c` is parsed as a flat sequence and
  resolved later, because fixities can come from user `infixl` declarations.

### Renamer
- Assigns every binder a unique id. **GHCi scoping:** a new prompt
  definition shadows the old name, and earlier definitions keep pointing at
  the binding they saw (`x = 5; y = x + 1; x = 10; y` gives `6`).
  `f 0 = …` followed by `f 1 = …` on separate prompts is a redefinition;
  equations only merge within one input.
- **Fixity resolution** follows the Report §10.6 algorithm, including the
  negation rules: `- 5` and `-2 ^ 2` give `-4`, and `3 - -2` and `1 < 2 < 3` are errors.
- **Dependency analysis** splits each declaration group into strongly
  connected components (iterative Tarjan), because HM generalisation needs
  that ordering.
- **Default scope** is Prelude plus the non-clashing parts of Data.List,
  Data.Maybe, Data.Char, Data.Tuple, Data.Function, Data.Ord,
  Data.Either and Control.Monad. `import M` of a known module is accepted
  as a no-op. The list only grows when coverage needs it.
- **`deriving` (Show, Eq, Ord, Enum, Bounded)** is expanded here into
  ordinary instance source, following the Report's derivation rules
  verbatim. That alone yields `Just (-3)`, `Circle (-1.0)`,
  `P {px = 1, py = -2}` and `3 :+: 4` with no special cases in the printer.

### Desugarer to Core
- **Match compilation** (Wadler/Augustsson style) turns multi-equation
  functions, nested patterns, guards with fall-through, as-patterns,
  irrefutable `let` patterns, and lambda/case patterns into flat
  single-level `case`. A failed match calls an error with the GHCi-style
  message (`Non-exhaustive patterns in function f`).
- **Literals become class methods:** `fromInteger n` and `fromRational r`,
  and literal patterns become `==` tests. This makes the type checker infer
  `Num`/`Eq` exactly as Haskell does.
- The remaining sugar maps onto Prelude functions per the Report:
  comprehensions → `concatMap`, ranges → `enumFromThenTo`, `if` → `case`,
  sections → λ, `where` → `let`, `do` → `>>=`/`>>`.
- **String literals stay a single node** (an array of code points) and are
  unpacked lazily at run time. A 10k-character literal is not 10k cons
  nodes in the AST.

## 3. Type system

### Representation
- Types are `TVar` (mutable link plus a *level*), `TCon` (name and kind)
  and `TApp`. Functions are `TApp(TApp(->, a), b)` and lists are `TApp([], a)`.
  Because application is first-order, constructor classes (`Foldable t`,
  `Functor f`) unify structurally with no special machinery.
- Kinds are inferred for `data` and `class` declarations, defaulting to `*`.

### Inference
- **Algorithm W with level-based generalisation** (Rémy/OCaml style),
  processing one SCC at a time. Explicit signatures are checked and then
  used as the binding's type. Polymorphic recursion is allowed only with a
  signature, as in Haskell.
- **No monomorphism restriction**, because GHCi turns it off.
- **Constraints** are collected as predicates `C τ` and reduced by
  instance lookup (`Show [a]` → `Show a`). A constraint on a concrete type
  with no instance is a type error (`length xs / 2` →
  `No instance for Fractional Int`).
- Constraints entailed through a superclass are dropped (`Ord t` subsumes
  `Eq t`), so `:t factorial` gives `(Ord t, Num t) => t -> t` up to renaming.
- **Defaulting:** a type variable with constraints that is ambiguous (it
  appears in neither the type nor the environment) is defaulted. Interactive
  input uses GHCi's ExtendedDefaultRules (candidates `()`, `[]`, `Integer`,
  `Double`; interactive classes allowed). Prelude code uses the standard
  rules. This is why `Nothing` and `[]` print, `2 ^ 64` is an Integer, and
  `head 5` is a type error.

### Classes and instances
- **Haskell 98 classes:** single parameter, superclasses, default methods,
  and instance heads of the form `C (T a1 … an)` with contexts. That covers
  Eq, Ord, Show, Enum, Bounded, Num, Real, Integral, Fractional, Floating,
  RealFrac, RealFloat, Semigroup, Monoid, Functor, Applicative, Monad,
  Foldable, Traversable, plus user-declared classes.
  - `Show` includes **`showList`**. That is the Report's trick that makes
    `"hi"` and `[['a'],"b"]` print as strings, so we use the class as
    specified rather than special-casing the printer.
- **Elaboration (dictionary passing):** a dictionary is a constructor value
  whose fields are the methods and the superclass dictionaries. A method is
  a field selector. An instance with a context is a function from
  dictionaries to a dictionary.
- **Sharing rule:** dictionary λs wrap the *whole* recursive group, and
  recursive references inside the group use the inner, monomorphic binder.
  So `fibs = 0 : 1 : zipWith (+) fibs (tail fibs)` elaborates to
  `fibs = \dNum -> letrec f = 0 : 1 : zipWith (+) f (tail f) in f`. The
  knot is still shared, and `fibs !! 1000` stays linear even though
  `fibs :: Num a => [a]`.

### `:t`
- `:t e` infers and generalises with no defaulting, simplifies the
  constraints, renames variables (`a`, `b`, …) and prints. Because names
  and order don't matter, the naming scheme can be the simplest one.

## 4. Runtime

### Values
| Haskell | Ruby representation |
|---|---|
| `Int` | Ruby `Integer`, wrapped to 64 bits after every arithmetic primop |
| `Integer` | Ruby `Integer` (bignum through mruby-bigint) |
| `Double` | Ruby `Float` |
| `Char` | Ruby `Integer` code point |
| data constructors, tuples, lists, `()`, `Bool` | `Con` object: tag plus a field array |
| functions | `Fun` (arity, code, env), `PAP` (partial application) |
| unevaluated | `Thunk` (code, env), overwritten in place when evaluated |

Types are erased after checking. Nothing at run time asks "is this a
list?". Printing goes through the `Show` dictionary like any other code.

### The machine
- A **lazy eval/apply machine** in the spirit of the STG machine and
  Sestoft's mark-2, interpreting machine Core in A-normal form.
  Allocation happens only at `let`, arguments are atoms, and `case` is the
  only thing that forces evaluation.
- **One `while` loop and an explicit frame stack** (a Ruby Array). The
  frames are *update* (thunk under evaluation), *apply* (pending
  arguments) and *case continuation*. Evaluation never uses Ruby
  recursion, so `foldr (+) 0 [1..10⁶]` and the non-tail `count 1000000`
  only grow an Array.
- **Primitives never force.** Core wraps every primop in `case`, so
  primops see already-evaluated, unboxed values and are plain Ruby methods
  (`plusInt`, `quotInteger`, `showDouble`, …).
- **Call-by-need:** a thunk is overwritten with its value through the update
  frame. While a thunk is under evaluation it is *blackholed*, so re-entering
  it raises `<<loop>>` instead of overflowing the stack.
- **Exceptions** (`error`, `undefined`, a failed match, `div` by zero) unwind
  the frame stack. Thunks under evaluation are overwritten to re-raise the
  same exception, which is semantically what GHC does.
- **IO uses state-token passing**, as in GHC. `IO a` is a function of a
  dummy token, so `do`-notation is just `Monad IO`. `putStr` is written in
  Haskell as `putChar` per character. That gives **incremental output for
  free**: `[1, 2, undefined]` prints `[1,2,` and then
  `*** Exception: Prelude.undefined`, because the REPL flushes before
  reporting the exception.

### Numerics (must match exactly)
- **`Int`** is wrapped with `((x + 2**63) % 2**64) - 2**63`, and so are
  `maxBound`, `minBound` and `fromIntegral`. **`Integer`** is unbounded.
- `div`/`mod` map to Ruby `/` and `%`. `quot`/`rem` use truncation and `remainder`.
  Division by zero raises `divide by zero`.
- **Double → String:** a Ruby port of GHC's `floatToDigits` (Burger–Dybvig,
  shortest digits that round-trip) on exact Integers, plus `showFloat`'s
  layout (fixed notation when 0.1 ≤ |x| < 10⁷, otherwise `d.ddde±n`).
  The mantissa and exponent come from `Math.frexp` (exact on both runtimes).
  Ruby's own `Float#to_s` is never used, because mruby's prints `%.15g`.
- **Double → Integer** (`truncate`/`floor`/`round`/`ceiling`) uses
  `frexp` plus Integer shifts, because mruby's `Float#to_i` is wrong past 2⁶³.
  `round` rounds half to even, as in `properFraction` in base.
- `enumFromThenTo` for Double, `^`/`^^`/`**`, `gcd`, `lcm` and similar are
  **ported from base's Haskell source** into the Prelude, so their edge
  cases (overshoot by half a step, `Negative exponent`) match by construction.

### Prelude
- **Written in Haskell** (`prelude/*.hs`), ported from base where possible.
  Ruby supplies only primitives: arithmetic and comparison per numeric
  type, char/code point conversion, `showDouble`, `error`, `seq`, `putChar`
  and `getLine`.
- It is compiled through the normal pipeline at startup. If that turns out
  slow on mruby (to be measured, not guessed), a build step snapshots the
  elaborated Core and type environment as a Ruby data literal.

## 5. REPL surface
- An input is one of: an expression, a declaration group (functions,
  signatures, `data`, `newtype`, `class`, `instance`, fixity), a
  `let` without `in`, a `pat <- io`, or `import`.
- **Expression of type `IO t`:** run it, and print the result unless `t` is `()`.
- **Any other expression:** bind `it` generalised (`:t it` gives `Num a => a`),
  then run `print it` at the defaulted type. With no `Show` instance this is a
  type error (functions, or `data` without `deriving Show`).
- **Commands:** `:t`/`:type`, `:q`/`:quit`, `:{ … :}`, and a minimal `:?`.
- **Error classes:** parse, scope, type and runtime. The text is GHC-like
  but not GHC-exact, for example `*** Exception: Prelude.head: empty list`.
- **Ctrl-C:** on CRuby an `INT` trap sets a flag the machine polls, and
  GHCi prints `Interrupted.`. mruby has no signal handling, so Ctrl-C ends
  the process there. That goes behind the runtime shim.

## 6. Dual-runtime discipline
- **One source tree, one manifest.** `lib/rghci/manifest.rb` lists the
  files in load order. CRuby loads them with `require_relative`. For mruby,
  `tools/bundle.rb` concatenates them (Prelude `.hs` embedded as heredocs)
  into `build/rghci.rb`, because mruby has no `require`.
- **`lib/rghci/shim.rb` is the only file that may branch on runtime.** It
  covers reading lines, flushing, reading files, interrupts and `exit`.
- **Coding rules,** checked by a lint script that greps for forbidden constructs:
  - No `Struct`, `Set`, `catch`/`throw`, `Fiber`, `format`/`sprintf`/`%`,
    `pack`, `instance_variable_get`, `ObjectSpace`, or `case/in`.
  - No blockless enumerators (`each_char` with no block, `each_with_index.map`).
  - Never `Float#to_s`/`to_i` on a Haskell-visible value.
  - Recursion is allowed only along syntactic nesting (parser, renamer,
    type checker), and every recursive pass carries a depth guard that
    raises a clean "too deeply nested" error.
  - Inside recursive methods, iterate with `while`, not blocks. On mruby a
    block frame costs as much as about 4 plain frames.
- **Recursion budget (measured):** stock mruby allows about 508 plain
  frames and about 100–170 through `map`/`each`, while CRuby allows about
  10k and 3.7k. With `MRB_CALL_LEVEL_MAX=100000` in the build config,
  mruby reaches about 131k plain and 26k–44k through blocks, which is
  deeper than CRuby. **Proposal:** set that define in our build, and keep
  the machine stack-free regardless.

## 7. Testing
- **Oracle runner** (`test/oracle_test.rb`): replays `oracle/probes.txt` on
  each runtime and compares against the goldens using the semantic rules.
  Values must match exactly. `:t` results are compared up to renaming with
  constraints as a set. Errors are compared by class only. It runs green or
  red per section, and expected gaps are listed in a single
  `oracle/known_gaps.txt` instead of hiding them.
- **A tiny in-house test framework** that works on both runtimes
  (`assert_equal`, sections, a failure summary). It replaces the
  minitest/test-unit that mruby lacks.
- **Focused differential suites** from the GHC container:
  - about 10k random and edge-case Doubles through `show` (subnormals,
    powers of ten, 0.1 ≤ x < 10⁷ boundaries)
  - `Int` overflow
  - `div`/`mod`/`quot`/`rem` sign tables
  - `round`/`truncate` on halves
- **`rake test` runs everything twice,** on `ruby` and on
  `build/mruby/bin/mruby` against the bundle. A test that passes on one
  runtime only counts as failing.

## 8. Build order
Each step ends green on **both** runtimes before the next one starts.

1. **Skeleton:** manifest, shim, bundler, test framework, lint, `rake test`
   on both runtimes.
2. **Lexer, layout, parser, fixity:** a parse-only pass over every probe,
   with error *class* matching the goldens for parse errors.
3. **Machine and primitives** driven by hand-written Core: laziness,
   sharing, deep stacks, exceptions, incremental output. Also
   `showDouble`, `Int` wrapping and float→integer conversion, with their
   differential suites.
4. **HM without classes:** monomorphic Core types and `:t` for
   Bool/Char/list/function types.
5. **Classes:** dictionary elaboration, defaulting, deriving, and the
   Prelude in Haskell. Then the oracle sections switch on one by one.
6. **REPL surface:** `it`, shadowing, IO at the prompt, `:{ :}`. The full
   oracle should then be green or in `known_gaps.txt`.
7. **Performance:** measure on mruby, then add the Prelude snapshot and
   machine fast paths if they're needed.

## 9. Open questions
1. **The mruby target:** is it our build (which can set
   `MRB_CALL_LEVEL_MAX`), or must rghci also run on stock and embedded
   mruby builds we don't control? The second option forces the parser and
   type checker onto explicit stacks too, which is much more work.
2. **Performance expectations** on mruby: acceptable startup time, and how
   long `sum [1..10^6]` may take.
3. **`Float` (32-bit):** leave it out, or emulate single-precision rounding?
   It is not in the probe surface.
4. **`:load file.hs`:** the original had it. Should it be in scope now,
   later, or not at all?
