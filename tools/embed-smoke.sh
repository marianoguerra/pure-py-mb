#!/bin/sh
# A code generator builds trees with `ast`'s builders and prints them with
# `write`. Two claims about that:
#
#   1. It should pay for those two packages and nothing else -- not the
#      tokenizer, not the parser, not the checker, not the evaluator. This
#      reads the `-i` flags off the REAL compile command rather than trusting
#      `moon.pkg`, so a package pulled in transitively is caught too.
#   2. What it generates should be PurePy. The program it prints is fed back
#      through `pure-py check` and `pure-py run`, which closes the loop: the
#      builders produce trees the printer can print, the parser can read back
#      and the checker accepts.
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

embed="$root/_build/native/debug/build/marianoguerra/pure-py-dev/test/embed/embed.exe"
impl="$root/_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
if [ -x "$embed" ] && [ -x "$impl" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  "$embed" > "$tmp/main.py"
  if ! "$impl" check "$tmp/main.py" > /dev/null; then
    echo "embed-smoke: the generated program is not well-formed PurePy" >&2
    "$impl" check "$tmp/main.py" >&2
    status=1
  fi
  got=$("$impl" run "$tmp/main.py")
  if [ "$got" != "3 True" ]; then
    echo "embed-smoke: the generated program printed '$got', expected '3 True'" >&2
    status=1
  fi
fi

[ "$status" -eq 0 ] && echo "embed-smoke: ok"
exit "$status"
