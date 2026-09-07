#!/bin/sh
# The layering of `implementation-plan.md` §2, as a gate.
#
# Three claims, each of which erodes quietly if only written down:
#
#   1. `marianoguerra/error-report` is named by `error/`, by the CLI and by the
#      playground -- the three that RENDER -- and nowhere else. Everything below produces a `Diagnostic` --
#      this module's own type -- and ONE function, `Diagnostic::to_report`,
#      turns it into a report. That function being the only bridge is checked
#      too: a second one would make swapping the renderer a hunt.
#   2. `moonbitlang/x` (the filesystem, the process) is named by `lib/program`
#      and the CLI only. A library consumer supplies its own source tree.
#   3. `lib/ast` and `lib/write` name neither the lexer, the parser, the
#      checker nor the evaluator, so a code generator that builds trees and
#      prints them links none of them.
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
    ./lib/error|./cli/pure-py|./playground) continue ;;
  esac
  if grep -q 'error-report' "$pkg"; then
    report "$dir names error-report; only lib/error, cli/ and playground/ may"
  fi
done

# 2. moonbitlang/x
for pkg in $(find . -name moon.pkg -not -path './_build/*' -not -path './reference/*' -not -path './.mooncakes/*'); do
  dir=$(dirname "$pkg")
  case "$dir" in
    ./lib/program|./cli/pure-py) continue ;;
  esac
  if grep -q 'moonbitlang/x' "$pkg"; then
    report "$dir names moonbitlang/x; only lib/program and cli/ may"
  fi
done

# 2b. one adapter, not several
bridges=$(grep -c '@report\.' lib/error/*.mbt 2>/dev/null | awk -F: '{n += $2} END {print n+0}')
adapters=$(grep -l '@report\.' lib/error/*.mbt 2>/dev/null | grep -v '_test' | wc -l)
if [ "$adapters" -gt 1 ]; then
  report "lib/error names error-report in $adapters files; one adapter, one file"
fi
[ "$bridges" -gt 0 ] || report "lib/error/report.mbt no longer names error-report"

# 3. the tree and the printer are free of the front end and the back end
for dir in lib/ast lib/write lib/basic lib/token; do
  [ -f "$dir/moon.pkg" ] || continue
  for forbidden in lexer parser sieve check eval program; do
    if grep -q "pure-py/$forbidden\"" "$dir/moon.pkg"; then
      report "$dir names $forbidden"
    fi
  done
done

[ "$status" -eq 0 ] && echo "boundaries: ok"
exit "$status"
