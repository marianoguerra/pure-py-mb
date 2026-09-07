# pure-py-mbt — the tasks this project is developed, tested and shipped with.
#
# `just` with no arguments lists everything, grouped. Each recipe is the real
# command, so this file is both the index of what can be done here and the
# place those commands are kept honest.
#
# Two properties decide how the recipes are split:
#
#   * The conformance suite is HERMETIC. `test/conformance/` and `test/golden/`
#     are committed, so everything in the `conform` group runs with neither the
#     `reference/` checkout nor `uv` present. Python 3 is needed, for the
#     harness itself.
#   * Regenerating a committed artifact -- the goldens, the ratchet, the
#     vendored suite -- is a deliberate act whose diff is the review. Those are
#     in `regen`, and none of them runs in CI.

impl := justfile_directory() / "_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
conform := justfile_directory() / "tools/conform.py"

# List every task, grouped.
default:
    @just --list --unsorted

# ---------------------------------------------------------------------------
# Everyday development
# ---------------------------------------------------------------------------

# Type-check everything, warnings fatal (what CI gates on).
[group('dev')]
check:
    moon check --deny-warn

# Native is the fastest backend; `test-all` is the four-backend run CI does.
#
# Run the unit tests (native).
[group('dev')]
test:
    moon test --target native

# Run the unit tests on every backend: wasm, wasm-gc, js, native.
[group('dev')]
test-all:
    moon test --target all

# Seeded random trees and values: the round trip, the builders, and `repr`.
[group('dev')]
prop:
    moon test -p marianoguerra/pure-py/test/prop --target native

# Mutate the corpus and check nothing crashes, hangs, or loses its position.
[group('gates')]
fuzz count="3000" seed="1": build
    tools/fuzz.py --count {{count}} --seed {{seed}}

# Generated programs, run against CPython. The suite's 136 `run` tests are
# programs somebody wrote; these are the ones nobody wrote. A failure is
# shrunk before it is printed, so the counterexample is a line or two.
[group('gates')]
diffrun count="300" seed="1": build
    tools/diffrun.py --count {{count}} --seed {{seed}}

# How long each stage takes. A baseline, not a gate.
[group('dev')]
bench: build
    tools/bench.sh

# The number `playground.mbt` passes as `max_depth` should be about a third of
# what this reports, and `docs/embedding.mbt.md` says why it is measured
# rather than assumed.
#
# How deep the guest can recurse before the host's stack gives out.
[group('dev')]
depth-probe:
    node tools/depth-probe.mjs

# Run one package's tests, e.g. `just test-pkg lexer`.
[group('dev')]
test-pkg pkg:
    moon test -p marianoguerra/pure-py/{{pkg}} --target native

# Accept new snapshot output (`inspect` blocks).
[group('dev')]
test-update:
    moon test --target native -u

# Format every source file.
[group('dev')]
fmt:
    moon fmt

# A diff in a `.mbti` is a public-API change and wants reviewing as one.
#
# Regenerate the committed `pkg.generated.mbti` files.
[group('dev')]
info:
    moon info

# Build the native CLI -- the binary every oracle drives.
[group('dev')]
build:
    moon build --target native

# Drop build outputs.
[group('dev')]
clean:
    moon clean

# ---------------------------------------------------------------------------
# The gates
# ---------------------------------------------------------------------------

# The layering of `implementation-plan.md` §2 erodes quietly, so it is a gate
# and not a note.
#
# Check that no package names a dependency it must not.
[group('gates')]
boundary-check:
    tools/boundary-check.sh

# A code generator that builds trees and prints them should not pay for the
# lexer, the parser, the checker or the evaluator.
#
# Check that an AST-and-printer consumer does not link the front end.
[group('gates')]
embed-smoke:
    tools/embed-smoke.sh

# Check, format, unit tests, boundaries, conformance -- run before committing.
[group('gates')]
quick: check fmt test boundary-check embed-smoke conform

# Mirrors .github/workflows/check.yml, including the `git diff --exit-code`
# steps -- which is how a stale `.mbti` or an unformatted file is caught.
#
# Everything CI enforces, in CI's order.
[group('gates')]
ci:
    moon check --deny-warn
    moon info
    git diff --exit-code
    moon fmt
    git diff --exit-code
    moon test --target all
    tools/boundary-check.sh
    moon build --target native
    tools/embed-smoke.sh
    tools/tokdiff.py --show 5
    tools/astdiff.py --show 5
    tools/unparse_check.sh
    tools/conform.py --show 5
    tools/fuzz.py --count 2000 --seed 1
    tools/diffrun.py --count 300 --seed 1
    moon build --target wasm-gc --release
    cp _build/wasm-gc/release/build/marianoguerra/pure-py-dev/playground/playground.wasm playground/
    tools/optimize-wasm.sh
    node tools/check_examples.mjs --expect

# ---------------------------------------------------------------------------
# The playground
# ---------------------------------------------------------------------------
#
# The page is the library in a browser AND a real embedder: the `host` module
# its examples import is supplied through the embedding interface, so anything
# that breaks embedding breaks the playground.

# Build the wasm-gc module, shrink it if binaryen is here, and put it beside
# the page.
[group('playground')]
playground-build:
    moon build --target wasm-gc --release
    cp {{justfile_directory()}}/_build/wasm-gc/release/build/marianoguerra/pure-py-dev/playground/playground.wasm {{justfile_directory()}}/playground/
    tools/optimize-wasm.sh

# Build it and serve the page on http://localhost:8000.
[group('playground')]
playground: playground-build
    python3 -m http.server 8000 --directory {{justfile_directory()}}/playground

# Every example, through the module the page loads. Fails if one has drifted
# from the outcome recorded beside it.
[group('playground')]
examples: playground-build
    node tools/check_examples.mjs --expect

# ---------------------------------------------------------------------------
# The conformance suite -- the project's real correctness gate
# ---------------------------------------------------------------------------
#
# Hermetic: `test/conformance/` and `test/golden/` are committed, so everything
# here runs without the reference checkout.

# Every oracle, held to the ratchet in test/conform-policy.json.
[group('conform')]
conform *args: build
    tools/tokdiff.py --show 5
    tools/astdiff.py --show 5
    tools/unparse_check.sh
    {{conform}} --show 5 {{args}}

# Our token stream against CPython's `tokenize`, over the suite and the corpus.
[group('conform')]
tokens *args: build
    tools/tokdiff.py --show 5 {{args}}

# Our parse tree against CPython's `ast`, with and without positions.
[group('conform')]
ast *args: build
    tools/astdiff.py --show 5 {{args}}

# Where our tree and CPython's part company, for one file.
[group('conform')]
ast-for file: build
    tools/astdiff.py --python --show 1 --filter {{file}}

# What the printer writes, parsed again, is the tree it was given.
[group('conform')]
unparse: build
    tools/unparse_check.sh

# The same claim, with CPython doing the reading.
[group('conform')]
unparse-python: build
    tools/unparse_python_check.py

# Where our token stream and CPython's part company, for one file.
[group('conform')]
tokens-for file: build
    tools/tokdiff.py --python --show 1 --filter {{file}}

# One oracle, with the failing tests shown -- the inner loop, not a gate.
[group('conform')]
only phase *args: build
    {{conform}} {{phase}} --no-ratchet --show 20 {{args}}

# Only the tests whose name contains PATTERN, across every oracle.
[group('conform')]
one pattern: build
    {{conform}} --no-ratchet --show 20 --filter {{pattern}}

# What our CLI says about one file, with the source annotated.
[group('conform')]
explain file: build
    -{{impl}} check {{file}} --error-format human --color always

# ---------------------------------------------------------------------------
# Regenerating committed artifacts (needs reference/; never in CI)
# ---------------------------------------------------------------------------

# Restore the read-only reference checkout at the pinned commit.
[group('regen')]
reference-fetch:
    tools/fetch-reference.sh

# Re-copy the conformance suite out of the reference checkout.
[group('regen')]
suite-sync:
    tools/fetch-reference.sh --sync

# Rewrite test/golden/{parse,check,program}.txt from the reference's answers.
# The resulting diff IS the review artifact; never edit a golden by hand.
[group('regen')]
goldens:
    tools/conform.py --reference --regen

# Move the ratchet's floors to what this build actually achieves.
[group('regen')]
ratchet: build
    tools/tokdiff.py --regen-policy --show 0
    tools/astdiff.py --regen-policy --show 0
    {{conform}} --regen-policy --show 0

# Rewrite the CPython indexes the `tokens` and `ast` oracles compare against.
[group('regen')]
indexes:
    tools/tokdiff.py --regen
    tools/astdiff.py --regen

# Rewrite the generated tables from CPython's own answers.
[group('regen')]
tables:
    tools/gen_number_cases.py
    tools/gen_string_cases.py
    tools/gen_float_cases.py
    tools/gen_value_cases.py
    tools/gen_repr_cases.py
    moon fmt

# Two modules go out; the root one never does. `tools/publish.sh` is what makes
# that structural rather than a habit -- it can only address `lib` and `cli`,
# and it walks them in dependency order.
#
# Show what would go to mooncakes, without sending it.
[group('publish')]
publish-dry: ci
    tools/publish.sh --dry-run

# A published version cannot be withdrawn, so the full gate runs first.
[group('publish')]
publish: ci
    tools/publish.sh

# For a follow-up release of one module, e.g. `just publish-one cli`.
[group('publish')]
publish-one module: ci
    tools/publish.sh {{module}}

# What each module would actually ship: the file count is the point, because
# 0.1.0 shipped 978 files and 832 of them were conformance fixtures.
[group('publish')]
package-size:
    #!/bin/sh
    set -eu
    for m in lib cli; do
      (cd "{{justfile_directory()}}/$m" && moon publish --dry-run) > /dev/null 2>&1 || true
    done
    for zip in {{justfile_directory()}}/_build/publish/*.zip; do
      [ -e "$zip" ] || continue
      printf "  %-38s %6s  %4s files\n" "$(basename "$zip")" \
        "$(du -h "$zip" | cut -f1)" "$(unzip -l "$zip" | tail -1 | awk '{print $2}')"
    done

# ---------------------------------------------------------------------------

# Prove the reference implementation passes its own suite.
[group('regen')]
reference-check:
    cd {{justfile_directory()}}/reference && uv run --locked ./test/run-all.sh --no-mypy
