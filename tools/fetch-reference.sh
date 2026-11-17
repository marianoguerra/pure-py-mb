#!/bin/sh
# Restore the read-only reference material at the pinned versions.
#
# Two directories, both gitignored and never a build or CI input:
#
#   reference/          the specification (pure-py-spec) at its pinned commit:
#                       the source this port is written from, and the origin
#                       of `test/conformance/`.
#   reference-checker/  the reference type checker and interpreter (the
#                       `purepy` wheel of isabelle-purepy, generated from the
#                       mechanisation) and the `purepy-conformance` wheel it
#                       imports, unpacked: what the goldens under
#                       `test/golden/` are generated from. Since v0.23.1 the
#                       checker is no longer in the specification's repository.
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

# The checker: two wheels, checked against their pinned digests, unpacked
# side by side so that `PYTHONPATH=reference-checker` finds both packages.
checker="$root/reference-checker"
stamp="$checker/.pinned"
want="$(field checker_wheel_sha256) $(field conformance_wheel_sha256)"
if [ "$(cat "$stamp" 2>/dev/null)" != "$want" ]; then
  rm -rf "$checker"
  mkdir -p "$checker/wheels"
  for w in checker_wheel conformance_wheel; do
    url=$(field "$w")
    file="$checker/wheels/${url##*/}"
    curl -sSfL -o "$file" "$url"
    have=$(sha256sum "$file" | cut -d' ' -f1)
    if [ "$have" != "$(field "${w}_sha256")" ]; then
      echo "$file: sha256 $have, expected $(field "${w}_sha256")" >&2
      exit 1
    fi
    (cd "$checker" && python3 -m zipfile -e "$file" .)
  done
  echo "$want" > "$stamp"
fi
echo "reference-checker at $(field checker_ref) ($(field checker_commit))"

if [ "${1-}" = "--sync" ]; then
  rm -rf "$root/test/conformance"
  mkdir -p "$root/test/conformance"
  # The suite is the `purepy-conformance` package's from v0.23.1, the
  # reference checker's package's from v0.22.2, and test/ before that.
  suite="$ref/src/purepy_conformance/conformance-suite"
  [ -d "$suite" ] || suite="$ref/src/purepy/conformance-suite"
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
