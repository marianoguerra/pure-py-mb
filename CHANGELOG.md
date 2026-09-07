# Changelog

## 0.2.0 — 2026-09-07

### Semantics

Five places where the interpreter answered something CPython does not. Every
one of them was the same mistake, and it is worth naming once: a termination
kind is *"named after the exception the same program raises under Python in
the same circumstances"* (`operational-semantics.tex`), so `Aborts(TypeError)`
is a claim about CPython. Where CPython raises nothing, the claim is false and
the honest answer is that this subset has no rule.

The arithmetic table in the specification is a `\todo` reading *"Arithmetic,
as in Python … aborts TypeError where an operand is not a number"*. The
sentence was written for `1 + "a"`, which the conformance suite tests and
which **is** a TypeError. Reading it to cover everything non-numeric is what
produced all five.

| | 0.1.0 | now | CPython |
|---|---|---|---|
| `"a" + "b"`, `[1] + [2]`, `(1,) + (2,)` | `TypeError` | `'ab'`, `[1, 2]`, `(1, 2)` | same |
| `"ab" * 3`, `[1] * 2` | `TypeError` | `'ababab'`, `[1, 1]` | same |
| `"%d" % 3` | `TypeError` | undefined | `'3'` — no formatting here |
| `True + 1`, `-False` | `TypeError` | undefined | `2`, `0` — no bool-as-int here |
| `nan < 1.0` | undefined | `False` | same |
| `4.0 % -2.0` | `0.0` | `-0.0` | same |

Concatenation and repetition are the ones that matter in practice: a subset
with no mutation rebuilds every sequence it touches, so `[x] + rest` is not a
convenience there, it is the only way to write the loop.

A bool now reaches no operator at all, which is what `True == 1` and
`True < 2` already said. Whether Python has an answer is decided by
substitution — put an integer where each bool is and ask whether the operands
become a pair this implementation has a rule for — so `True + 1` is undefined
while `True + None`, a TypeError in Python too, still aborts.

Nothing here changes an API. `pkg.generated.mbti` is untouched.

### Testing

`tools/diffrun.py` generates PurePy programs, runs them under both this
interpreter and CPython, and compares. The conformance suite's 136 `run` tests
are programs somebody wrote; these are the ones nobody wrote. Three gates
decide what counts: `pure-py check` discards what is not well formed, so the
generator can chase variety rather than correctness; `stuck` is an answer and
is skipped; everything else must match. `test/fuzzgen` builds the trees with
`moonbitlang/core/quickcheck`, and shrinks a failure — dropping statements and
simplifying expressions, with the oracle re-run on every candidate — before it
is reported, so a counterexample is a line or two rather than forty.

It found `%` on a string and the bool rule. The other three came from reading
`moon coverage analyze` over the evaluator and checking each unreached branch
against CPython.

The tool's allow list of deliberate divergences is **empty**, and that is the
result rather than the starting point: every entry it held turned out to be a
defect. `just diffrun` runs it; `ci` runs it at 300 programs.

### Fixed

`tools/gen_*.py` wrote their tables to `value/`, `lexer/` and `basic/` —
paths that stopped existing when the module split moved them under `lib/`.
`just tables` would have created orphan directories and left the real tables
untouched.

### Packaging

The library no longer ships the conformance suite. `lib/` is its own module
and is what gets published; `cli/` is a second module holding the command;
and the repository root is a development module that is never published,
holding the suite, the goldens, the corpora, the tools, the documentation and
the playground.

| | files | size |
|---|---|---|
| `marianoguerra/pure-py` 0.1.0 | 978 | 540 KB |
| `marianoguerra/pure-py` 0.2.0 | 96 | 164 KB |
| `marianoguerra/pure-py-cli` 0.2.0 | 5 | 8 KB |

This is what 0.1.0's packaging note said the fix would have to be:
`moon publish` packages a module's whole directory tree and `moon.mod` has no
way to leave part of it out, so the only way to ship a library without its
fixtures is for the library to be the module. `moon.work` makes the local
directories win over the registry, so the split costs nothing during
development.

Import paths are unchanged: `lib/`'s module is still `marianoguerra/pure-py`
and its packages are still `marianoguerra/pure-py/ast` and the rest. A
consumer of 0.1.0 upgrades by changing a version number.

The command moved out of the library and into `marianoguerra/pure-py-cli`, so
a consumer of the library no longer downloads it.

## 0.1.0 — 2026-09-07

The first release: PurePy's tokenizer, parser, sieve, checker,
printer and interpreter, with the conformance suite passing in full.

### What it does

- **Tokenizes** Python 3.12, matching CPython's `tokenize` token for token
  and column for column over 413 sources.
- **Parses** into a CPython-shaped tree, matching CPython's `ast` node for
  node and position for position over the same 413.
- **Prints** a tree back as Python that parses to the same tree, checked both
  through this parser and through CPython's.
- **Rejects** what PurePy excludes syntactically, reproducing the reference's
  message and position for every source in the suite.
- **Decides** module and program well-formedness, likewise.
- **Evaluates** modules and programs, matching CPython's output.

### Conformance

| oracle | result |
|---|---|
| tokens against CPython | 413/413 |
| trees against CPython, without positions | 413/413 |
| trees against CPython, with positions | 413/413 |
| the printer's round trip | 412/412 |
| `parse` against the reference | 392/392 |
| `check` against the reference | 392/392 |
| `check-program` against the reference | 63/63 |
| `run` against CPython | 136/136 |

### Embedding

A host supplies everything about a run that is not pure, and there are
exactly four things:

- **output**, one call per `print` while the run is going;
- **`sys.argv`**;
- **importable modules** the host defines, whose members are values;
- **calls to the functions in them**, answered by name.

Everything else is already a value: a program is a `SourceTree`, so a host
whose guest code lives in a database or a text box never touches a
filesystem. A host function is a NAME rather than a closure, which is what
lets a `Value` stay comparable, printable and free of the host's types.

The same `Host` goes to the checker and to the evaluator: the checker needs
the member names so `from store import get` resolves, and never sees the
values.

[docs/embedding.mbt.md](docs/embedding.mbt.md) is the whole surface, and its
examples are compiled and run as tests.

### Playground

<https://marianoguerra.github.io/pure-py-mb/>, built from `playground/` as one
wasm-gc module and deployed by GitHub Actions. It is a real embedder: the
`host` module its examples import is supplied by the page.
`tools/check_examples.mjs --expect` runs every example through the very module
the page loads -- after it has been shrunk, because that is the one that ships
-- and fails if one has drifted from the outcome recorded beside it.

`moon build --release` strips symbols and eliminates what the single export
cannot reach, but does not optimise for size. `tools/optimize-wasm.sh` runs
`wasm-opt -Oz` over the result, which takes about a quarter off:

| | raw | over the wire |
|---|---|---|
| as built | 340 KB | 138 KB |
| after `-Oz` | 262 KB | 110 KB |

The feature list it passes is explicit and that is the whole trick:
`--all-features` lets binaryen emit post-MVP shapes no browser accepts, and
the module then fails to compile rather than failing a test. The pass is
optional -- without binaryen the page still builds, one quarter larger.

### Decisions

Each is a judgement the specification leaves open, recorded where it is made:

- An operation the semantics leaves undefined **aborts**, with exit code 5 and
  the operation named, rather than falling back to Python's answer. Chapter 1
  allows either; aborting is what makes the suite's dynamically excluded
  bucket a checked claim.
- A module is **loaded once per run**. The spec needs no cache because loading
  is deterministic; what loading prints is not, and CPython prints once.
- **`typing` exposes `Any` alone.** Figure 2.7 of the spec also lists
  `Callable` and the reference checker does not; the reference is the oracle.
- **Arithmetic aborts `TypeError` when an operand is not a number**, which is
  the sentence in the spec's own table, so string concatenation aborts.
  Ordering has no such sentence, so a bool against an int is undefined
  instead. Nothing in the conformance suite reaches either.
- **Integers are `BigInt`** throughout, and an integer compares with a float
  exactly rather than through a conversion.
- **Strings are UTF-16 with a code-point view.** `len`, indexing, iteration
  and pattern matching all count code points, as Python does.
- **Identifier classes are approximated** by printability rather than the full
  XID tables; the conformance suite is ASCII.
- **`Constant.kind` is not recorded.** CPython sets it to `'u'` for a `u"..."`
  literal; nothing in PurePy asks, and the two literals are the same string.

### Hardening

- **Property tests** over seeded random trees: 400 generated modules survive
  being printed and read back, 200 more are accepted by the sieve, and a
  value's `repr` is source that prints the value back. A failure names the
  seed that produced it.
- **A fuzzer**, `tools/fuzz.py`, mutates the corpus and checks that nothing
  crashes, nothing hangs, and every rejection carries a position. It found one
  defect: a comment that runs to the end of a file with no newline after it
  crashed the tokenizer, and CPython emits a synthetic empty `NL` there.
- **Nesting is bounded.** Four thousand nested brackets used to be a
  segmentation fault and are now a syntax error; an unbounded recursion used
  to be one and is now an undefined operation. The parser's limit is 500
  levels and the evaluator's call stack is 2000 deep by default, twice
  Python's own. The evaluator's is a parameter rather than a constant: the
  ceiling belongs to the host, and a JavaScript engine's stack holds far
  fewer frames than a native thread's.

### Performance

A baseline, not a target, from `tools/bench.sh` on one developer machine.
The claim is only that nothing regresses by 2x unnoticed.

| what | time |
|---|---|
| `tokens` over a 366-line file | 19 ms |
| `dump` over the same | 16 ms |
| `unparse` over the same | 14 ms |
| the `parse` oracle over 392 sources | 0.7 s |
| the `check` oracle over 392 sources | 0.7 s |
| the `program` oracle over 63 directories | 0.2 s |
| the `run` oracle over 136 tests | 0.4 s |

Most of each oracle's time is process startup: the harness runs the binary
once per test, which is what the conformance suite specifies.

### Packaging

The published module carries its conformance suite: 832 of its 978 files are
test fixtures, about half a megabyte. `moon.mod` has no way to leave them out
-- `exclude`, `include` and `files` are all rejected by `moon publish` -- so
the fix is to move the library under a directory with its own `moon.mod`.
That is a restructuring, and not one to do to a working tree on the eve of a
first release. **Done in the next release.**
