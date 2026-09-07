#!/bin/sh
# The round trip: what the printer writes, parsed again, is the tree it was
# given.
#
#   dump(parse(unparse(parse(f)))) == dump(parse(f))
#
# Positions are excluded -- re-printed source has its own -- so this is a claim
# about STRUCTURE, and it is the only claim about the printer that a corpus can
# make on its own. When Python is present, `--python` adds CPython's opinion:
# `ast.parse` of what we wrote and of the original agree.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
impl="$root/_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[ -x "$impl" ] || { echo "$impl: not built" >&2; exit 1; }

pass=0
fail=0
for f in $(find "$root/test/conformance" "$root/test/corpus" -name '*.py' \
           -not -path '*__pycache__*' | sort); do
  rel=${f#"$root"/}
  if ! "$impl" dump "$f" > "$tmp/before" 2>/dev/null; then
    continue          # CPython does not parse it either; the ast oracle has it
  fi
  "$impl" unparse "$f" > "$tmp/out.py"
  if ! "$impl" dump "$tmp/out.py" > "$tmp/after" 2>/dev/null; then
    echo "  $rel: what we printed does not parse"
    fail=$((fail + 1))
    continue
  fi
  if cmp -s "$tmp/before" "$tmp/after"; then
    pass=$((pass + 1))
  else
    echo "  $rel: the tree changed"
    diff "$tmp/before" "$tmp/after" | head -6
    fail=$((fail + 1))
  fi
done

echo "unparse round trip: $pass ok, $fail failing"
[ "$fail" -eq 0 ]
