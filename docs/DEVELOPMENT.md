# Developing rhci

How the project is organised, the rules it follows, and the runtime facts
that shape the code. The design itself is in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Commands

```
rake            # lint, build mruby, tests on CRuby and mruby
rake test       # lint + both test runs (CRuby also runs e2e against both executables)
rake bench      # startup budgets: prompt < 10 ms, `rhci -c` < 200 ms (build/rhci/bin/rhci)
rake mruby      # rebuild build/mruby/bin/mruby and build/rhci/bin/rhci
rake compact    # build/rhci.rb: the compact CRuby build (one file, snapshot embedded)
rake bench_runtime  # runtime benchmarks, CRuby and the mruby binary
rake torture    # mruby tests with GC torture in the C loop (after machine.c changes)
rake exercism   # the exercism Haskell track vs GHC (podman, network)
rake cosmo      # release: build/rhci-cosmo/bin/rhci, one portable executable (curl, unzip)
rake musl       # release: build/rhci-musl/bin/rhci, static x86-64 Linux (podman)
rake release    # both plus the compact build, as dist/rhci, dist/rhci-linux-x86_64-musl, dist/rhci.rb
rake fuzz[1,1000,0.05]  # differential fuzzing vs GHCi (podman)
rake fuzz_progs[1,150]  # random whole programs vs runghc (podman)
bin/rhci        # CRuby launcher
```

## Release builds

`rake mruby` is the development build: dynamically linked against this
machine's glibc, so the binary needs a glibc at least as new where it
runs. Releases use two other builds of the same sources (`rake release`
makes all assets into `dist/`):

- **`rake cosmo`** (`tools/cosmo_build_config.rb`): Cosmopolitan Libc,
  with the pinned `cosmocc` toolchain fetched once into `build/cosmocc`.
  One "actually portable executable" (15 MB) for Linux, macOS, Windows,
  FreeBSD, OpenBSD and NetBSD, x86-64 and ARM64, needing no libc. Verified
  on Linux x86-64 (the e2e suite passes against it, and it evaluates 5-10%
  faster than the glibc build); the other platforms are untested so far,
  and the Windows terminal emulation is where trouble would show first. A
  known quirk: a Linux host that registers Wine for MZ-headed files runs
  it under Wine; Cosmopolitan's `--assimilate` or its `ape` loader fixes
  that.
- **`rake musl`**: a static x86-64 Linux ELF (7 MB) built in an Alpine
  container, for distros of any age; within a few percent of glibc's
  speed.

Both binaries contain a libc; `THIRD_PARTY_NOTICES` carries its licence.
Measured on 2026-10-11: prompt 3-4 ms on all three, `sum [1..1000000]`
2.07 s glibc, 2.04 s musl, 1.86 s Cosmopolitan.

`rake bench` is not part of the default task: its budgets are absolute
times (about 3 ms and 25 ms here, so with wide margins), expected to hold
on a desktop-class machine and to fail on a loaded CI runner or a slow
laptop through no fault of the code. Run it before committing anything
that touches startup: the snapshot, what the Prelude core contains,
background loading, the CLI.

## Layout

- `lib/rhci.rb` + `lib/rhci/*.rb`: the implementation. The load order is
  in `lib/rhci/manifest.txt`; adding a file means adding it there.
- `lib/rhci/shim.rb` is the only file that may branch on runtime.
- `test/harness.rb` (RT, a tiny framework), `test/unit/` (both runtimes),
  `test/e2e/` (CRuby only, spawns both executables).
- `mrbgems/rhci/`: the standalone binary (C `main` and the generated
  `mrblib`).
- `mrbgems/rhci-native/` (in both mruby builds): `src/machine.c`, the C
  evaluation loop, and `src/term.c` (terminal, SIGINT, getenv, directory
  listing for the shim). C code must keep every object it holds reachable
  or in the GC arena; see the comment at the top of machine.c.
- `tools/`: `bundle.rb`, `lint.rb`, `bench_startup.rb`, `runtime_probe.rb`.

## Scope decisions

The goal is **GHCi semantics, not GHCi's text.** Do not widen coverage;
make what is covered behave like GHCi.

- **Typed:** real Hindley–Milner inference with **type classes**
  (dictionary passing), including constructor classes — `Foldable`,
  `Functor` — so `length :: Foldable t => t a -> Int` holds. User `class`/
  `instance` declarations and `deriving` (Show, Eq, Ord, Enum, Bounded).
  GHCi defaulting rules (ExtendedDefaultRules: `()` default, so `Nothing`,
  `[]` print) and no monomorphism restriction at the prompt.
- **Lazy:** call-by-need with sharing; evaluator on an explicit work stack,
  never Ruby recursion. Output is printed incrementally, so
  `[1, 2, undefined]` prints `[1,2,` before the exception.
- **Must match exactly** (these are semantics): values and their `show`
  output — Double formatting (shortest round-trip, `5.0e-2`, `1.0e7`),
  `Int` wrapping at 64 bits vs unbounded `Integer`, `div`/`mod`/`quot`/
  `rem`, banker's `round`, Double range overshoot, char/string escapes
  (`"\955"`, `\&`), negative-number parenthesisation, record/infix show.
  Also which inputs are type errors and which evaluate, and the syntax users
  write.
- **Need not match:** error/warning wording, help text, version banners,
  type-variable names and constraint order in `:t` (compare types up to
  renaming and constraint-set equality). Error messages should be similar
  in spirit (`*** Exception: Prelude.head: empty list`). No GHC warnings
  are emitted (e.g. `-Woverlapping-patterns`).
- **No imports needed:** everything from commonly used base modules that
  does not clash with Prelude names is in scope by default (`sort`, `nub`,
  `fromMaybe`, `swap`, `toUpper`, `on`, `comparing`, …). `import` lines are
  accepted; clashing modules (e.g. `Data.Map`) stay qualified-only.
- **No GHC version pinned.** The oracle happens to run 9.6.7.
- **Two deliverables:** a CRuby *library* embedded in long-running Ruby
  programs (startup irrelevant; isolation, no global side effects, host
  limits matter) and an mruby *standalone command* built only with our own
  config. On this machine: prompt usable in < 10 ms, and `rhci -c EXPR`
  finishes in < 200 ms. `-c EXPR ARG…` applies a pure EXPR to ARGs that are
  themselves Haskell expressions (arity and types must match); `-x EXPR
  ARG…` runs an IO EXPR with ARGs as Strings via getArgs; `-i` applies the
  result to stdin (interact). String
  results print raw via putStr, other types via print.
- **Fail, don't approximate.** Anything that can't match GHCi semantics
  exactly is rejected with an explicit "unsupported" error. Runtime
  performance is best effort.
- **No 32-bit `Float`** for now (unsupported error). **`:load`/`:reload`**
  are in scope, in GHCi file mode (MR on, standard defaulting).

## The dual-runtime constraint

Running on **both CRuby and mruby** is the interesting constraint and the
one most likely to be violated by accident, because mruby silently lacks
things CRuby has:

- No RubyGems and no `require` of installed gems. Dependencies are mrbgems
  compiled into the interpreter, so the core should need none.
- A much smaller stdlib, and which parts exist depends on the mrbgems the
  binary was built with. `Set`, `StringIO`, `pp`, most of `Struct`'s
  conveniences, and large parts of `String`/`Enumerable` may be absent.
- Weaker introspection and no `ObjectSpace` to rely on.
- No stack-depth luxury: deep recursion in a lazy evaluator will hit mruby's
  limits sooner, which argues for an explicit work stack over Ruby recursion.

Write the core in the intersection, not in CRuby and then port. Keep any
runtime-specific code behind a thin shim so there is one place to look.
Test on both from the beginning — a CRuby-only test suite will let mruby
breakage accumulate invisibly.

## Toolchain

- **CRuby 3.4.11** via mise, pinned in `mise.toml`.
- **mruby 4.0.0**, built from `vendor/mruby` (a gitignored clone of tag
  4.0.0) with `mruby_build_config.rb`. That config is deliberately lean, and
  it is the contract: the core may use only the gems it lists.
  ```
  git clone --depth 1 --branch 4.0.0 https://github.com/mruby/mruby.git vendor/mruby
  MRUBY_CONFIG=$PWD/mruby_build_config.rb rake -f vendor/mruby/Rakefile -j8
  build/mruby/bin/mruby <file>
  ```
- **GHCi oracle**: `podman` image `docker.io/library/haskell:9.6`, see `oracle/`.
- `tools/runtime_probe.rb`: run it on both runtimes and diff the output to
  re-check the facts below.

### mruby facts that shape the design (measured, mruby 4.0.0 lean build)
- **`Float#to_s`/`inspect` uses `%.15g`.** It does not round-trip: `0.1+0.2`
  prints `0.3`. Double `show` must be implemented ourselves, by porting
  GHC's `floatToDigits` onto exact Integer arithmetic. Never use Ruby's
  float printing.
- **mruby's float literal parser flushes subnormals to zero.**
  `"5.0e-324".to_f` gives `0.0`. `Math.frexp`/`ldexp` and arithmetic handle
  subnormals correctly on both runtimes, so the lexer parses float literals
  itself (exact rational → correctly rounded Double).
- **Float→Integer is wrong past 2⁶³** (`1e20.floor` gives `92233720368547758080`).
  Implement `truncate`/`floor`/… via `Math.frexp` plus Integer shifts.
- **Integer is bignum** (mruby-bigint) and promotes automatically. Haskell
  `Int` must wrap explicitly: `((x + 2**63) % 2**64) - 2**63`.
- **Bignum comparisons are broken in mruby 4.0.0**: `int_equal` truncates
  a bignum receiver (`2**64 + 7 == 7` and `(2**64).zero?` are true), and
  `mrb_bint_cmp` orders a bignum holding INT64_MIN (`-(2**63)`) below the
  fixnum INT64_MIN. rhci-native replaces `==`, `<=>`, `<`, `<=`, `>`, `>=`
  on Integer (`src/bigint_eq.c`); `runtime_assumptions_test` pins it.
- **Bignum arithmetic with a fixnum operand is broken in mruby 4.0.0**
  too: `-18446744073709551614 + -9` is positive (a carry that grows a limb
  sets the sign), `~` of a positive bignum is off by two, a negative
  bignum `& 92` ANDs the magnitude, and `>>` of a negative bignum
  truncates. rhci-native (`src/bigint_ops.c`) replaces `+ - & | ^ ~ >> <<`
  for bignum operands; mruby and CRuby then agree on 20 000 random pairs.
- **`String#to_i` on mruby** reads a string that starts with
  `-9223372036854775808` and goes on (`"-92233720368547758080"`) as
  INT64_MIN. The lexer parses digits itself; the snapshot encoder refuses
  such an integer (its decoder uses `to_i`).
- Ruby's `/` and `%` on Integers already match Haskell `div`/`mod`
  (`Num` computes `quot`/`rem` itself: mruby's `Integer#remainder` hangs
  on some bignums). Banker's rounding is not built in:
  `round(half: :even)` fails on mruby.
- **UTF-8 works**: `length`, `[]`, `codepoints`, and `String#<<(Integer)`
  for code point → char. Missing: `Integer#chr` beyond ASCII, `Array#pack`,
  `force_encoding`.
- **Array length is capped at 131072 by default** (and String length at
  1 MB outside Linux/macOS). Our build sets `MRB_ARY_LENGTH_MAX=0` and
  `MRB_STR_LENGTH_MAX=0`; `runtime_assumptions_test` pins this.
- **Constant lookup differs:** inside a class that `include`s a module,
  mruby resolves a name like `Range` to the *core* class before the
  included module's constant (CRuby does the opposite). Never give AST or
  other included-module classes core-class names; the lint checks this.
- **`$!` is nil inside a `rescue` modifier** on mruby. Use `begin/rescue
  => e` (or `RT.error_kind` in tests).
- **No Regexp at all** in the lean build (`=~`, `match`, `sub(/…/)`).
- **Every block allocates a Proc** on mruby (and bumps a 16-bit irep
  refcount). Hot loops use `while`, never `map`/`each` with a block.
- **CRuby's `Math.sqrt(-0.0)` is `0.0`** (mruby's and IEEE's: `-0.0`);
  `p_doubleSqrt` returns a zero argument as it is.
- **`inject(sym) { ... }` on mruby** treats a Symbol initial value as an
  operator name even with a block (`[:x].inject(:star) { ... }` reduces
  with `star`); start a fold from a Symbol with a loop.
- **`NaN == NaN` is true on mruby** (an identity shortcut), and
  `NaN <=> NaN` is 0. Use `Float#nan?`, `Num.double_eq`, and ordered
  comparisons (`<`, `<=`), which are reliable.
- **A bare `raise` in a `rescue` does not re-raise** on mruby (it raises an
  empty RuntimeError); use `rescue => e` and `raise e`. The lint checks this.
- **`String#rstrip`/`strip` leave trailing whitespace on non-ASCII
  strings** on mruby. Use `Rhci::Text`; the lint checks this.
- **A huge Array that is written constantly is re-scanned whole** by
  mruby's incremental GC, which made deep evaluation quadratic. The
  machine's stack is therefore segmented (`VM::FrameStack`).
- **Missing:** `sprintf`/`format`/`String#%`, `Struct`, `Set`,
  `catch`/`throw`, `Fiber`, blockless enumerators (`each_char` without a
  block raises), `Proc#curry`, `clamp`, `instance_variable_get`, `ObjectSpace`.
- **mruby-io retries a read interrupted by a signal**, so Ctrl-C could not
  end a blocked `getLine`. The binary reads its stdin through
  `Rhci::Term.read_byte` instead (unbuffered; returns on SIGINT), and must
  use it for every stdin read so no bytes sit in mruby-io's buffer.
- **No `ENV` and no `Dir`** in the lean build: `Rhci::Term.getenv` and
  `Rhci::Term.entries` stand in.
- **Call depth:** stock mruby allows about 508 nested Ruby calls, and about
  100–170 when they go through blocks. Our build sets
  `MRB_CALL_LEVEL_MAX=100000`, giving about 131k plain and 26k–44k through
  blocks; CRuby allows about 10k and 3.7k. The evaluator runs on an
  explicit stack. The parser and type checker may recurse only along
  syntactic nesting, never along input length.

## Testing

`rake` runs the lint (constructs mruby lacks), the unit and end-to-end tests
on CRuby, the same unit tests on mruby, and the startup benchmarks. Beyond
that, rhci is tested differentially against real GHC; the details and what
each fuzzer found are in [test/fuzz/README.md](../test/fuzz/README.md) and
[oracle/README.md](../oracle/README.md).

- **Oracle:** rhci answers 1737 of 1746 GHCi probes, all agreeing; 9 exceed
  the oracle's step budget (million-element computations). The 79 file IO
  probes (`oracle/probes_files.txt`) run on CRuby, in a scratch directory.
  Runtime errors must match GHCi's message (locations aside) and the
  output printed before them.
- **More differential testing** (needs podman and the network; not
  part of `rake`):
  - `rake exercism` (`test/exercism/`): the exercism Haskell track's
    reference solutions and test suites on rhci and GHC: 56 pass, 33 are
    refused as unsupported, 23 need packages, 1 is too slow, no bugs.
  - `rake fuzz[seed,count,bottoms]` (`test/fuzz/`): random well-typed
    expressions, including tagged `error`s that expose evaluation order,
    compared with GHCi, and `:t` of random compositions; 24 000 so far
    agree.
  - `rake fuzz_progs[seed,count]` (`test/fuzz/progs.rb`): random whole
    programs (multi-module, data types, classes, a user State monad,
    patterns, guards, where, recursion, stdin-driven main) run by runghc
    and by `:load` + `main`; 2 100 agree.
  - `ruby test/fuzz/run.rb --sessions`: random GHCi sessions
    (redefinitions, `it`, `:{ :}`, IO statements, and in half of them
    imports along the way: aliases, import and hiding lists, the
    Prelude's); 11 200 inputs agree.
  - `ruby test/fuzz/run.rb --defaulting`: the same unannotated numeric
    definitions loaded from a file (MR, standard defaulting) and typed at
    the prompt, then printed, `:t`, and used at other types; 7 300
    inputs agree.
  - `run.rb --numbers` (Doubles from bit patterns, Ints and Integers at
    the 2^63/2^64 edges through show, Numeric, conversions, Bits, Ratio),
    `--datatypes` (random declarations with infix constructors and
    fixities, all derivable classes), `--reads` (read on damaged text),
    and `progs.rb --relayout` (programs respelt: broken lines, comments,
    tabs, explicit braces); 45 000 probes and 300 programs agree.
  - `run.rb --typeerrors` (well-typed expressions with a slip),
    `--tokens` (lexical traps, respaced), `--laziness` (infinite
    structures, lazy and bang patterns, seq), `--classes` (random class
    hierarchies, defaulting through them); 23 000 probes agree.
  - `run.rb --fail` (failing patterns in do blocks, MonadFail) and
    `--kinds` (`:k` and kind errors; `lib/rhci/kinds.rb` infers kinds,
    polymorphic as in GHC2021); 8 000 probes agree.
  - `run.rb --instances` (hand-written Prelude-class instances with
    varying minimal definitions); 5 000 probes agree.
  - `run.rb --equal` (which of equal elements Map/Set/list operations
    keep) and `--library` (the library's breadth, with tagged bottoms);
    8 000 probes agree.
  - Every fuzzer takes `--mruby` (the mruby build instead of CRuby).
  - **Memory is bounded everywhere** (a generated `4 ^ (2 ^ 127)` once grew
    a fuzz run to 85 GB and took the machine down): sessions refuse an
    Integer over `limits[:integer_bits]` (default 2^30 bits) as a limit;
    the fuzz runners, `test/run.rb` and exercism cap their address space
    at 8 GB (`Process.setrlimit`, inherited by the mruby subprocesses);
    GHC containers get `--memory 8g` and GHC itself `+RTS -M6g` /
    `GHCRTS=-M6g`, so a runaway probe is a "heap overflow", not a killed
    section. Keep any new harness inside these bounds.

## Performance

A Core simplifier (`lib/rhci/simplify.rb`: inlining,
case-of-known, case merging, specialisation of dictionary-abstracted
functions) cuts machine steps 1.5–4x, and the mruby builds run the
evaluation loop in C (`mrbgems/rhci-native/src/machine.c`, a port of
`Machine#run_ruby`; keep the two in step: a test compares them). At 10⁶
elements, `sum [1..1000000]` takes 1.9 s with the mruby binary and 10 s
with `bin/rhci` on CRuby (YJIT on); GHCi takes 0.02 s. Speed is best
effort, but it is watched. `rake bench_runtime` measures
bench/programs.txt; `tools/profile.rb` (steps per function),
`tools/dump_core.rb` (simplified Core) help find work.
