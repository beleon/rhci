#!/bin/sh
# Regenerate golden.txt from cases.txt with real GHC (podman, haskell:9.6).
set -e
cd "$(dirname "$0")"
podman run --rm -v "$PWD:/w:Z" docker.io/library/haskell:9.6 \
  sh -c 'cd /tmp && ghc -O0 -outputdir /tmp/o -o /tmp/num /w/Num.hs >/dev/null && /tmp/num < /w/cases.txt' > golden.txt
wc -l cases.txt golden.txt
