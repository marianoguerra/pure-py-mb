#!/bin/sh
# A code generator builds trees with `ast`'s builders and prints them with
# `write`. It should pay for those two packages and nothing else -- not the
# tokenizer, not the parser, not the checker, not the evaluator.
#
# This reads the `-i` flags off the REAL compile command for `test/embed`
# rather than trusting its `moon.pkg`, so a package pulled in transitively is
# caught too.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

line=$(moon build --dry-run --target native 2>/dev/null \
       | grep 'build-package ./test/embed/' | head -1)
if [ -z "$line" ]; then
  echo "embed-smoke: no build command for test/embed" >&2
  exit 1
fi

status=0
for forbidden in lexer parser sieve analysis context check value eval program; do
  if printf '%s\n' "$line" | grep -q "pure-py/$forbidden"; then
    echo "embed-smoke: test/embed links $forbidden" >&2
    status=1
  fi
done

[ "$status" -eq 0 ] && echo "embed-smoke: ok"
exit "$status"
