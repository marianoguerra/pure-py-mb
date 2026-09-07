#!/bin/sh
# A performance baseline: how long each stage takes on the largest source in
# the tree.
#
# There is no target beyond "does not regress by 2x unnoticed". The numbers go
# in CHANGELOG.md, and a person who changes something hot runs this and
# compares. It is not a gate: a machine's numbers are its own.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
impl="$root/_build/native/debug/build/cmd/pure-py/pure-py.exe"
[ -x "$impl" ] || { echo "$impl: not built" >&2; exit 1; }

# The largest file in the tree, which is the reference's own test runner.
big=$(find "$root/test" -name '*.py' -not -path '*__pycache__*' \
      | xargs ls -S 2>/dev/null | head -1)
echo "front end, over $(basename "$big") ($(wc -l < "$big") lines), 50 runs:"
for command in tokens dump unparse; do
  start=$(date +%s%N)
  i=0
  while [ "$i" -lt 50 ]; do
    "$impl" "$command" "$big" > /dev/null 2>&1 || true
    i=$((i + 1))
  done
  end=$(date +%s%N)
  printf '  %-8s %6d ms/run\n' "$command" $(( (end - start) / 50000000 ))
done

echo
echo "the whole suite, once through each oracle:"
for phase in parse check program run; do
  start=$(date +%s%N)
  "$root/tools/conform.py" "$phase" --no-ratchet --show 0 > /dev/null 2>&1 || true
  end=$(date +%s%N)
  printf '  %-8s %6d ms\n' "$phase" $(( (end - start) / 1000000 ))
done
