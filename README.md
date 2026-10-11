<h1 align="center">rhci</h1>

<p align="center">
  <strong>A small GHCi in Ruby: a Haskell REPL with GHCi's semantics.</strong><br>
  One binary, or one Ruby file. Prompt in 3 ms, a one-liner in 25 ms.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/CRuby-2.7%20to%203.4-CC342D" alt="CRuby 2.7 to 3.4">
  <img src="https://img.shields.io/badge/mruby-4.0-CC342D" alt="mruby 4.0">
  <img src="https://img.shields.io/badge/tested%20against-GHC%209.6-5e5086" alt="Tested against GHC 9.6">
</p>

---

```
$ rhci
rhci> xs = [x * x | x <- [1 .. 10], odd x]
rhci> sum xs
165
rhci> :t foldr
foldr :: Foldable c => (a -> b -> b) -> b -> c a -> b
rhci> import qualified Data.Map as M
rhci> M.fromListWith (+) [(c, 1) | c <- "mississippi"]
fromList [('i',4),('m',1),('p',2),('s',4)]
rhci> show (0.1 + 0.2)
"0.30000000000000004"
rhci> [1, 2, undefined]
[1,2,*** Exception: Prelude.undefined
```

## Features

- **GHCi's semantics:** Hindley-Milner type inference with type classes
  (dictionary passing, constructor classes, defaulting as GHCi does it),
  lazy evaluation with sharing, and `show` output that matches GHC
  exactly, from `Double` formatting to `Int` wrap-around
- **Fails rather than guesses:** anything rhci can't do exactly as GHCi
  would is refused with an explicit `unsupported:` error
- **A real Prelude:** ported from GHC's base, plus Data.List, Data.Char,
  Data.Maybe, Control.Monad, Data.Map, Data.Set, Data.IORef, Data.Bits,
  Data.Ratio, Numeric, Text.Printf, Text.Read and file IO
- **The GHCi workflow:** `:type`, `:kind`, `:info`, `:load`/`:reload` of
  multi-module programs, `:{ ... :}` blocks, `it`, imports at the prompt, a
  line editor with history and Tab completion, Ctrl-C to interrupt
- **Scripts and one-liners:** `rhci -c EXPR` evaluates and exits, `-i`
  applies the result to standard input like `interact`, and `-r FILE`
  runs a file's `main` like `runghc`, so a `#!` line makes a Haskell file
  executable
- **Small and self-contained:** one portable executable with no
  dependencies at all (15 MB, built for Linux, macOS, Windows and the
  BSDs), a 7 MB static Linux binary, or a single Ruby file for any CRuby
  from 2.7 to 3.4; as a library it embeds in Ruby programs with limits on
  evaluation steps, stack depth, time and Integer size

## What it's for

**Trying something quickly.** What does `words` do with tabs, does this
fold terminate, what's the type of that composition. GHCi answers all of
that, but it comes with GHC, which is gigabytes to install and a
noticeable wait before the prompt, and it isn't there on the machine you
just `ssh`ed into. rhci is one file you copy, with a prompt in
milliseconds, and the answer is the one GHCi would give, down to the
formatting of the output and which inputs are type errors. Where it
can't promise that, it says so.

**Haskell scripting.** `rhci -r script.hs`, or a `#!/usr/bin/env -S rhci -r`
line at the top of the file, runs `main` with the arguments on `getArgs`,
and `-i` turns a pure function into a filter over standard input. This is
for the kind of script you'd otherwise write in a shell or Ruby, not for
long-running or compute-heavy programs: rhci is an interpreter in Ruby,
and on tight loops it's about 100 times slower than compiled GHC.

**Portability and size.** Each release is three files: a Cosmopolitan
executable that runs unchanged on Linux, macOS, Windows and the BSDs,
on x86-64 and ARM64, needing no libc; a static Linux binary for systems
of any age; and a single Ruby file for anywhere Ruby is. None of them
needs a toolchain, a package, or any file besides itself.

**Haskell as an embedded scripting language.** As a Ruby library, rhci
gives a Ruby program (or anything that embeds Ruby) a Haskell interpreter
with sessions that are isolated from each other and from the host, with
limits on evaluation steps, stack depth, time and Integer size, and with
file access that can be switched off.

## How it's built

- **Two runtimes, one source.** The same Ruby code runs on CRuby and on
  mruby. The standalone binaries are mruby with rhci compiled in, and
  their evaluation loop runs in C.
- **A real compiler pipeline, kept small.** About 23 000 lines including
  the Haskell Prelude.
- **Startup by snapshot.** The compiled Prelude ships as a build-time
  snapshot. Only what a typical input needs is decoded at startup, the
  rest loads on demand, or in the background while you type.

```
  input --> lexer + layout --> parser --> renamer --> type checker --> desugar to Core
                                                     (classes, kinds,     |
                                                      defaulting)         v
                    output <-- lazy graph-reduction machine <-- simplifier + lowering
                               (Ruby, or C in the binaries)
```

The design is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Install

Each release has three files, all self-contained (the Prelude is
embedded); copy one anywhere on your `PATH`:

| File | Runs on |
|---|---|
| `rhci` | Linux, macOS, Windows, FreeBSD, OpenBSD, NetBSD; x86-64 and ARM64. One [Cosmopolitan](https://github.com/jart/cosmopolitan) executable, no libc needed. Verified on Linux x86-64 so far; reports from the other systems are welcome |
| `rhci-linux-x86_64-musl` | Any x86-64 Linux, however old: a static binary |
| `rhci.rb` | Anything with a Ruby from 2.7 to 3.4 (`chmod +x` it, or `ruby rhci.rb`) |

The only file rhci writes is its history, `~/.rhci_history`.

### Build

Requirements: Ruby with rake (the build is tested with CRuby 3.4, pinned
in `mise.toml`), git and a C compiler. The build fetches mruby 4.0.0
itself.

```bash
rake mruby      # build/rhci/bin/rhci: a binary for this machine's glibc
                # build/rhci.rb: the compact CRuby build (also: rake compact)
rake            # lint, build, the tests on CRuby and mruby (rake bench: startup budgets)
rake release    # the three release files into dist/ (needs curl, unzip, podman)
```

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) has the details, including
how the release builds are made.

## Usage

```
rhci [FILE.hs...]                 interactive session, FILEs loaded
rhci [FILE.hs...] [-i] -c EXPR [ARG...]   apply pure EXPR to ARGs (Haskell expressions)
rhci [FILE.hs...] [-i] -x EXPR [ARG...]   run IO action EXPR; ARGs via getArgs
rhci -r FILE.hs [ARG...]          run FILE's main with ARGs, like runghc
rhci -h | --help | --version
```

```bash
$ rhci -c 'sum [1..100]'
5050
$ rhci -c 'map toUpper' '"hello"'
HELLO
$ printf 'one\ntwo\n' | rhci -i -c 'unlines . map reverse . lines'
eno
owt
$ rhci -x 'getArgs >>= print' a b
["a","b"]
$ cat hello.hs
#!/usr/bin/env -S rhci -r
import System.Environment
main :: IO ()
main = getArgs >>= putStrLn . unwords . ("hello" :)
$ ./hello.hs world
hello world
```

Strings print raw, other values print with `show`. The exit status is 0
on success, 1 for a Haskell exception, 2 for a usage error, 3 for a
parse, scope or type error, and 4 for something unsupported.

### Commands

| Command | Action |
|---|---|
| `expression` | Evaluate and print it; IO actions are run. The result is `it` |
| `x = ...`, `f x = ...`, `data`, `class`, `instance` | Define at the prompt |
| `:{` ... `:}` | A multi-line input |
| `:type EXPR` | The expression's type (`:t` works, as does any unambiguous prefix) |
| `:kind TYPE` | The type's kind |
| `:info NAME` | What a name is: its type, class, instances, fixity |
| `:load FILE...` / `:reload` | Load modules (prompt definitions are discarded) / load them again |
| `:quit` | Leave (or Ctrl-D) |
| `:?`, `:help` | List the commands |

Ctrl-C interrupts an evaluation, including a blocked `getLine`.

### As a Ruby library

```ruby
require_relative 'rhci'   # build/rhci.rb
require 'stringio'

out = StringIO.new
session = Rhci::Session.new(stdout: out, limits: { steps: 10_000_000 })

session.eval('xs = [x * x | x <- [1 .. 10]]')
session.eval('sum xs').status        # => :ok, and out.string is "385\n"
session.eval('head []').message      # => "Prelude.head: empty list"
session.eval('length [1 ..]').status # => :limit
```

Sessions are isolated from each other and from the host. Limits cover
evaluation steps, stack depth, wall-clock time and the size of Integers,
and `files: false` turns off file IO.

## What is covered

Haskell 2010 with type classes (single-parameter, including constructor
classes), `deriving` for Show, Read, Eq, Ord, Enum and Bounded, records,
modules with export and import lists, `where`/`let`/guards/`case`, list
comprehensions, `do` notation (with MonadFail), bang patterns, kind
inference with GHC2021's polymorphic kinds, and the GHCi prompt's rules:
extended defaulting, no monomorphism restriction, `it`, redefinition.

Not supported, by choice and with an explicit error: GHC extensions other
than bang patterns and polymorphic kinds (GADTs, type families, rank-n
types, multi-parameter classes, existential types, ...), 32-bit `Float`,
tuple sections, non-ASCII identifiers, `default` declarations, foreign
imports, and packages other than the base and containers modules listed
above.

## Testing against GHC

Every answer rhci gives is meant to be GHCi's, so it's tested against the
real GHC 9.6:

- **An oracle** of about 1 700 hand-written probes with GHCi's recorded
  answers, run by `rake` on both runtimes.
- **Differential fuzzing:** about twenty generators compare rhci with GHCi
  or runghc on random input: expressions with error values that expose
  evaluation order, whole multi-module programs, GHCi sessions,
  defaulting, numbers at the 64-bit edges, user data types and classes,
  damaged `read` input, deliberate type errors, lexical traps, laziness,
  kinds and the breadth of the libraries. Over 140 000 generated inputs
  and 2 800 programs agree, on CRuby and on mruby.
- **The exercism Haskell track:** its reference solutions and test suites
  run on rhci and on GHC.

[test/fuzz/README.md](test/fuzz/README.md) lists what each fuzzer covers
and what it found (quite a lot, early on), and
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) how the project is organised.

## Acknowledgements

Designed by [Leon Becker](https://blog.leonbecker.de); implementation
largely by [Claude Code](https://claude.com/claude-code). The project's
structure, scope, and design decisions are mine; most of the code itself
was produced by Claude under my direction.

## Related projects

- [**GHCi**](https://downloads.haskell.org/ghc/latest/docs/users_guide/ghci.html):
  the real thing, and the reference rhci is tested against. Use it for
  anything beyond quick checks and small scripts.
- [**Hugs**](https://www.haskell.org/hugs/): the classic small Haskell
  interpreter, no longer maintained.
- [**MicroHs**](https://github.com/augustss/MicroHs): a small Haskell
  implementation compiling to combinators, with its own REPL.

## License

rhci is MIT-licensed. See [LICENSE](LICENSE).

Parts are derived from other projects, and their licences apply to those
parts (details in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)):

| Component | Used for | License |
|---|---|---|
| GHC's base library | `prelude/Prelude.hs` (ported) | BSD-style |
| containers | `prelude/Data/Map`, `prelude/Data/Set` (ported) | BSD-3-Clause |
| Unicode Character Database | `lib/rhci/unicode_data.rb` (generated) | Unicode License v3 |
| mruby | the standalone binaries (not in this repository) | MIT |
| Cosmopolitan Libc | the portable `rhci` binary | ISC |
| musl | the `rhci-linux-x86_64-musl` binary | MIT |
