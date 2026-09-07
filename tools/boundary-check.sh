#!/bin/sh
# The layering of `implementation-plan.md` §2, as a gate.
#
# Three claims, each of which erodes quietly if only written down:
#
#   1. `marianoguerra/error-report` is named by `error/` and by the CLI (which
#      renders) and nowhere else. Everything below produces a `Diagnostic` --
#      this module's own type -- and one adapter turns it into a report.
#   2. `moonbitlang/x` (the filesystem, the process) is named by `program/` and
#      the CLI only. A library consumer supplies its own source tree.
#   3. `ast/` and `write/` name neither the lexer, the parser, the checker nor
#      the evaluator, so a code generator that builds trees and prints them
#      links none of them.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
status=0

report() {
  echo "boundary: $1" >&2
  status=1
}

# 1. error-report
for pkg in $(find . -name moon.pkg -not -path './_build/*' -not -path './reference/*' -not -path './.mooncakes/*'); do
  dir=$(dirname "$pkg")
  case "$dir" in
    ./error|./cmd/pure-py) continue ;;
  esac
  if grep -q 'error-report' "$pkg"; then
    report "$dir names error-report; only error/ and cmd/pure-py may"
  fi
done

# 2. moonbitlang/x
for pkg in $(find . -name moon.pkg -not -path './_build/*' -not -path './reference/*' -not -path './.mooncakes/*'); do
  dir=$(dirname "$pkg")
  case "$dir" in
    ./program|./cmd/pure-py) continue ;;
  esac
  if grep -q 'moonbitlang/x' "$pkg"; then
    report "$dir names moonbitlang/x; only program/ and cmd/pure-py may"
  fi
done

# 3. the tree and the printer are free of the front end and the back end
for dir in ast write basic token; do
  [ -f "$dir/moon.pkg" ] || continue
  for forbidden in lexer parser sieve check eval program; do
    if grep -q "pure-py/$forbidden\"" "$dir/moon.pkg"; then
      report "$dir names $forbidden"
    fi
  done
done

[ "$status" -eq 0 ] && echo "boundaries: ok"
exit "$status"
