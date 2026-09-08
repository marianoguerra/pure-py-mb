# Changelog

## Unreleased

### The default recursion limit is per backend

`default_max_depth` is 500 on `native` and **12** on `wasm`, `wasm-gc` and
`js`. It was 500 everywhere, and on a JavaScript engine that number was above
the ceiling it was meant to sit under -- so the guard never fired and the
engine threw first.

That failure mode is why this is a defect and not a tuning note. On a native
thread an overflow is a crash the developer sees. On a JavaScript engine it is
a `RangeError` that no MoonBit code can catch, and in a browser it takes the
tab with it -- where `a call stack deeper than 12` is an ordinary termination
that a page can render and a program can be rewritten around. Turning the
first into the second is the only thing the limit is for.

### What the ceiling actually is

Measured by recursing at increasing depths until the host's own stack went,
over a program with a small expression in each frame:

| how the evaluator is called | debug | release | release + `-Oz` |
|---|---|---|---|
| `native`, as a process | about 1050 | over 6000 | — |
| `wasm-gc` under `moon test` | about 26 | about 130 | — |
| `wasm-gc` as a bare export | about 370 | about 600 | about 780 |

The build matters. **The caller matters more,** which is the part worth
carrying away: the same `wasm-gc` module holds fourteen times as many guest
calls entered directly as it does under a test harness, because whatever is
already on the stack is stack the guest does not get.

12 is the tightest row rather than a guess at anyone's embedding -- the
configuration a consumer reaches without choosing it, `moon test --target
wasm-gc` on a debug build -- and it is under half of it, the margin the native
number already keeps. It is a floor. `docs/embedding.mbt.md` says how to
measure your own: call the module the way your application calls it, at
increasing depths, more than once per depth because the answer depends on what
is already on the stack, and take about a third.

The playground now does that and passes **250**, measured against the release
module it actually ships. It used to pass 120 against a default of 500, and
its note claimed the library's default was 2000, which stopped being true in
0.3.0.

`tools/depth-probe.mjs` is the measurement itself rather than a number in a
document that rots -- `just depth-probe` over the page's own module, or point
it at any module exporting `analyze`. It bisects, tries each depth five times
because the answer depends on what is already on the stack, and says when it
found the module's own `max_depth` instead of the engine's ceiling, which is
the mistake it is easiest to publish.

### And the engine is an axis of its own

Node is V8, so a Node figure is a Chromium figure and not a browser figure.
Over the playground's release module:

| engine | ceiling |
|---|---|
| V8 (Node 24) | 781 |
| V8 (Chromium 152, headless) | 783 |
| SpiderMonkey (Firefox 154, headless) | 1966 |

`just depth-probe-browser firefox` is that measurement and `chromium` the
other, from `tools/depth-probe-page/`: a page that bisects and a server that
collects what it found, because a headless browser has nowhere to print. It
also asks the question that decides whether a page survives -- does the module
we serve hold at its own limit and report rather than throw past it -- and for
the playground's 250 both engines say yes.

The ratio is the thing not to carry away. An embedder measuring a different
module got SpiderMonkey at a third of V8 where this one gets it at two and a
half times, same shape and same method. Which engine binds is a property of
the module, so the guide asks for a measurement rather than offering a rule.
Neither of us could reach WebKit or a phone, and the guide says so rather than
guessing.

Found by an embedder that makes PurePy the whole language of a tool call and
runs it under `moon test --target wasm-gc` -- the tightest configuration, and
not an exotic one -- and then sharpened by that same embedder sweeping a real
browser, which is what turned up the caller effect.

## 0.4.0 — 2026-09-08

### Where a run aborted

`Terminated` carries a `Site` beside the termination kind: the module the
guest was running in, and the span within it. `KeyError` was all a run could
say about a failure; now it can say `helper:2:11`.

**This is reporting, not semantics.** The specification is explicit that it
leaves the question open -- *"An implementation must agree on which kind a run
yields, though how it reports one is not prescribed"*
(`operational-semantics.tex`) -- and the termination kinds themselves are a
closed grammar with no position in them. So a `Site` never changes which
`Termination` a run yields, two runs that abort in different places still
agree on the kind, and `Termination` is byte-for-byte the type it was. That is
also why the position is beside the kind and not inside it: a `Termination`
that compared by position would no longer compare by kind, which is the one
thing the specification asks of it.

Two things it gets right that are easy to get wrong:

**The site is the innermost expression that aborted**, not the statement it
sits in. In `print(len(xs) + 1 // n)` it is the `1 // n`. Each of the six
places an expression can abort records its own span, and the first write wins
-- which is sound because `try`/`except` is not PurePy: an abort is never
caught, so the first one built is the one the run ends with.

**The module is where the code was WRITTEN, not what imported it.** A function
defined in `helper` and called from `__main__` reports `helper`. The import
stack cannot answer this -- during the call it still names the importer -- so
`LamClosure` and `DefClosure` now carry the module they were written in, and
that is what a call restores while it runs. A line number attributed to the
wrong file is worse than no line number.

A `Site` is `None` when there is no guest position to give: an abort a host
function returned before any guest expression was entered, or one from a tree
a code generator built, whose nodes have no source behind them.

The CLI prints a frame between the traceback header and the exception, which
is the file and line CPython names in its own innermost frame:

```
Traceback (most recent call last):
  File "helper.py", line 2
KeyError
```

The playground shows `line:col`, in the same shape it already shows a static
rejection. That column counts CODE POINTS: the byte columns are the reference
checker's message format, and this is not that format.

### The API this moved

| | 0.3.0 | now |
|---|---|---|
| `RunResult::Terminated` | `Terminated(Termination)` | `Terminated(Termination, Site?)` |
| `LamClosure`, `DefClosure` | `env`, and the body | and `in_module` |
| `region_bindings` | `(env, region)` | `(env, region, in_module)` |

It costs about 6% on `fib(25)`, the same call-heavy shape the async transform
was measured against, and nothing measurable on the conformance suite. That
6% is one tag test after each guest call and one more word in each closure.
An earlier cut recorded the span around `eval_expr` as a whole rather than at
the six places that abort; it reads better and cost 21%, because a step after
a recursive call in an `async` function is a continuation allocated per
expression instead of a tail call.

`Termination`, `Outcome` and `StmtResult` are untouched, so a host function
that answers `Aborts(KeyError)` is written exactly as it was. A caller that
matched `Terminated(k)` matches `Terminated(k, _)`, and one that never
constructed a closure by hand -- which is every caller that runs source --
sees nothing else.

### Fixed

`pure-py --version` said `0.2.0` in 0.3.0. It says `0.4.0`.

## 0.3.0 — 2026-09-08

### A host function may answer later

`Host::call` is `async`. A host that has to read a socket, await a promise or
ask a person no longer has to answer on the spot: it takes the continuation it
is handed, returns, and calls it when the answer arrives. The run parks
exactly where it stood -- mid-expression, inside a call, anywhere -- and
resumes on the value supplied.

**The guest cannot tell.** PurePy has no `await` and no concurrency, and
nothing in Chapter 4 changed: a call that answered a second later is a call
that answered. Suspension is a fact about the embedder's clock, not about the
semantics.

It is also not an escape from the sandbox. A parked run is not a concurrent
one -- there is one guest, it is at exactly one point, and the host holds the
only continuation. A continuation that is dropped is a run that never
finishes; there is no timeout and no cleanup, so a host that can give up on
its own work answers `Stuck` rather than walking away.

No JSPI, and no `moonbitlang/async`. This is MoonBit's own `async` effect,
which the compiler transforms for every backend, so it works the same on
`wasm`, `wasm-gc`, `js` and `native`. The test suite runs on all four.

### The API this moved

| | 0.2.0 | now |
|---|---|---|
| `Host::call` | `(String, Array[Value]) -> Outcome` | the same, `async` and `noraise` |
| `RunResult` | `Finished`, `Terminated`, `Undefined` | and `Suspended` |
| `run_with` | returns the answer | returns the answer *or* `Suspended`, and takes `done` |
| `Interp::run` and the rest of the evaluator | `fn` | `async fn` |

A host that answers immediately is written exactly as it was -- a plain
function is a valid `async` one -- and reads the answer from `run_with`'s
return value as before. A host that parks reads it from `done`, which is
called exactly once with the real answer whenever the run really ends: before
`run_with` returns when nothing suspended, and from inside the host's own
continuation when something did. An embedder that is itself asynchronous needs
neither: `Interp::run` is an `async` function and can be awaited.

`run_program` did not move. It builds its own host, that host answers no
foreign call, and so a run started through it cannot park.

### What it costs

Nothing is free, and two of these are worth stating before someone measures
them and is surprised.

**A guest call costs more machine stack.** The transform makes each one
several frames where it was one. Measured on a native thread's default 8 MB,
over a program that recurses with a small expression in each frame:

| build | 0.2.0 | now |
|---|---|---|
| debug | over 4000 guest calls | about 1050 |
| release | over 4000 | over 6000 |

So `default_max_depth` drops from **2000 to 500**. The old number is now above
the tightest ceiling rather than under half of it: a debug build would meet
the stack at about 1050 and die there, rather than reach the limit and report
`a call stack deeper than 2000`, which is the one thing the limit exists to
do. 500 restores the margin the number always had. It costs a PurePy program
half of Python's own recursion limit by default, and it is a parameter: a
caller that knows it built for release should raise it.

**Evaluation is slower**, by 1.8x on the worst shape of program -- one that
does nothing but call. `fib(25)` in PurePy, native release: 0.30 s to 0.53 s.
The conformance suite does not move, because most of its time is process
startup:

| what | 0.2.0 | now |
|---|---|---|
| `fib(25)`, native release | 0.30 s | 0.53 s |
| the `run` oracle over 136 tests | 0.4 s | 0.4 s |
| `playground.wasm` after `-Oz` | 262 KB | 279 KB |

The conformance numbers are unchanged: 983/983 across the four oracles, and
the playground's 27 examples still do what their notes say.

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
