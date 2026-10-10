# The exercism Haskell track as a test corpus

`ruby test/exercism/run.rb` (or `rake exercism`) runs every exercise of
[exercism/haskell](https://github.com/exercism/haskell) -- its reference
solution and its hspec test suite -- on rhci and on real GHC (the oracle's
podman image), and compares their output.

- The track is cloned into `vendor/exercism-haskell` on first use; GHC's
  results are cached in `build/exercism/.ghc` (`--ghc` reruns them).
- `shim/` is a Haskell 98 stand-in for `Test.Hspec` and
  `Test.Hspec.Runner`, so the tests run unchanged under both.
- The tests' scaffolding uses RecordWildCards (`test Case{..} = ...`); the
  runner expands `C{..}` into `C{f = f, ...}` (Haskell 98) and drops the
  extension. Every other LANGUAGE pragma is left in place, so rhci refuses
  those exercises as unsupported.
- `--mruby` runs the mruby binary instead of an in-process CRuby session.

Outcomes: `pass` (same output as GHC), `unsupported` (rhci refused
explicitly: an extension, `Float`, a module it does not implement),
`ghc_failed` (needs a package the image lacks: QuickCheck, split, vector,
...), `slow` (over two minutes), and `BUG` -- a wrong result, valid code
rejected, or an internal error.

As of 2026-10-10: 56 pass, 33 unsupported, 23 ghc_failed, 1 slow
(perfect-numbers: trial division up to 33550336), 0 bugs. The bugs it
found are fixed and pinned by oracle probes (section 42, L10).
