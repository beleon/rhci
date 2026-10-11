# rhci architecture

This document describes rhci as it is implemented. The goal is GHCi
*semantics* (values, `show` output, what type-checks, laziness, the syntax
users write), not GHCi's text. Contributor rules (scope decisions, the
dual-runtime rules and the measured mruby facts the design relies on) are
in `docs/DEVELOPMENT.md`.

There are two deliverables from one source tree:
- **CRuby library:** embedded in long-running Ruby programs. Startup time
  matters little. Isolation, no global side effects, and host control over
  runaway evaluation matter a lot.
- **mruby standalone command `rhci`:** built only with our own
  `mruby_build_config.rb`. On the development machine the prompt is usable
  in under 10 ms and `rhci -c EXPR` finishes in under 200 ms (§6).

**Fail, don't approximate.** If something can't be done with GHCi's exact
semantics, rhci rejects it with an explicit "unsupported: …" error. It
never substitutes something close. This covers unsupported syntax and
extensions, types rhci does not provide (`Float`), and numeric edge cases
it can't reproduce exactly. A wrong answer that looks right is the worst
outcome. Runtime performance is best effort.

## 1. Pipeline

```
 input line(s)
    │  REPL: :{ :} grouping, command dispatch
    ▼
 Lexer + layout ──► tokens with explicit { ; } (Haskell 2010 §10.3)
    ▼
 Parser ──► surface AST; operator chains kept flat (unresolved)
    ▼
 Renamer ──► unique names, GHCi shadowing, imports, fixity resolution,
    │        dependency analysis (SCCs) of binding groups,
    │        `deriving` expanded into ordinary instance declarations
    ▼
 Kind inference ──► kinds of declarations; signatures and heads checked
    ▼
 Type checker ──► HM + type classes over the renamed source; records
    │             types and dictionary evidence; defaulting; answers :t
    ▼
 Desugarer ──► Core: λ, app, var, lit, con, letrec groups, flat case
    │          (match compiler; guards, where, if, comprehensions,
    │           sections, ranges), with explicit dictionaries, and
    │           primitive operations where the types are known
    ▼
 Simplifier ──► Core to Core: inlining, case-of-known, specialisation
    ▼
 Lowering ──► machine code: A-normal form, env slots resolved
    ▼
 Machine ──► lazy graph reduction on an explicit stack
    ▼
 REPL runs `print it` (or the IO action) and streams the characters out
```

The files, in load order, are listed in `lib/rhci/manifest.txt`. Every
input runs the whole pipeline, and the session's names, types and globals
are updated only once the input has checked completely. A type error leaves
the session unchanged, as in GHCi. Type checking comes before desugaring
(as in GHC), so the desugarer knows the types: it inserts dictionaries and
turns arithmetic at known types into single primitive operations.

## 2. Front end

### Lexer and layout
- Unicode-aware, working on code points (`String#codepoints`, which both
  runtimes have).
- Implements the full Haskell 2010 escape set for chars and strings
  (`\SOH`, `\^A`, `\&`, string gaps).
- **Numeric literals are parsed by rhci** into an exact `Integer` or an
  exact rational. A Fractional literal is converted to Double with correct
  rounding by rhci's own code, because mruby's float parser flushes
  subnormals to zero.
- Layout is the Report's algorithm *L*, implemented as a token-stream
  transformer. It includes the parse-error(t) rule (`let x = 1 in …`
  closes the implicit block on `in`), handled by having the parser ask the
  layout stage to close the innermost implicit block.

### Parser
- Hand-written recursive descent. Recursion follows **syntactic nesting
  only**, capped at 400 levels ("expression nested too deeply"), which
  also bounds the recursion of the later passes. Anything that grows with
  input length is a loop: list literals, application spines `f a b c`,
  operator chains, declarations, case alternatives.
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
  Data.Either, Control.Monad, System.IO, System.Environment, Text.Read,
  Data.Bits, Data.Ratio, Data.IORef and Text.Printf (`DEFAULT_MODULES`).
  This is a deliberate difference from GHCi: `sort` or `fromMaybe` work
  without an import.
- **Modules.** `lib/rhci/base_names.rb` is generated by
  `tools/gen_base_names.rb` from GHCi's `:browse` of each module: what
  every known module exports (`MODULE_EXPORTS`). Modules that clash with
  the Prelude (Data.Map, Data.Map.Strict, Data.Set) are imported, as in
  GHC: `import qualified Data.Map as M`, `import Data.Set (Set, member)`,
  `hiding`, aliases shared by several imports, and explicit imports of the
  Prelude itself (`import Prelude hiding (…)` replaces the implicit one).
  Their implementations are library modules (`LIBRARY_IMPLEMENTATIONS`):
  Haskell sources under `prelude/Data/`, ported from containers, compiled
  in file mode after the Prelude and kept in the snapshot. At the prompt,
  as in GHCi, a fully qualified name (`Data.Map.fromList`) works without
  an import.
  - An import of a module rhci does not know, or of an item the module
    does not export, is an error. A known name that rhci does not
    implement fails as `unsupported` when used.
- **`deriving` (Show, Read, Eq, Ord, Enum, Bounded)** is expanded here
  (`lib/rhci/derive.rb`) into instance source text following the Report's
  derivation rules as GHC implements them, then parsed and treated like a
  user-written instance. That alone yields `Just (-3)`, `Circle (-1.0)`,
  `P {px = 1, py = -2}` and `3 :+: 4` with no special cases in the
  printer. Generated code refers only to Prelude-internal aliases, so user
  definitions cannot capture it.

### Desugarer to Core
- **Match compilation** turns multi-equation functions, nested patterns,
  guards with fall-through, as-patterns, irrefutable and bang patterns,
  and lambda/case patterns into flat single-level `case`. A failed match
  calls an error with the GHCi-style message (`Non-exhaustive patterns in
  function f`). Pattern-match failure continuations are functions of a
  dummy argument, not thunks, so a recursive call from a later clause is
  still a tail call.
- **Literals become class methods:** `fromInteger n` and `fromRational r`,
  and literal patterns become `==` tests. This makes the type checker infer
  `Num`/`Eq` exactly as Haskell does.
- The remaining sugar maps onto Prelude functions per the Report:
  comprehensions → `concatMap`, ranges → `enumFromThenTo`, `if` → `case`,
  sections → λ, `where` → `let`, `do` → `>>=`/`>>` (and `fail` only where
  GHC uses MonadFail).
- **String literals stay a single node** (`Core::Str`) and are unpacked
  lazily at run time. A 10k-character literal is not 10k cons nodes.

## 3. Types and kinds

### Representation
- Types (`lib/rhci/types.rb`) are plain data so they can be snapshotted:
  `TMeta` (unification variable with a link and a *level*), `TSkol`
  (rigid variable from a signature), `TCon`, `TAp`, and `TGen` (the i-th
  quantified variable of a `Scheme`). Functions are `TAp(TAp(->, a), b)`.
  Because application is first-order, constructor classes (`Foldable t`,
  `Functor f`) unify structurally with no special machinery.

### Kind inference
`lib/rhci/kinds.rb` infers kinds as GHC2021 does (PolyKinds): each
declaration group's kinds are found by unification, and what stays open is
generalised (`data P a = P` has kind `k -> *`), so each use instantiates
it afresh. Signatures, annotations and instance heads are checked against
the declared kinds, so ill-kinded declarations are rejected. `:kind`
prints `*`, `Constraint` and kind variables `k`, `k1`, ….

### Two checking modes
GHCi checks prompt input and loaded files under different flags. Both
modes are implemented and tested separately:

| | prompt input | `:load`ed file |
|---|---|---|
| monomorphism restriction | off | **on** |
| defaulting | ExtendedDefaultRules | standard Haskell 2010 rules |

### Inference
- **Algorithm W with level-based generalisation** (Rémy/OCaml style),
  processing one SCC at a time. Explicit signatures are checked and then
  used as the binding's type. Polymorphic recursion is allowed only with a
  signature, as in Haskell.
- **Constraints** are collected as predicates `C τ` and reduced by
  instance lookup (`Show [a]` → `Show a`). A constraint on a concrete type
  with no instance is a type error (`length xs / 2` →
  `No instance for Fractional Int`).
- Constraints entailed through a superclass are dropped (`Ord t` subsumes
  `Eq t`), so `:t factorial` gives `(Ord t, Num t) => t -> t` up to renaming.
- **Defaulting:** a constrained type variable that is ambiguous is
  defaulted. Interactive input uses GHCi's ExtendedDefaultRules
  (candidates `()`, `[]`, `Integer`, `Double`; interactive classes
  allowed, superclasses seen through). The Prelude and loaded files use
  the standard rules. This is why `Nothing` and `[]` print, `2 ^ 64` is an
  Integer, and `head 5` is a type error.

### Classes and instances
- **Haskell 98 classes:** single parameter, superclasses, default methods,
  and instance heads of the form `C (T a1 … an)` with contexts. That covers
  Eq, Ord, Show, Read, Enum, Bounded, Num, Real, Integral, Fractional,
  Floating, RealFrac, RealFloat, Semigroup, Monoid, Functor, Applicative,
  Monad, MonadFail, Foldable and Traversable, plus user-declared classes.
  - `Read` is a port of base's ReadP, ReadPrec, Text.Read.Lex and GHC.Read,
    so what parses, what is ambiguous and what `reads` leaves over are
    GHC's by construction, and derived Read is GHC's generated code.
    ReadP's type is rank-2 (`forall b. (a -> P b) -> P b`); rhci fixes `b`
    to `()` and coerces at the three places that instantiate it otherwise
    (running a parser, `<++`, `gather`). The machine is untyped, so the
    `coerce` primitive is the identity.
  - `Show` includes **`showList`**, the Report's trick that makes `"hi"`
    and `[['a'],"b"]` print as strings, so the printer has no special case.
- **Equality contexts** `(a ~ T) => C (K a)` are allowed in instance
  contexts, for Text.Printf's `(a ~ ()) => PrintfType (IO a)`: selecting
  the instance unifies the argument with `T`, so `x <- printf "…"` gives
  `x :: ()`. Equality constraints elsewhere are unsupported.
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

### Constraints GHC2021 keeps
- A constraint no instance solves is kept while it mentions a type
  variable (FlexibleContexts): `max (\y -> 1) :: (Ord (p -> a), Num a) =>
  ...`; a ground one (`Num String`) is an error. Its superclasses are
  reduced into the context (`Integral [a]` adds `Ord a`). A use at
  concrete types then fails.
- Defaulting and ambiguity follow GHC's growThetaTyVars: a variable is
  determined by the type if it is in it or shares a constraint with one
  that is, so `toEnum 1 mempty :: (Enum (t1 -> t2), Monoid t1) => t2`.
  An undetermined constraint on a compound type is ambiguous.

### `:t`
- `:t e` infers and generalises with no defaulting, simplifies the
  constraints, renames variables (`a`, `b`, …) and prints. Variable names
  and constraint order are not required to match GHCi's.

## 4. Runtime

### Values
| Haskell | Ruby representation |
|---|---|
| `Int` | Ruby `Integer`, wrapped to 64 bits after every arithmetic primop |
| `Integer` | Ruby `Integer` (bignum through mruby-bigint) |
| `Double` | Ruby `Float` |
| `Char` | Ruby `Integer` code point |
| data constructors, tuples, lists, `()`, `Bool` | `ConValue`: a flat Array `[con, field0, …]`; nullary constructors are shared |
| functions | `Fun` (flat Array: code and captured values), `PAP` (partial application) |
| unevaluated | `Thunk` (flat Array: code and captures), overwritten in place when evaluated; `StringThunk` for a literal |

Values are flat Array subclasses so that each is one object rather than an
object plus a field array; on mruby this cut memory by about a third and
with it most of the GC's superlinearity at depth. Types are erased after
checking. Nothing at run time asks "is this a list?". Printing goes
through the `Show` dictionary like any other code.

### The machine
- A **lazy eval/apply machine** in the spirit of the STG machine and
  Sestoft's mark-2 (`lib/rhci/vm.rb`), interpreting the code `Lower`
  produces: plain Arrays `[op, …]` with integer opcodes, variables
  resolved to local slots, environment slots or global cells, in A-normal
  form. Allocation happens only at `let`, arguments are atoms, and `case`
  is the only thing that forces evaluation.
- **One `while` loop and an explicit frame stack.** The frames are
  *update* (thunk under evaluation), *apply* (pending arguments) and
  *case continuation* (three stack entries, not an object). Evaluation
  never uses Ruby recursion, so `foldr (+) 0 [1..10⁶]` and a non-tail
  `count 1000000` only grow the stack. The stack is segmented
  (`VM::FrameStack`), because mruby's incremental GC rescans a huge Array
  that is written constantly. Known saturated calls and already-evaluated
  scrutinees are short-cut.
- **Primitives never force.** Core wraps every primop in `case`, so
  primops see already-evaluated, unboxed values and are plain Ruby methods
  (`plusInt`, `quotInteger`, `showDouble`, …), one method per primitive,
  called without an argument array.
- **Call-by-need:** a thunk is overwritten with its value through the update
  frame. While a thunk is under evaluation it is *blackholed*, so re-entering
  it raises `<<loop>>` instead of overflowing the stack.
- **Exceptions** (`error`, `undefined`, a failed match, `div` by zero) unwind
  the frame stack. Thunks under evaluation are overwritten to re-raise the
  same exception, as GHC does. A host limit or Ctrl-C instead resets them,
  so they can be demanded again.
- **IO** is `newtype IO a = IO (() -> IORes a)`: a function of a dummy
  token, so `do`-notation is just `Monad IO`. `putStr` is written in
  Haskell as `putChar` per character. That gives **incremental output for
  free**: `[1, 2, undefined]` prints `[1,2,` and then
  `*** Exception: Prelude.undefined`, because the REPL flushes before
  reporting the exception.

### The C evaluation loop (mruby builds)
`mrbgems/rhci-native/src/machine.c` is a line-by-line port of
`Machine#run_ruby` that works on the same Ruby objects (code Arrays,
thunks, closures, constructor values, the segmented frame stack) and calls
the same Ruby primitives, except for fixnum and Double arithmetic, which
it does in C. CRuby always runs the Ruby loop, which stays the reference.
**A change to one loop is a change to both:** `native_machine_test`
requires the two to give identical output, errors and step counts, and
`rake torture` runs the mruby tests with forced collections inside the C
loop to check its GC rooting (mruby does not scan C locals; the loop
resets the GC arena each step and re-protects its registers).

The same gem holds `bigint_eq.c` and `bigint_ops.c`, which replace
mruby 4.0.0's Integer comparison and bitwise/additive operators for
bignum operands (they give wrong results there), and `term.c`, the
terminal helpers (§6).

### Numerics (must match exactly)
- **`Int`** is wrapped with `((x + 2**63) % 2**64) - 2**63`, and so are
  `maxBound`, `minBound` and `fromIntegral`. **`Integer`** is unbounded,
  up to the session's integer size limit (§6).
- `div`/`mod` map to Ruby `/` and `%`; `quot`/`rem` are computed from
  them. Division by zero raises `divide by zero`.
- **Double → String:** a Ruby port of GHC's `floatToDigits` (Burger–Dybvig,
  shortest digits that round-trip) on exact Integers, plus `showFloat`'s
  layout (fixed notation when 0.1 ≤ |x| < 10⁷, otherwise `d.ddde±n`).
  The mantissa and exponent come from `Math.frexp` (exact on both runtimes).
  Ruby's own `Float#to_s` is never used, because mruby's prints `%.15g`.
- **Double → Integer** (`truncate`/`floor`/`round`/`ceiling`) uses
  `frexp` plus Integer shifts, because mruby's `Float#to_i` is wrong past 2⁶³.
  `round` rounds half to even, as in base.
- `enumFromThenTo` for Double, `^`/`^^`/`**`, `gcd`, `lcm` and similar are
  **ported from base's Haskell source** into the Prelude, so their edge
  cases (overshoot by half a step, `Negative exponent`) match by construction.

### Prelude
- **Written in Haskell**: `prelude/Prelude.hs` (about 4400 lines) plus the
  containers ports under `prelude/Data/`, taken from base and containers
  with GHC's definitions wherever behaviour is observable (evaluation order
  included). Ruby supplies only primitives (`foreign import prim`):
  arithmetic and comparison per numeric type, char/code point conversion
  and classification, `showDouble`, `error`, `seq`, handle IO (`hPutChar`,
  `getChar`, `getLine`, `isEOF`, a lazily read stdin, `getArgs`, buffering
  modes), bit operations, IORefs, and files.
- **Files** (`readFile`, `writeFile`, `appendFile`) follow GHC's
  observable behaviour, checked against the oracle
  (`oracle/probes_files.txt`):
  - `readFile` opens, reads and decodes (strict UTF-8) the file at once,
    hands the characters out lazily, and holds GHC's per-file read lock
    until the String reaches its end, so writing a file that is still
    being read fails with `resource busy (file is locked)`. A decoding
    error surfaces where GHC's does: after the characters before it.
  - `writeFile`/`appendFile` truncate (or create) first, then commit the
    String in GHC's 2047-character chunks (`hPutStr`'s `writeBlocks`),
    so a String that fails part way leaves exactly GHC's prefix in the
    file. Error messages are GHC's (`openFile: does not exist (No such
    file or directory)`, `withFile: inappropriate type (Is a directory)`).
- **Text.Printf and Numeric** are base's code (formatRealFloat,
  floatToDigits, roundTo from GHC.Float). Where GHC estimates
  floatToDigits's exponent with `Float` logarithms (bases other than 10),
  rhci counts up from below the estimate to the exact exponent.
- **Data.Char is GHC's Unicode.** General categories, simple case
  mappings and the Uppercase/Lowercase properties come from GHC itself:
  `oracle/unicode/Tables.hs` dumps them in the oracle container and
  `tools/gen_unicode.rb` packs them into `lib/rhci/unicode_data.rb`,
  decoded on first use.

### The Core simplifier
`lib/rhci/simplify.rb` runs between the desugarer and `Lower`. Every rule
keeps call-by-need: only lambdas, atoms and constructor applications are
duplicated or moved, and a `case` that forces an unevaluated scrutinee is
never dropped.
- dead lets, inlining of single-use and small lambdas, beta reduction;
- case of known constructor/literal, binder swap, and merging a case on
  an already evaluated variable into the enclosing case (so the
  desugarer's clause-by-clause matching becomes one case per variable),
  unreachable defaults;
- case-of-case with one inner alternative, case-of-let, application
  pushed into case/let, let-to-case for a thunk forced at once, integer
  primitives on literals folded.

Across definitions, **unfoldings** (the simplified Core of small global
functions and of constants; dictionary fields are lifted to globals so
every instance is a constant) make methods at known instances reduce to
the instance's code. A dictionary-abstracted function called at known
instances is **specialised** once per session (memoised by function and
dictionaries, recursion included, at most 5000 per session), as GHC's
SPECIALISE does. Machine steps fell 1.5–4x (`length (filter even (map
(*3) [1..10^5]))`: 12.2M → 3.1M).

### Snapshot and staged loading
The Prelude is **never compiled at startup** by the binary or the compact
build. `tools/snapshot.rb` (run by `tools/bundle.rb`, so on every build)
compiles it through the whole pipeline and encodes the session state: name
tables, type environment, class and instance tables, unfoldings and the
machine code. `test/unit/snapshot_test.rb` checks that a snapshot session
and a session compiled from source give the same results.
- **Format** (documented in `lib/rhci/snapshot.rb`): text records in
  chunks of 256, each chunk split into records only when one of them is
  first needed. Arrays of integers that only one place refers to (most
  code operands) are written inline in their parent's record.
- **Tables are `LazyTable`s** (`lib/rhci/lazy_table.rb`) whose entries are
  decoded one at a time. `LazyTable` is deliberately not a Hash: a method
  it doesn't define fails loudly instead of seeing only the loaded part.
- **Three runs of records:**
  1. **The core**, decoded at startup: the entries that a corpus of typical
     inputs (`tools/snapshot_corpus.txt`) looks up, found at build time by
     running it against a snapshot with every entry pending.
  2. **The rest of the structure**, decoded entry by entry: on a lookup
     that misses the loaded entries (a missing name can't be reported
     before the rest is checked), by an operation over a whole table
     (`:info`'s instance lists, Tab completion), or in the background.
  3. **Compiled code**, decoded per global on first use, ordered so that
     the corpus's code comes first and an input's code sits in few chunks.
- **Specialisations made ahead.** The specialisations the corpus makes
  (Prelude functions at Prelude dictionaries) are made at build time and
  shipped. Making them runs only the compiler: no top-level value is
  evaluated into the snapshot.
- **Background loading, paced by the machine itself** (the REPL only, not
  `-c`/`-x`). The session measures how long decoding the core took (P).
  While an input runs, the machine calls back every 4096 steps: after P of
  running it loads entries for about P, runs for P again, and so on until
  everything is loaded; no fixed durations, so it adapts to the hardware.
  While the REPL waits for a key, it loads in 2 ms steps between
  non-blocking input checks, so the snapshot is usually complete before
  the first Enter. Embedders opt in with `background_loading` (§6).
- Compiled code and types are shared and read-only. **CAFs (top-level
  thunks) are instantiated per session**, because evaluating one mutates
  it, and two embedded sessions must never share mutable heap.
- The binary embeds the trained snapshot. The mruby test bundle embeds one
  with every entry pending, so every mruby test also checks that lookups
  find what isn't loaded yet.

## 5. REPL surface
- An input is one of: an expression, a declaration group (functions,
  signatures, `data`, `newtype`, `type`, `class`, `instance`, fixity), a
  `let` without `in`, a `pat <- io`, or `import`.
- **`pat <- io`** runs the action and matches the pattern at once, as
  GHCi does: a failed match is an IO error (`Pattern match failure in
  interactive GHCi command`) and binds nothing; a lazy `~pat` is matched
  on use. The bound names are monomorphic: their types are defaulted,
  and a type variable left open becomes `Any` (`xs <- return []` gives
  `xs :: [Any]`, which has no Show instance).
- **Expression of type `IO t`:** run it, and print the result unless `t` is `()`.
  As in GHCi, an expression is tried as an IO action first: a monadic
  value of an ambiguous monad is run in IO, and so is a value of a bare
  type variable when each of its constraints has an IO instance without
  a class context (`printf "%d\n" 5`).
- **Any other expression** `e` becomes `rhci_itN = e`, generalised, and is
  printed with `print` at the defaulted type. When the statement
  completes, the binding becomes `it`, so `:t it` gives `Num a => a`; an
  exception while running or printing leaves the previous `it`, as in
  GHCi. With no `Show` instance this is a type error (functions, or
  `data` without `deriving Show`).
- **Commands:** `:t`/`:type`, `:i`/`:info`, `:k`/`:kind`, `:q`/`:quit`,
  `:{ … :}`, `:l`/`:load`, `:r`/`:reload`, and a minimal `:?`/`:help`,
  abbreviated as GHCi resolves them. `:info` shows a type's definition or
  a class's methods with the instances in scope, or a value's type.
- **`:load file`, with GHCi semantics:**
  - The `.hs` extension is optional and an optional `module M where`
    header is accepted.
  - The file is checked in file mode (monomorphism restriction on,
    standard defaulting).
  - Imported modules are found as `A/B.hs` relative to the session's
    directory, which is GHCi's default `-i.`. Imports are loaded
    transitively, and a cycle is an error. Within a module, a top-level
    definition and an imported name of the same name are ambiguous where
    used.
  - A successful load **discards all prompt bindings**. Then every
    top-level name of the loaded module is in scope (exports are ignored, as
    in GHCi's `*M` context), along with the exports of the modules it imports.
  - A failed load keeps the modules that compiled, with the topmost one's
    scope, as GHCi does.
  - `:reload` repeats the last `:load`. Running `main` at the prompt works,
    because it's just an `IO ()` expression.
- **Error classes:** parse, scope, type, unsupported, runtime and limit.
  The text is GHC-like but not GHC-exact, for example
  `*** Exception: Prelude.head: empty list`. Runtime exception messages
  match GHC's apart from source locations. No warnings are emitted.
- **stdin is shared** by Haskell code and the REPL, as in GHCi: a line
  read by `getLine` is not seen by the prompt, and a character `isEOF`
  looked ahead at is handed back to it. `getContents` is lazy and leaves
  stdin semi-closed (later reads fail as in GHC), closed once the String
  reaches its end. Buffering modes are remembered and reported (GHCi
  starts with `NoBuffering`), but output always appears in program
  order: stdout is flushed at each newline, before stderr is written and
  before stdin is read.
- **Ctrl-C** during evaluation prints `Interrupted.` and returns to the
  prompt; thunks under evaluation are reset, so they can be demanded
  again. The CLI installs the handler (the library never does):
  - CRuby: an `INT` trap calls `Session#interrupt!`, whose flag the
    machine polls every 4096 steps; a trap during a blocked stdin read
    raises into the read instead.
  - mruby: a C handler sets a flag (`Rhci::Term.take_sigint`) that the
    machine polls the same way. mruby-io retries reads interrupted by a
    signal, so the binary reads stdin itself, one byte at a time through
    `Rhci::Term.read_byte`, which returns when Ctrl-C arrives.
  Ctrl-C at the prompt abandons the line.

## 6. Deliverables

### CRuby library (embedding)
- Two forms: `lib/` (require `lib/rhci.rb`; each session compiles the
  Prelude from source, about 2.5 s) and the **compact build**,
  `build/rhci.rb` (`rake compact`, made by `tools/bundle.rb`): the same
  code, Prelude sources and trained snapshot as the mruby binary, in one
  file of about 7 MB. `require_relative 'rhci'` embeds it (a session
  starts in about 20 ms); run directly, it is the CLI. It runs unchanged
  on CRuby 2.7 through 3.4.
- Everything lives under `module Rhci`. There are **no globals, no
  core-class monkey patches, no signal traps, no `exit`**, and no writes to
  `$stdout`/`$stdin` except through the IO objects the host passes in.
- **The API** (`lib/rhci/session.rb`):
  - `Rhci::Session.new(stdout:, stdin:, stderr:, limits:, prelude:, cwd:,
    files:)`. `prelude:` is `:source`, `:snapshot` or `:auto` (the
    snapshot when one is embedded). `cwd` is where `:load` and
    `readFile`/`writeFile` resolve relative paths; `files: false` makes
    file access fail (`permission denied (file access is disabled)`), for
    hosts that must not touch the disk.
  - `session.eval(input)` writes output to `stdout` and returns a `Result`
    with a `status` (`:ok`, `:parse_error`, `:scope_error`,
    `:compile_error`, `:exception`, `:unsupported`, `:limit`,
    `:command_error`) and a `message`.
  - `session.type_of(expr)`, `session.load(paths)`, `session.reload`,
    `session.interrupt!`, `session.completions(text)`.
  - `session.background_loading = true` lets inputs load the rest of the
    snapshot as they run (off by default, so a host's step and time limits
    measure only its own inputs); `session.load_while_idle(ready)` loads
    while `ready.call` is false.
- **Sessions are independent.** Prelude code and types are shared
  read-only, and each session has its own heap (see CAFs above). A single
  session is not thread-safe.

### Limits
A host can't afford a hang or unbounded memory. `limits:` is a Hash with
optional keys:
- `:steps`, a machine step budget per top-level evaluation;
- `:stack`, a cap on frames;
- `:deadline`, a wall-clock deadline (monotonic seconds; refused as
  unsupported on a runtime without a clock);
- `:integer_bits`, the largest Integer result allowed (default 2³⁰ bits,
  set by default because the step limit does not bound the memory of one
  bignum operation: `4 ^ (2 ^ 127)` once grew a process to 85 GB).

Steps, stack and deadline are checked every 4096 machine steps, as is the
interrupt flag. When a limit is hit the input is aborted with status
`:limit`, thunks under evaluation are reset, and the session stays usable,
the same way a Ctrl-C at GHCi's prompt behaves. Apart from the integer
size, with no limits set the behaviour is GHCi's (`[1..]` prints forever).

### mruby command `rhci`
- **A static binary** is built from the mrbgem `mrbgems/rhci`. The
  generated bundle (library plus snapshot) is that gem's `mrblib`, which
  mruby's build compiles to bytecode and links in. `mrb_open()` loads it,
  and a small C `main` calls `Rhci::CLI.main`. Ruby source is never parsed
  at startup.
- **Startup.** The order is: load bytecode, put the terminal in raw mode,
  print the prompt, *then* decode the snapshot's core, while waiting for
  a key. Anything typed meanwhile waits in the tty buffer. `rhci -c
  '"Hello"'` takes about 24 ms. `rake bench` (`tools/bench_startup.rb`,
  timing with `Process.spawn` and a monotonic clock) enforces a prompt in
  under 10 ms and `rhci -c` in under 200 ms. These budgets rule out
  parsing Ruby source and compiling the Prelude at startup (compiling the
  Prelude from source takes seconds); bytecode and the snapshot are
  mandatory.
- **Line editor:** rhci's own (`lib/rhci/line_editor.rb`), because mruby
  has no readline. Emacs keys, xterm arrow/Home/End/Delete sequences,
  history (`~/.rhci_history`, the last 1000 lines), and Tab completion of
  names in scope, commands, and paths after `:load`. A line wider than the
  terminal scrolls horizontally. Both executables use it when stdin and
  stdout are a terminal; it talks to the terminal only through the shim,
  which uses io/console on CRuby and the C helpers in
  `mrbgems/rhci-native/src/term.c` (termios, window size, unbuffered
  reads, SIGINT, getenv, directory listing) on mruby. Embedding code never
  reaches it.
- **Command-line modes** (`lib/rhci/cli.rb`, shared by both executables):
  | form | meaning |
  |---|---|
  | `rhci -c EXPR [ARG…]` | **Pure evaluation.** Each ARG is itself a Haskell **expression**. The input is checked and run as `(EXPR) (ARG1) (ARG2) …`, with prompt rules (extended defaulting, no monomorphism restriction). |
  | `rhci -x EXPR [ARG…]` | **IO.** EXPR must have type `IO t` and is run. The ARGs are plain `String`s, visible only through `getArgs`, and the program parses them itself. |
  | `rhci -i …` | Combines with `-c`/`-x`: the result (after applying any ARGs) is applied to stdin as a lazy `String` (`String -> String`, or `String -> IO t` with `-x`), and output streams as it's produced. |
  - **`-c` arity and type rules.** EXPR must take exactly as many
    arguments as given: if the applied result still has a function type,
    that is an error ("the function expects more arguments than the N
    given"). Too many arguments, or arguments of the wrong type, are
    ordinary type errors. `-c` with an `IO` type is an error that points
    at `-x`, and `-x` with a non-IO type is an error that points at `-c`.
  - **Examples:**
    - `rhci -c '(+)' '3 :: Double' 10` prints `13.0`.
    - `rhci -c 'map toUpper' hello` is a scope error (`hello` is a
      variable). Write `'"hello"'`.
    - `rhci -x 'getArgs >>= mapM_ putStrLn' a b` writes `a` and `b` on
      separate lines.
  - **Output rule:** a result of type `String` is written raw with
    `putStr` (no quotes, escapes become real characters, no newline
    added), so `-c '"Hello\n"'` writes `Hello` and a newline. Any other
    type is written with `print`. For `-x`, the result of the action is
    written by the same rule unless it's `()`.
  - **Exit status:** 0 on success, 1 for an uncaught exception or a
    limit, 2 for a usage error, 3 for a parse, scope or type error, 4 for
    unsupported input.

### Performance
Speed is best effort. At 10⁶ elements, `sum [1..1000000]` takes about
1.9 s with the mruby binary and about 10 s with `bin/rhci` on CRuby (which
enables YJIT, worth about 1.7x on the loop; the library leaves that choice
to the host); GHCi takes 0.02 s. The main levers were the simplifier and
specialisation (fewer steps), the C loop (about 10M steps/s), flat
values, a segmented stack, and keeping blocks out of hot loops (mruby
allocates a Proc per block). `rake bench_runtime` measures
`bench/programs.txt`; `tools/profile.rb` (steps per function) and
`tools/dump_core.rb` (simplified Core) help find work.

## 7. Dual-runtime discipline
The rules themselves, and the measured mruby facts behind them, are in
`docs/DEVELOPMENT.md`. Structurally:
- **One source tree, one manifest.** `lib/rhci/manifest.txt` lists the
  files in load order. CRuby loads them through `lib/rhci.rb`. Because
  mruby has no `require`, `tools/bundle.rb` concatenates them into
  `mrbgems/rhci/mrblib/rhci.rb` (compiled into the binary), into
  `build/rhci.rb` (the compact CRuby build), and, together with the
  harness and unit tests, into `build/test_bundle.rb` (run by the plain
  `build/mruby/bin/mruby`).
- **`lib/rhci/shim.rb` is the only file that may branch on runtime.** It
  covers the clock, reading lines and bytes, flushing, files, the
  terminal, signals, environment variables and directory listings.
- **`tools/lint.rb`** greps every file that runs on mruby for constructs
  the lean build lacks or gets wrong (`Struct`, `Set`, `catch`/`throw`,
  `Fiber`, `format`/`sprintf`/`String#%`, `pack`, Regexp, `require`,
  blockless enumerators, `round(half:)`, `$!`, bare `raise` in a rescue,
  `strip`/`rstrip`, Ruby float printing, AST classes named like core
  classes, and more).
- The build sets `MRB_CALL_LEVEL_MAX=100000` (about 131k plain Ruby frames
  on mruby, deeper than CRuby), and `MRB_ARY_LENGTH_MAX=0` and
  `MRB_STR_LENGTH_MAX=0`. The evaluator never recurses regardless; only
  the parser, renamer and type checker recurse, and only along syntactic
  nesting.

## 8. Testing
- **A tiny in-house test framework** (`test/harness.rb`, `RT`) that works
  on both runtimes, replacing the minitest/test-unit that mruby lacks.
  `rake test` runs the lint, then the unit tests on CRuby (`test/run.rb`)
  and on `build/mruby/bin/mruby` against the bundle. The e2e tests
  (`test/e2e/`, CRuby only) spawn both executables, including a
  pseudo-terminal test of editing, completion, history and Ctrl-C.
- **Oracle** (`oracle/`, see its README): probe inputs and real GHCi 9.6.7
  goldens, regenerated in a podman container. `test/oracle.rb` and
  `test/unit/oracle_*_test.rb` replay them in fresh sessions on both
  runtimes. Values and the output printed before an exception must match
  exactly; runtime exceptions must match GHCi's message (locations
  aside); `:t` is compared up to renaming with constraints as a set;
  other errors by kind. Each input gets a step budget: rhci answers 1737
  of 1746 probes, all agreeing, and 9 (million-element computations)
  exceed the budget. Probes where rhci differs by decision (names in scope
  without an import) are listed in `oracle/known_gaps.txt`. Separate
  goldens cover `:load` (`probes_load.txt`) and file IO
  (`probes_files.txt`, CRuby, in a scratch directory).
- **Numeric suite** (`oracle/numeric/`): about 14.5k cases (Double `show`
  by bit pattern, `decodeFloat`, rounding, conversions, literals, `Int`
  edges) run through real GHC; `num_golden_test` requires an exact match
  on both runtimes.
- **`runtime_assumptions_test`** pins the runtime facts the design relies
  on (the mruby bignum fixes, no array or string length cap), and `snapshot_test` that
  snapshot and source sessions agree.
- **Differential testing against GHC** (podman and network, not part of
  `rake`), described in `test/fuzz/README.md` and
  `test/exercism/README.md`:
  - `rake fuzz`: random well-typed expressions, optionally with tagged
    `error`s that expose evaluation order, and `:t` of random
    compositions, compared with GHCi;
  - `rake fuzz_progs`: random multi-module programs run by `runghc` and by
    `:load` + `main`, optionally respelt (layout, comments, braces);
  - further `test/fuzz/run.rb` modes: GHCi sessions, defaulting in files
    versus the prompt, numbers at the edges, user data types, `read` on
    damaged text, type errors, tokens, laziness, classes, failing
    patterns, kinds, instances, equal-element choice and library breadth;
  - `rake exercism`: the exercism Haskell track's reference solutions and
    test suites on rhci and GHC.
  Every fuzzer takes `--mruby`. Each bug found is pinned by an oracle
  probe. Test runs cap their address space at 8 GB.

## History
rhci was designed up front in this document (2026-10-09) and built in
seven steps, each green on both runtimes before the next: skeleton
(manifest, shim, bundler, test framework, lint, binary, startup
benchmark); lexer, layout, parser and fixity; the machine and primitives on
hand-written Core; HM without classes; classes, deriving and the Prelude
in Haskell; the REPL surface, `:load` and the embedding API; and
performance (the simplifier and the C loop). Later additions, chosen as the
most used parts of everyday Haskell: qualified imports, Data.Map/Data.Set,
`:info`/`:kind`, Text.Printf, Data.Bits, Data.Ratio, file IO, Data.IORef,
staged snapshot loading, and kind inference. Library modules are faithful
ports of base and containers, not reimplementations.
