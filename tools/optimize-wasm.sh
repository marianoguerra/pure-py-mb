#!/bin/sh
# Shrink the playground's wasm with binaryen, if binaryen is here.
#
# `moon build --release` already strips symbols -- the name section is 46
# bytes -- and eliminates what the single export cannot reach. What it does
# not do is optimise for SIZE, and `wasm-opt -Oz` takes about a quarter off:
#
#   as built       339,769 bytes   138,030 gzipped
#   wasm-opt -Oz   261,696 bytes   109,988 gzipped
#
# The feature list is explicit and that is the whole trick. `--all-features`
# lets binaryen emit post-MVP shapes no browser accepts yet -- `exact` heap
# types from custom descriptors, and an import encoding the engine reads as
# "unknown import kind" -- and the module then fails to COMPILE rather than
# failing a test. So the list below is exactly what MoonBit's wasm-gc output
# uses, and nothing more.
#
# Optional: with no `wasm-opt` on the path this says so and leaves the module
# alone, so a local `just playground` needs nothing but MoonBit. The
# deployment installs it, which is why the page ships the smaller one.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
wasm="${1:-$root/playground/playground.wasm}"

FEATURES="--enable-gc --enable-reference-types --enable-strings \
--enable-bulk-memory --enable-tail-call --enable-nontrapping-float-to-int \
--enable-sign-ext --enable-multivalue --enable-exception-handling"

if command -v wasm-opt > /dev/null 2>&1; then
  opt="wasm-opt"
elif command -v npm > /dev/null 2>&1 && npm exec --no -- wasm-opt --version > /dev/null 2>&1; then
  opt="npm exec --no -- wasm-opt"
else
  echo "wasm-opt not found; leaving $(basename "$wasm") as built"
  echo "  install it with: npm install --no-save binaryen"
  exit 0
fi

before=$(wc -c < "$wasm")
# shellcheck disable=SC2086
$opt -Oz $FEATURES "$wasm" -o "$wasm.opt"
mv "$wasm.opt" "$wasm"
after=$(wc -c < "$wasm")
echo "wasm-opt -Oz: $before -> $after bytes ($(( (before - after) * 100 / before ))% off)"
