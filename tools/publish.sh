#!/bin/sh
# Publish the two real modules, in dependency order.
#
# This exists so that "the root module is never published" is structural
# rather than a habit: it can only address `lib` and `cli`, and `moon publish`
# at the repository root -- which would upload half a megabyte of conformance
# fixtures under the wrong name -- is not something this script can be talked
# into.
#
#   tools/publish.sh --dry-run    ask the registry, send nothing
#   tools/publish.sh              publish both
#   tools/publish.sh lib          publish one
#
# `moon publish --dry-run` reaches the registry, is told the version is fine,
# and then exits non-zero anyway: "Dry run completed successfully" in its
# output is the answer, not the exit code.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dry=""
modules="lib cli"

for arg in "$@"; do
  case "$arg" in
    --dry-run) dry="--dry-run" ;;
    lib|cli) modules="$arg" ;;
    *) echo "usage: $0 [--dry-run] [lib|cli]" >&2; exit 2 ;;
  esac
done

for m in $modules; do
  name=$(sed -n 's/^name = "\(.*\)"/\1/p' "$root/$m/moon.mod")
  version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$root/$m/moon.mod")
  echo
  echo "── $name $version ($m/)"
  # A module reports "pending" until its dependencies exist in the registry:
  # `moon publish` verifies the packaged zip against the registry, and on a
  # first release the dependency is not there yet.
  if [ -n "$dry" ]; then
    (cd "$root/$m" && moon publish --dry-run) || true
  else
    (cd "$root/$m" && moon publish)
  fi
done
