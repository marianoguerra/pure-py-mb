# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## This project

A port of **PurePy** (a pure functional subset of Python 3.12) to MoonBit.
[implementation-plan.md](implementation-plan.md) is the plan; work it phase by
phase and read §7 before touching the tokenizer, the numbers, the strings, the
checker or the evaluator.

### Two oracles, and which one decides

- **The reference checker is the specification for what `parse` and `check`
  decide.** `reference/src/*.py` (pinned in `tools/reference.json`) is what
  `test/golden/{parse,check,program}.txt` was generated from, message for
  message. A disagreement is our bug until upstream is shown to be wrong.
- **CPython is the oracle for what `run` prints.** The suite's `.expected`,
  `.exception.expected` and `.output.expected` files are Python's own output.

### Rules

- **Goldens are regenerated, never edited.** `just goldens` rewrites them from
  the reference; the diff is the review artifact. Editing one by hand turns a
  disagreement into a silence.
- **`test/conform-policy.json` is a ratchet that fails from both sides.** A run
  below a floor is a regression; a run above one is an improvement nobody
  recorded. `just ratchet` moves the floors, in the commit that earned them.
- **A profile has its own oracle and its own ratchet.** `lib/profile` lets a
  caller opt in to a superset of PurePy, and the reference refuses everything
  in it -- so the reference cannot be the oracle there. Every profile feature is
  outside the specification and inside Python, so CPython is: `test/profile/`
  and `tools/profile-conform.py` ask, per file, that it is still refused under
  `core`, accepted under the profile, and prints what `python3` prints.
  `test/profile-policy.json` is a SEPARATE ratchet, so a profile can never move
  a PurePy floor. A profile may open a `not_yet` gate and never a `prohibited`
  one; `test/profile/refused/` is that claim as a corpus.
- **Three modules, one workspace.** `lib/` is `marianoguerra/pure-py`, `cli/`
  is `marianoguerra/pure-py-cli`, and the root is a development module that is
  never published: it holds the conformance suite, the goldens, the corpora,
  the tools, the docs and the playground, and reaches the other two through
  their public API only. `moon.work` makes the local directories win over the
  registry, so working on the library does not mean publishing it to test it.
  Publish with `just publish`, never `moon publish` at the root.
- **Layering is a gate,** not a note: `tools/boundary-check.sh`. `error-report`
  is named by `lib/error`, the CLI and the playground -- the three that render
  -- and nowhere else; `moonbitlang/x` by `lib/program` and the CLI only;
  `lib/ast` and `lib/write` link neither the front end nor the back end.
- **`test/conformance/` is vendored verbatim** from the reference and is never
  edited. `just suite-sync` re-copies it.
- **Positions are code points, not bytes.** CPython's `col_offset` counts UTF-8
  bytes and the `tokenize` module counts code points; we store code points and
  convert only when printing a message in the reference's format.
- **Ints are `BigInt` and floor-based.** MoonBit's `/` and `%` truncate;
  Python's `//` and `%` floor. `value/arith.mbt` has the one implementation.
- **Floats print through our own `repr`,** not `Double::to_string`, which
  differs from Python's layout in six ways (see the plan, §7.3).
