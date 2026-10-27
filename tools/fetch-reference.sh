#!/bin/sh
# Restore the read-only reference checkout at the pinned commit.
#
# `reference/` is gitignored. It is used for exactly three things -- as the
# source this port is written from, as the implementation the goldens under
# `test/golden/` are generated from, and as the origin of `test/conformance/`
# -- and is never a build or CI input.
#
#   tools/fetch-reference.sh            clone or update, then verify
#   tools/fetch-reference.sh --sync     also re-copy the suite into test/conformance/
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ref="$root/reference"
json="$root/tools/reference.json"

field() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$json" | head -1
}

repo=$(field repository)
commit=$(field commit)

if [ ! -d "$ref/.git" ]; then
  echo "cloning $repo into reference/"
  git clone --quiet "$repo" "$ref"
fi

git -C "$ref" fetch --quiet origin
git -C "$ref" checkout --quiet "$commit"

have=$(git -C "$ref" rev-parse HEAD)
if [ "$have" != "$commit" ]; then
  echo "reference is at $have, expected $commit" >&2
  exit 1
fi
echo "reference at $commit ($(field ref))"

if [ "${1-}" = "--sync" ]; then
  rm -rf "$root/test/conformance"
  mkdir -p "$root/test/conformance"
  # The suite is a part of the reference's package from v0.22.2, and was
  # its test/ directory before.
  suite="$ref/src/purepy/conformance-suite"
  [ -d "$suite" ] || suite="$ref/test"
  (cd "$suite" && tar --exclude=__pycache__ -cf - .) | (cd "$root/test/conformance" && tar -xf -)
  # A directory the reference's runs left holding nothing but bytecode is
  # not a test: git does not track it, and the copy above leaves it empty.
  find "$root/test/conformance" -type d -empty -delete
  echo "test/conformance synced from ${suite#"$ref"/}"
  # The mypy configuration the suite type-checks under, which the profile
  # harness asks mypy with (tools/profile-conform.py, question 4).
  cp "$ref/test/mypy.ini" "$root/test/profile/mypy.ini"
  echo "test/profile/mypy.ini synced from test/mypy.ini"
fi
