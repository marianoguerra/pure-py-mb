# pure-py for MoonBit: implementation plan

A port of **PurePy** (spec v0.15.1, a pure functional subset of Python 3.12) to
MoonBit: a Python tokenizer and parser producing a CPython-shaped AST, a sieve
that rejects the Python that PurePy excludes, a well-formedness checker (the
static semantics), an interpreter (the operational semantics), a printer that
turns the AST back into Python source, and a command-line tool that is the
other half of a differential harness against the reference checker and CPython.

This document is the output of the research and design phase. It is meant to
be executed phase by phase: each phase ends with a commit, and each substep has
a pass/fail criterion that a person or an agent can run.

---

## 1. Sources of truth

| what | where | pinned at |
|---|---|---|
| Specification | `PurePy-spec.pdf` v0.15.1 (`~/Downloads/PurePy-spec.pdf`; LaTeX sources in `spec/` of the repo below) | v0.15.1 |
| Reference checker | `https://github.com/pure-py/pure-py-spec`, `src/` (Python 3.12+, over the `ast` module) | commit `f850209` (2026-08-27) |
| Conformance suite | same repo, `test/` (288 tests: 240 module-level `.py`, 48 program-level directories) and `test/run-all.py` | same commit |
| Runtime oracle | CPython (the suite's `.expected` files were produced by Python; locally Python 3.14.4 passes 288/288) | Python ≥ 3.12 |
| Diagnostics library | `marianoguerra/error-report` (built in `../shrubbery/error-report`, published on mooncakes) | 0.1.0 |
| Porting references | `../shrubbery` (harness, goldens, ratchet policy, CLI layout); `connect0459/starlark` (Python-like scanner with INDENT/OUTDENT, AST enums, BigInt ints, vendored test data) | local / 0.5.1 |
| AST design references | CPython `Parser/Python.asdl` (3.14 main); RustPython/PyPy follow the same ASDL | fetched 2026-09-07 |

Two facts about the spec drive the design:

1. **Well-formedness is decided on Python's AST.** The spec's abstract syntax
   (Figures 2.3–2.4) is a subset of CPython's `ast`, and the reference checker
   walks CPython nodes directly. The only place the reference departs from
   CPython's tree is that it re-tags `MatchSequence` as `PatList` or `PatTuple`
   from the source text, because the spec distinguishes list and tuple
   patterns and CPython does not.
2. **Verdicts are three-valued and staged.** A test is *semantically valid*,
   *excluded* (Python accepts, PurePy rejects: syntactically at parse, statically
   at check, or dynamically at run), or a *python-error* (both reject). The
   runner derives every assertion from the test's path, and the reference
   scripts signal the stage with exit codes: `1` prohibited form, `2` planned
   but not yet supported, `3` ill-formed module, `4` ill-formed program.

### 1.1 What the reference checker is, in one paragraph each

- `syntax.py` (462 lines): the **sieve**. Walks CPython's AST and raises
  `Prohibited` (exit 1) or `NotYetSupported(feature, issue)` (exit 2) with a
  fixed message per construct. Its message strings are the conformance
  suite's `.error.expected` for the `excluded/syntactic` bucket, so they must be
  reproduced verbatim.
- `aux.py` (349): the syntactic analyses of Annex A.1 — `statements()` groups
  consecutive `def`s into a mutual region; `assigns`, `binds`, `captures`,
  `captures_e`, `fv_e`, `fv_stmt`; plus `own_fields`, `qualified_name`,
  `find_nested_import`, `split_imports`.
- `contexts.py` (200): contexts Γ (a map from names to `Status`, `ModuleStub`,
  `ModuleLoaded` or `ClassEntry`), result types `Returns | Assigns Δ`, the
  operators ⊗ (override), ⊕ (merge) and ⊲ (extend), `fields`, `ancestors`,
  `field_map`, and the predefined modules table.
- `reasons.py` (314): 31 ill-formedness reasons, each with its message. These
  are the `.error.expected` strings of the `static` buckets.
- `statements.py` (388) and `patterns.py` (130): Figures 3.1–3.4 — result
  types, sequencing with the captured-then-reassigned check, mutual regions,
  expressions with constructor arity, comprehensions, pattern well-formedness,
  linearity and subsumption.
- `check_module.py` (250) and `check_program.py` (156): Figures 3.5–3.7 —
  import prefixes, `loads-as`, submodule stubs, signatures, cycle detection
  (exit 4 `import cycle: a -> b -> a`), and program discovery from a source tree.

The interpreter has **no reference implementation**; Chapter 4 and Annex A.3
are the specification and CPython's output is the oracle, with two TODOs in the
spec (ordering and arithmetic are "as in Python") that this port fills in from
Python's behaviour.

### 1.2 Verified MoonBit facts (moon 0.1.20260827)

Checked in a scratch module before writing this plan, because each one changes
a design decision:

- `Double::to_string` gives shortest round-trip digits but not Python's layout:
  `1` for `1.0`, `10000000000000000` for `1e16`, `Infinity`, `NaN`, `0` for
  `-0.0`, `2.5e-7` for `2.5e-07`, `0.00001` for `1e-05`. Python's `repr` must be
  laid out from the digits, exactly as `../shrubbery/lib/write/racket_write.mbt`
  does for Racket. (§7.3)
- `BigInt` (core) has `/` and `%` **truncating** toward zero, `pow`, `from_string`,
  `to_string`, comparisons, but **no `to_double`**. Python's `//` and `%` are
  floor-based; int→float conversion goes through `to_string` + `parse_double`
  (correctly rounded, same as Python). `Int64 / Int64` truncates too. (§7.2)
- `moonbitlang/x/fs` 0.5.1 offers `read_file_to_string`, `read_dir`, `is_dir`,
  `is_file`, `path_exists`; `moonbitlang/x/sys` offers `exit`; `moonbitlang/core/env`
  offers `args()`. Enough for the CLI and program discovery.
- `moon build --target native` works on this machine; the CLI is a native binary
  for the harness, as in shrubbery.
- MoonBit `String` is UTF-16; Python strings are sequences of code points.
  `len`, indexing, iteration and `in` on strings must be implemented over code
  points. (§7.4)
- `moon.pkg` supports `"pre-build"` with `:embed --text` (used by the Starlark port
  to vendor test files into `.mbt`), should we want in-process corpus tests.

---

## 2. Architecture

One module, `marianoguerra/pure-py`, packages per directory, root package as a
façade. Layering is strict and gated by `tools/boundary-check.sh` (§8, Phase 0):
nothing below `error` names `error-report` except one function, and the AST
plus printer link neither the lexer nor the parser nor the evaluator.

```
basic      Pos, Span                                             (no deps)
error      Diagnostic, Stage/exit codes, Reason catalogue,       basic, error-report (one fn)
           the single adapter to error-report
token      Token, TokenKind                                      basic
lexer      Python 3.12 tokenizer: NEWLINE/INDENT/DEDENT,         token, error
           strings, numbers, f-string/bytes tagging
ast        The CPython-shaped AST (§3), dump, walk               basic, bigint
parser     Recursive-descent Python parser → ast                 lexer, ast, error
write      AST → Python source (unparse)                         ast
sieve      Port of syntax.py: Prohibited / NotYetSupported       ast, error
analysis   Port of aux.py: mutual regions, assigns/binds/        ast
           captures/fv, qualified names
context    Port of contexts.py: Γ, entries, ⊗ ⊕ ⊲, ResultType,   ast
           fields/ancestors/field_map, predefined table
check      Port of statements.py, patterns.py, check_module.py,  ast, analysis, context, error
           check_program.py: module and program well-formedness
value      Runtime values, environments, Python str/repr,        bigint, immut/hashmap
           arithmetic, eq/contains/elems/iter/getitem (A.3)
eval       Operational semantics: patterns, statements,          ast, value, analysis, context, error
           expressions, imports, loading, primitives
program    Source-tree discovery shared by check and eval        x/fs (the only fs user besides cli)
.          façade: parse, check, run in one call                 all of the above
cmd/pure-py  the CLI: tokens, dump, unparse, parse, check,       façade, x/fs, x/sys, env, error-report/render
           check-program, run
test/      corpora, goldens, policy, embed-smoke package
tools/     conform.py, tokdiff.py, astdiff.py, pyast_dump.py, pytokens.py,
           fetch-reference.sh, boundary-check.sh, embed-smoke.sh, reference.json
```

`program` exists so that `check` and `eval` share one discovery procedure
(`check_program.py`'s `is_module`/`source_tree`/`discover`) but neither of them
links the filesystem directly: `program` produces a `SourceTree` value (a map
from module name to source text or "namespace package"), and the checker and
evaluator take that value. A test can build a `SourceTree` in memory.

### 2.1 The CLI and its exit codes

`pure-py <command> [options] FILE...`, mirroring the reference scripts so the
harness can swap one for the other:

| command | output | exit |
|---|---|---|
| `tokens FILE` | one token per line: `line:col-line:col KIND text` (§8 Phase 1 format) | 0, or 1 on a lexical error with `!error line:col: msg` |
| `dump FILE [--pos]` | canonical AST dump (§3.4) | 0 / 1 |
| `unparse FILE` | Python source regenerated from the AST | 0 / 1 |
| `parse FILE...` | `FILE: ok` or `FILE:line:col: msg` (the sieve) | 0 ok, 1 prohibited, 2 not yet supported, 1 on a Python syntax error |
| `check FILE...` | `FILE: ok` or `FILE:line:col: msg` (module well-formedness; the sieve runs first) | 0, 1, 2, 3 ill-formed |
| `check-program MAIN` | `MAIN: ok` or the reference's message | 0, 1, 2, 3, 4 ill-formed program |
| `run MAIN [ARGS...]` | the program's stdout; on abort, `Kind` or `Kind: msg` on stderr | 0 normal or `SystemExit(n)`'s `n`; 1 for other aborts; 5 stuck |
| `check --error-format human|short|json --color auto|always|never` | human: `error-report` rendering with source | as `check` |

Exit code 5, **stuck**, is this implementation's own: the run reached an
operation the semantics leaves undefined (§1 of the spec allows either
aborting or producing Python's result; we abort, so that the `excluded/dynamic`
bucket is *checked* rather than merely tolerated). The message names the
operation: `stuck: == between int and str`, `stuck: if condition is not a bool`.

`run` passes `[MAIN, ARGS...]` as `sys.argv`, so `argv[0]` is the path as given,
like Python.

### 2.2 Oracles

Every oracle is hermetic: its expected answers are committed under
`test/golden/` and regenerated only by an explicit `just goldens` that needs the
reference checkout and Python. CI needs Python 3 for the harness scripts but
neither `uv` nor the reference repository.

| oracle | our side | reference side | golden | compares |
|---|---|---|---|---|
| `tokens` | `pure-py tokens` | `tools/pytokens.py` over `tokenize` | `test/golden/tokens.index` (sha1 per file) | kind, text, start/end line:col of every non-trivia token; encoding cookie and `\f` cases excluded |
| `ast` | `pure-py dump` | `tools/pyast_dump.py` over `ast.parse` | `test/golden/ast.index` | the canonical dump, with and without positions |
| `unparse` | `pure-py unparse` then `pure-py dump` | our own `dump` of the original | none (fixed point) | tree equality after a round trip; and CPython `ast.dump(ast.parse(unparsed))` equals `ast.dump(ast.parse(original))` when Python is present (`just unparse-check`) |
| `parse` | `pure-py parse` | `src/syntax.py` | `test/golden/parse.txt` (one line per file: exit, message) | exit code, `line:col`, message |
| `check` | `pure-py check` | `src/check_module.py` | `test/golden/check.txt` | exit code, `line:col`, message |
| `program` | `pure-py check-program` | `src/check_program.py` | `test/golden/program.txt` | exit code, message |
| `run` | `pure-py run` | CPython (already in the suite as `.expected`, `.exception.expected`, `.output.expected`, `expected`, `expected_exit`) | the suite's own files | stdout byte-exact; abort kind substring on stderr; exit code |
| `conform` | all of the above, driven by verdict directory as `run-all.py` does | `run-all.py`'s logic | — | 288 pass/fail lines and a summary |

`test/conform-policy.json` is a **ratchet** per bucket, as in shrubbery: a
floor that fails from both sides, so an improvement is recorded in the commit
that made it.

---

## 3. The AST

Package `ast`. One tree for everything: the parser produces it, the sieve
validates it, the checker and evaluator consume it, `write` prints it, and a
code generator builds it. It follows `Python.asdl` node-for-node for the
constructs PurePy needs to *name* (to accept, or to reject with the right
message), and is typed rather than stringly: operators, contexts and pattern
kinds are enums.

Deviations from CPython, each deliberate:

- **`MatchSequence` carries its bracket kind.** `SeqKind::List | Tuple`, because
  the spec distinguishes `[p]` from `(p)` and the reference recovers it from
  the source. A bare `case a, b:` is `Tuple`.
- **Async is a flag,** not three extra node kinds: `FunctionDef{is_async}`,
  `For{is_async}`, `With{is_async}`. The sieve's message is the same either way.
- **`Constant` is a typed enum,** not a Python object: `Int(BigInt) | Float(Double) | Complex(Double) | Str(String) | Bytes(Bytes) | Bool(Bool) | None | Ellipsis`.
  `Complex` and `Bytes` exist so the sieve can say "complex literals prohibited".
- **f-strings are `JoinedStr(raw~ : String)`** with the parts left unparsed
  (the sieve rejects them as not-yet-supported #55; a future phase parses them).
- **Positions are a `Span`** of two `Pos {line, col, offset}` where `col` counts
  code points from 0 (CPython's `col_offset` counts UTF-8 bytes; `Pos::byte_col`
  converts using the source when a message needs it).
- **No `type_comment`, `type_ignores`, `type_params`, `TemplateStr`, `Interpolation`.**
  Out of scope for 3.12 PurePy; the parser rejects `type` statements and PEP 695
  syntax as a Python syntax error.
- **`Dict` keys are `Expr?`** as in ASDL (a `None` key is `**e` unpacking), so
  the sieve can name it.

### 3.1 Definitions (normative for the port)

```moonbit
///| A node's extent in the source.
pub(all) struct Span { start : Pos; end : Pos } derive(Eq)

pub(all) struct Module { body : Array[Stmt]; span : Span }

pub(all) enum Stmt {
  FunctionDef(name~ : String, args~ : Arguments, body~ : Array[Stmt],
              decorators~ : Array[Expr], returns~ : Expr?, is_async~ : Bool, span~ : Span)
  ClassDef(name~ : String, bases~ : Array[Expr], keywords~ : Array[Keyword],
           body~ : Array[Stmt], decorators~ : Array[Expr], span~ : Span)
  Return(value~ : Expr?, span~ : Span)
  Delete(targets~ : Array[Expr], span~ : Span)
  Assign(targets~ : Array[Expr], value~ : Expr, span~ : Span)
  AugAssign(target~ : Expr, op~ : Operator, value~ : Expr, span~ : Span)
  AnnAssign(target~ : Expr, annotation~ : Expr, value~ : Expr?, simple~ : Bool, span~ : Span)
  For(target~ : Expr, iter~ : Expr, body~ : Array[Stmt], orelse~ : Array[Stmt], is_async~ : Bool, span~ : Span)
  While(test~ : Expr, body~ : Array[Stmt], orelse~ : Array[Stmt], span~ : Span)
  If(test~ : Expr, body~ : Array[Stmt], orelse~ : Array[Stmt], span~ : Span)
  With(items~ : Array[WithItem], body~ : Array[Stmt], is_async~ : Bool, span~ : Span)
  Match(subject~ : Expr, cases~ : Array[MatchCase], span~ : Span)
  Raise(exc~ : Expr?, cause~ : Expr?, span~ : Span)
  Try(body~ : Array[Stmt], handlers~ : Array[ExceptHandler], orelse~ : Array[Stmt],
      finalbody~ : Array[Stmt], is_star~ : Bool, span~ : Span)
  Assert(test~ : Expr, msg~ : Expr?, span~ : Span)
  Import(names~ : Array[Alias], span~ : Span)
  ImportFrom(module~ : String?, names~ : Array[Alias], level~ : Int, span~ : Span)
  Global(names~ : Array[String], span~ : Span)
  Nonlocal(names~ : Array[String], span~ : Span)
  Expr(value~ : Expr, span~ : Span)
  Pass(span~ : Span)
  Break(span~ : Span)
  Continue(span~ : Span)
}

pub(all) enum Expr {
  BoolOp(op~ : BoolOp, values~ : Array[Expr], span~ : Span)
  NamedExpr(target~ : Expr, value~ : Expr, span~ : Span)
  BinOp(left~ : Expr, op~ : Operator, right~ : Expr, span~ : Span)
  UnaryOp(op~ : UnaryOp, operand~ : Expr, span~ : Span)
  Lambda(args~ : Arguments, body~ : Expr, span~ : Span)
  IfExp(test~ : Expr, body~ : Expr, orelse~ : Expr, span~ : Span)
  Dict(keys~ : Array[Expr?], values~ : Array[Expr], span~ : Span)
  Set(elts~ : Array[Expr], span~ : Span)
  ListComp(elt~ : Expr, generators~ : Array[Comprehension], span~ : Span)
  SetComp(elt~ : Expr, generators~ : Array[Comprehension], span~ : Span)
  DictComp(key~ : Expr, value~ : Expr, generators~ : Array[Comprehension], span~ : Span)
  GeneratorExp(elt~ : Expr, generators~ : Array[Comprehension], span~ : Span)
  Await(value~ : Expr, span~ : Span)
  Yield(value~ : Expr?, span~ : Span)
  YieldFrom(value~ : Expr, span~ : Span)
  Compare(left~ : Expr, ops~ : Array[CmpOp], comparators~ : Array[Expr], span~ : Span)
  Call(func~ : Expr, args~ : Array[Expr], keywords~ : Array[Keyword], span~ : Span)
  JoinedStr(raw~ : String, span~ : Span)          // f-string, parts unparsed (#55)
  Constant(value~ : Constant, span~ : Span)
  Attribute(value~ : Expr, attr~ : String, ctx~ : ExprContext, span~ : Span)
  Subscript(value~ : Expr, slice~ : Expr, ctx~ : ExprContext, span~ : Span)
  Starred(value~ : Expr, ctx~ : ExprContext, span~ : Span)
  Name(id~ : String, ctx~ : ExprContext, span~ : Span)
  List(elts~ : Array[Expr], ctx~ : ExprContext, span~ : Span)
  Tuple(elts~ : Array[Expr], ctx~ : ExprContext, span~ : Span)
  Slice(lower~ : Expr?, upper~ : Expr?, step~ : Expr?, span~ : Span)
}

pub(all) enum Constant {
  Int(BigInt) ; Float(Double) ; Complex(Double) ; Str(String) ; Bytes(Bytes)
  Bool(Bool) ; None ; Ellipsis
}
pub(all) enum ExprContext { Load ; Store ; Del }
pub(all) enum BoolOp { And ; Or }
pub(all) enum Operator { Add ; Sub ; Mult ; MatMult ; Div ; Mod ; Pow ; LShift ; RShift ; BitOr ; BitXor ; BitAnd ; FloorDiv }
pub(all) enum UnaryOp { Invert ; Not ; UAdd ; USub }
pub(all) enum CmpOp { Eq ; NotEq ; Lt ; LtE ; Gt ; GtE ; Is ; IsNot ; In ; NotIn }

pub(all) struct Comprehension { target : Expr; iter : Expr; ifs : Array[Expr]; is_async : Bool }
pub(all) struct ExceptHandler { type_ : Expr?; name : String?; body : Array[Stmt]; span : Span }
pub(all) struct Arguments {
  posonlyargs : Array[Arg]; args : Array[Arg]; vararg : Arg?
  kwonlyargs : Array[Arg]; kw_defaults : Array[Expr?]; kwarg : Arg?; defaults : Array[Expr]
}
pub(all) struct Arg { arg : String; annotation : Expr?; span : Span }
pub(all) struct Keyword { arg : String?; value : Expr; span : Span }   // None = **kwargs
pub(all) struct Alias { name : String; asname : String?; span : Span }
pub(all) struct WithItem { context_expr : Expr; optional_vars : Expr? }
pub(all) struct MatchCase { pattern : Pattern; guard : Expr?; body : Array[Stmt] }

pub(all) enum SeqKind { List ; Tuple }
pub(all) enum Pattern {
  MatchValue(value~ : Expr, span~ : Span)                 // literal, -n, complex, attribute
  MatchSingleton(value~ : Constant, span~ : Span)         // None | True | False
  MatchSequence(kind~ : SeqKind, patterns~ : Array[Pattern], span~ : Span)
  MatchMapping(keys~ : Array[Expr], patterns~ : Array[Pattern], rest~ : String?, span~ : Span)
  MatchClass(cls~ : Expr, patterns~ : Array[Pattern], kwd_attrs~ : Array[String],
             kwd_patterns~ : Array[Pattern], span~ : Span)
  MatchStar(name~ : String?, span~ : Span)
  MatchAs(pattern~ : Pattern?, name~ : String?, span~ : Span)   // `_` is MatchAs(None, None)
  MatchOr(patterns~ : Array[Pattern], span~ : Span)
}
```

All types derive `Eq` and `@debug.Debug` (per `AGENTS.md`, snapshot tests use
`Debug`, not `Show`). `Stmt::span`, `Expr::span`, `Pattern::span` accessors;
`Module::walk`, `Stmt::children` for generic traversals (the sieve's
`find_nested_import`, the harness's counters).

### 3.2 Builders for code generation

`ast` exports constructors with defaults for spans (`Span::none`) so a generator
never has to invent positions: `Expr::name("x")`, `Expr::call(f, args)`,
`Expr::int(3)`, `Stmt::assign("x", e)`, `Stmt::def_("f", ["x"], body)`,
`Stmt::dataclass("P", ["x", "y"], base?)`, `Pattern::capture("x")`, and so on.
The `test/embed` package (§8 Phase 11) is a consumer that builds a tree with
them and prints it, and `tools/embed-smoke.sh` checks that doing so links
neither `lexer`, `parser`, `check` nor `eval`.

### 3.3 The PurePy grammar is a predicate, not a second tree

The reference checks well-formedness on the Python AST and asserts the sieve
already removed everything else. This port does the same: `check` and `eval`
match on the full enums and hit `abort("unreachable after sieve")` in the arms
the sieve excludes. A second, narrower "core" AST was considered and rejected:
it would double the node definitions, need a lowering pass that the reference
does not have, and make the checker harder to compare with `statements.py`
line by line. Mutual regions are grouped on the fly by `analysis::statements`,
exactly as `aux.statements` does, so the tree stays CPython's.

### 3.4 The dump format

The `ast` oracle compares text, so the format is defined once and implemented
twice (MoonBit `ast::dump`, Python `tools/pyast_dump.py`):

- S-expressions, one node per line, two-space indentation by depth.
- A node is `(Kind field=value ...)` in ASDL field order; lists are `[a b]`;
  absent optionals are `-`; identifiers bare; strings as Python `repr` (the
  Python side uses `repr`; the MoonBit side implements the same escaping,
  which `value` needs anyway for `print`); ints in decimal; floats via Python
  `repr` layout (§7.3); `Bool`/`None`/`Ellipsis` bare.
- `MatchSequence` prints as `(MatchSequence kind=List ...)`; the Python dumper
  classifies from the source segment as `syntax.py` does.
- Async flags print as `is_async=True/False`; `Try` prints `is_star`.
- With `--pos`, every node gets `@l:c-l:c` after its kind, columns in **code
  points** (the Python side converts `col_offset` bytes to code points using the
  line's text).

---

## 4. Diagnostics

Package `error`, patterned on `../shrubbery/lib/error`:

```moonbit
pub(all) enum Stage { Syntax ; Prohibited ; NotYetSupported ; IllFormedModule ; IllFormedProgram ; Abort ; Stuck }
pub(all) enum Kind {
  PythonSyntax(msg~ : String)                          // exit 1 (a `load` reports "parse error")
  Prohibited(msg~ : String)                            // exit 1, syntax.py's text verbatim
  NotYetSupported(feature~ : String, issue~ : Int)     // exit 2, "<feature> not yet supported (#N)"
  IllFormed(Reason)                                    // exit 3, reasons.py's message()
  Program(msg~ : String)                               // exit 4
  Abort(Termination)                                   // run: exit 1 or SystemExit's n
  Stuck(op~ : String)                                  // run: exit 5
}
pub(all) struct Diagnostic { kind : Kind; span : Span?; module : String?; related : Array[(Span, String)] }
pub fn Diagnostic::exit_code(Self) -> Int
pub fn Diagnostic::message(Self) -> String            // exactly the reference's text
pub fn Diagnostic::short(Self, path : String, source : Source?) -> String  // "path:line:col: msg"
pub fn Diagnostic::to_report(Self, @report.SourceId) -> @report.Report  // the ONE error-report call
pub(all) suberror PurePyError { PurePyError(Diagnostic) }
```

`Reason` is an enum with one arm per `reasons.py` class (31 of them), each
carrying the same fields, and `Reason::message` reproduces the Python
f-strings character for character; the catalogue is in Appendix B and is a
test (`error/reasons_test.mbt` snapshots every message).

`related` is our addition: a second span the reference does not record but the
human renderer wants — for `CapturedReassignment`, the statement that captured;
for `UnreachableCase`, the subsuming case; for `SubmoduleNameClash`, nothing.
`short` never prints it, so the reference comparison is unaffected.

---

## 5. Static semantics

Direct ports, file for file, function for function, so a reviewer can put
`statements.py` and `check/statements.mbt` side by side:

| Python | MoonBit | notes |
|---|---|---|
| `aux.py` | `analysis/{regions,assigns,binds,captures,fv,imports}.mbt` | `Statement = Single(Stmt) \| Region(Array[FunctionDef])`; sets are `@sorted_set.SortedSet[String]` so `min(reassigned)` is deterministic as in Python |
| `contexts.py` | `context/{entry,ops,result,classes,predefined}.mbt` | `Context = @sorted_map.SortedMap[String, Entry]` (deterministic iteration for `sorted(clash)[0]`); `Entry = Status(Bool) \| ModuleStub(q) \| ModuleLoaded(q, Context) \| Class(ClassEntry)`; `ClassEntry {context, name, own_fields, base}` |
| `patterns.py` | `check/patterns.mbt` | `subsumes`, `check_pattern`, `check_pattern_list`, `is_catch_all`, `literal_value` compared with Python semantics (`1 == 1.0` is True for `MatchValue`; `True is True` identity for singletons) |
| `statements.py` | `check/statements.mbt` | `result_type`, `check_seq` (unreachable, captured-reassignment), `check_stmt`, `check_expr` (constructor arity), comprehensions |
| `check_module.py` | `check/module.mbt` | `check_module` with a signature cache and a loading stack for cycle detection; `IllFormedProgram` for cycles; `signature`, `submods`, `imports`, `loads_as`, `check_submodule_clash` |
| `check_program.py` | `check/program.mbt` + `program/discover.mbt` | `import_targets`, `is_module`, `source_tree`, `discover`, `walk_program`; the message prefix `path: msg` for a non-main module |

Every ordering the Python relies on is reproduced: Python `set` iteration order
is *not* relied on by the reference anywhere it affects output (it uses `min`
and `sorted`), and this port uses sorted collections so that no order is
accidental.

---

## 6. Dynamic semantics

Package `value`:

```moonbit
pub(all) enum Value {
  None ; Bool(Bool) ; Int(BigInt) ; Float(Double) ; Str(String)
  List(Array[Value]) ; Tuple(Array[Value])          // never mutated after construction
  Dict(Array[(String, Value)])                      // insertion order; keys are strings (§A.3)
  Lambda(Closure)                                   // LamΓ(ρ, x⃗, e)
  Def(DefClosure)                                   // DefΓ(ρ, d⃗, i): env, region, index
  Obj(ClassEntry, Env)                              // ObjΓ(C, ρ), ρ holds every field, inherited first
  ModStub(String)                                   // Mod(q)
  Mod(String, Env)                                  // Mod(q, ρ)
  Class(ClassEntry)                                 // ClsΓ(q.c, x⃗, c′)
  Prim(Primitive)                                   // Prim(f): Print | Len | Range | Exit | Sqrt | ...
}
pub type Env = @immut/hashmap.HashMap[String, Value]  // ρ; closures capture it by value

pub(all) enum Termination {          // κ
  TypeError ; IndexError ; KeyError ; ZeroDivisionError ; AttributeError
  AssertionError(String?) ; SystemExit(Int)
}
pub(all) enum Outcome { Val(Value) ; Aborts(Termination) ; Stuck(String) }
pub(all) enum StmtResult { Assigns(Env) ; Returns(Value) ; Aborts(Termination) ; Stuck(String) }
pub(all) enum MatchResult { Match(Env) ; NoMatch ; Stuck(String) }
```

`Stuck` is threaded like `Aborts`: an undefined operation propagates out
through every rule, and `run` reports it with exit 5.

Package `eval` implements Figures 4.2–4.13 and Annex A.3 rule by rule; each
`///|` block names the rule(s) it implements (`eval-call-def`,
`eval-pat-constr`, …) so the spec and the code can be read together.
`analysis::statements` groups mutual regions before `eval-def`, and
`eval-call-def` rebinds the whole region in the callee's environment.

Module loading (`eval/load.mbt`) follows Figure 4.13 with one deliberate
difference: a **per-run module cache** keyed by module name. The spec says
loading is deterministic so no cache is needed, but a module that prints when
it loads would print twice under `import pkg.sub` twice, and CPython (the
oracle) prints once. The cache makes the two agree and changes nothing else.
Loading of ancestors before descendants, `loads-as`, and submodule stubs are as
specified.

Primitives (Figure 2.7): `print` (Python `str` of each argument, space-separated,
newline), `len` (elements or dictionary keys; `TypeError` otherwise), `range(n)`
(a list; `TypeError` on a non-int), `sys.exit()` / `sys.exit(n)`, `math.*` over
floats (ints converted; `sqrt` of a negative aborts `ValueError`, which is not a
κ — treat as stuck), and `sys.argv`, `math.pi`, `math.e`, `__name__` as values.
`typing.Any`, `typing.Callable`, `dataclasses.dataclass` are values only so that
`from typing import Any` binds something; they are never called.

`python-error/dynamic` fixes how aborts print: `AssertionError`, `TypeError`,
etc. on stderr, exit 1, after any stdout the run already produced (the harness
compares `.output.expected` too).

---

## 7. Porting notes that are easy to get wrong

Recorded now so that they end up in `AGENTS.md` and are not rediscovered.

### 7.1 Tokenizer

- **Two column notions.** CPython's `col_offset` is a UTF-8 byte offset; the
  `tokenize` module reports code-point columns. Store code points; convert to
  bytes only when printing a reference-format message.
- **INDENT/DEDENT are emitted at the first token of a logical line,** never
  inside brackets, and a comment-only or blank line produces neither NEWLINE nor
  indentation changes. Tabs advance to the next multiple of 8; Python also checks
  consistency with tab-size 1 and raises `TabError` on disagreement — implement
  both columns as CPython does (`col` and `altcol`).
- **Dedent must land on an existing indentation level** or it is
  `IndentationError: unindent does not match any outer indentation level`.
- **Backslash continuation** joins lines outside brackets; inside brackets
  newlines are whitespace (`NL` in `tokenize`, not `NEWLINE`).
- **A file that does not end in a newline still ends its last logical line.**
  Emit NEWLINE, then the closing DEDENTs, then ENDMARKER.
- **`match`, `case`, `_`, `type` are soft keywords.** The tokenizer emits NAME;
  the parser decides. `match = 1` is an assignment; `match x:` is a match.
- **Numbers**: `0x`, `0o`, `0b`, underscores between digits, leading-zero
  decimals only when all zeros (`00` ok, `01` error), floats with `.`/exponent,
  imaginary suffix `j`/`J`. Keep the lexeme; parse the value in the parser
  (BigInt for ints, `parse_double` for floats).
- **Strings**: prefixes in any case and order from `r b f u rb br fr rf`;
  `u` cannot combine. Triple quotes span lines. Escapes decoded per Python
  (`\n \t \\ \' \" \a \b \f \r \v \0oo \xhh \N{...} \uhhhh \Uhhhhhhhh`, and an
  unknown escape keeps the backslash — Python 3.12 warns, does not fail).
  Raw strings keep everything. Bytes literals must be ASCII. **Implicit
  concatenation is the parser's job**; a bytes and a str cannot mix.
- **CRLF and lone CR are newlines** in Python source; normalise at read time,
  as Python's universal newlines do, but only in the *source*, not in string
  literal values that spell `\r`.
- **A form feed** at the start of a line resets the column. Rare; handle it or
  reject it, and exclude it from the token oracle.

### 7.2 Numbers

- Python ints are unbounded: `Int(BigInt)` everywhere, no fast path in the
  first version (the suite has no large numbers; a future `Int64` fast path is
  a measurable optimisation, not a correctness change).
- `//` and `%` are floor-based with the sign of the divisor (`-7 // 2 == -4`,
  `-7 % 2 == 1`, `7 % -2 == -1`); core's `BigInt` and `Int64` truncate.
  Implement `floordiv`/`floormod` once in `value/arith.mbt`.
- `/` on ints is float division; `int ** negative int` is a float; `int ** int`
  is exact; `float // float` is `floor(a / b)` as a float; `float % float`
  follows Python's `fmod` adjustment.
- `bool` is *not* a number in PurePy: `True + 1`, `True == 1`, `not 1` are
  **stuck**, even though Python accepts them (`excluded/dynamic-semantic`).
- Comparisons `< <= > >=`: numbers with each other (int vs float via exact
  comparison, not via conversion, to match Python on large ints), strings by
  code point, lists with lists and tuples with tuples lexicographically; anything
  else is stuck. `==`/`!=`: `eq` of Annex A.3 (None compares with anything;
  otherwise same kind only; NaN rules; short-circuit order is observable).
- `ZeroDivisionError` for `/`, `//`, `%` by zero, including `0.0`.

### 7.3 Float repr

Python's `repr(float)`: shortest round-trip digits (MoonBit agrees on the
digits), positional when the decimal exponent is in `[-4, 16)`, otherwise
`d.ddde±XX` with at least two exponent digits; integral values get `.0`;
`inf`, `-inf`, `nan`, `-0.0`. Port `double_to_string` from
`../shrubbery/lib/write/racket_write.mbt` with Python's thresholds and
spellings. Tested against a committed table generated by CPython
(`test/golden/float_repr.txt`, ~200 values including subnormals, powers of ten
around the thresholds, and `0.1 + 0.2`).

### 7.4 Strings

- Python strings are code-point sequences; MoonBit's are UTF-16. `len`,
  `getitem`, `elems`, `iter`, pattern matching against a string all go through
  a code-point view. Substring `in` is on the encoded string and is correct as is.
- `str` vs `repr`: `print("a")` writes `a`; `print(["a"])` writes `['a']`.
  `repr` picks `'` unless the string contains `'` and no `"`; escapes `\\ \n \r \t`,
  other control characters as `\xNN`, and non-printable code points as
  `\xNN`/`\uNNNN`/`\UNNNNNNNN` per `str.isprintable` — implement the ASCII
  and Latin-1 cases exactly and treat every code point ≥ U+00A0 as printable,
  which is what the suite exercises; note the gap.
- Objects print as `P(x=1, y='a')` — the class's short name and every field,
  inherited first, with `repr` of each value. `print(P)` never happens (classes
  are not values).
- `print` with no arguments prints an empty line. `sep=` and `end=` are not in
  the grammar, but the sieve accepts keywords on any call and the checker
  (`statements.py`'s `check_expr`) looks at keyword *values* only for
  constructor calls — a reference quirk to reproduce, not fix. At run time a
  keyword argument on a call that is not a constructor is **stuck**.

### 7.5 Checker

- **`min` and `sorted` decide which name a message reports** when several
  qualify; use sorted sets so that `'g' captured…` names the same variable the
  reference names.
- **`ClassEntry.context` is the declaring context,** captured at declaration,
  and `fields`/`ancestors` resolve the base through *that* context, not the
  current one. `class_entry_for` builds it from `ctx.gamma` before the class
  is added.
- **`__name__ = "<q>"` is prepended to every module body** before checking and
  evaluation, and counts as an assignment for `own_members` and `binds_name`.
- **Import prefix vs body.** Imports are not statements: `find_nested_import`
  (exit 3 `import only allowed at module top level`) runs before
  `split_imports`; a stray import after a statement is `imports must precede all
  other statements`.
- **`check_module` is cached per `(program, q)` and detects cycles with a
  loading stack;** the cycle message lists names from the first repeat to `q`.
- **Predefined modules have bodies that are empty `Module`s** in the discovery
  map, and `own_members` for them is the fixed table, not the body.
- **`typing` exposes only `Any` in the reference,** while spec Figure 2.7 also
  lists `Callable`. Follow the reference (it is the oracle); record it in the
  policy file as a known divergence to revisit when upstream settles.
- **`__init__.py`-less directories are namespace packages** whose body is just
  the `__name__` assignment; `source_tree` includes every `.py` under the
  entry's directory, prefix-closed, so an unused module is still discovered
  (but not checked).

### 7.6 Evaluator

- **`eval-call-def` rebinds the whole mutual region** in the callee's
  environment (`ρ′ ⊗ {f⃗ : v⃗} ⊗ {x⃗ : u⃗}`), which is what makes `even`/`odd`
  work and what makes `mutual_after_rebind` print `0` then `1`.
- **A sequence's result environment is `ρ′ ⊗ r`**, not the whole environment:
  `eval-seq` returns only the bindings the sequence made; the caller overrides.
  `eval-match` likewise returns the pattern's bindings composed with the body's.
- **`if`/`assert`/`and`/`or`/conditional expressions require an actual `Bool`**;
  anything else is stuck (`if 5:` is `excluded/dynamic`).
- **`assert e, m` evaluates `m` only when `e` is `False`,** and `m` must be a
  string (otherwise stuck). Python's traceback shows `AssertionError: m`.
- **Dict literals with a non-string key are stuck**, dict patterns with a
  non-string key are rejected by the sieve (`dict pattern keys must be string
  literals`), and `getitem(dict, non-str)` is stuck (not `KeyError`).
- **List patterns match only lists, tuple patterns only tuples,** and the
  `no-match` rules are narrower than "anything else". `eval-pat-list-no` fires
  when `v` is *neither list nor tuple*, or a list of the wrong length; a list
  pattern against a **tuple** value is covered by no rule at all, so it is
  **stuck** (`excluded/static/pending/match_list_pat_on_tuple`: Python
  matches, PurePy has no derivation). A tuple pattern against an int is
  `no-match` (`semantically-valid/match_tuple_pat_on_int`). A literal pattern
  against a list is `eq` between unrelated kinds: stuck
  (`pending/match_int_pat_on_list`). Implement exactly that.
- **Constructor pattern on an object whose class is a *subclass* of the
  pattern's class matches,** binding the pattern class's fields only.
- **`sys.exit(n)` aborts with `SystemExit(n)`;** `run` exits with `n` and prints
  nothing. A run that completes exits 0.
- **Comprehension variables are local:** evaluate `g⃗` to a list of
  environments, then the body in each; the enclosing `ρ` is not extended.

---

## 8. Phases

Conventions for every phase:

- Work on `main` (single-developer repository), one commit per substep or per
  phase as marked; messages in the imperative, first line ≤ 72 characters, with
  the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` when
  produced by Claude.
- Before a commit: `moon fmt && moon info && moon check --deny-warn && moon test`,
  and the phase's oracle at or above its floor. `pkg.generated.mbti` is committed.
- `just quick` is the developer gate; `just ci` is what CI runs. Both exist
  from Phase 0 and grow.
- "Pass" is a command whose exit status is 0; "Fail means" says how to read a
  non-zero result.

### Phase 0 — Scaffold, reference pin, harness skeleton

Goal: a repository where every later phase has a place to put its code and a
gate to run. Nothing is parsed yet.

0.1 **Commit the generated scaffold as is** (`moon new` output already in the
tree) so that later diffs are readable.
- Pass: `git log --oneline | wc -l` is 1; `moon check` passes.

0.2 **Module and package layout.** Rename `cmd/main` to `cmd/pure-py`; create
`basic/`, `error/`, `token/`, `lexer/`, `ast/`, `parser/`, `write/`, `sieve/`,
`analysis/`, `context/`, `check/`, `value/`, `eval/`, `program/`, `test/embed/`
with a `moon.pkg` and an empty `///|` file each; root `moon.pkg` imports them;
`moon.mod` gets `marianoguerra/error-report@0.1.0` and `moonbitlang/x@0.5.1`
(the latter only in `cmd/pure-py` and `program`); `preferred_target = "native"`
is **not** set (library stays wasm-first like shrubbery; the CLI is built with
`--target native` explicitly).
- Pass: `moon check --deny-warn` and `moon build --target native` succeed;
  `moon info` produces a `pkg.generated.mbti` per package.

0.3 **Vendor the conformance suite and pin the reference.** `tools/reference.json`
`{ "repository": "https://github.com/pure-py/pure-py-spec", "commit": "f850209…", "spec_version": "0.15.1" }`;
`tools/fetch-reference.sh` clones at that commit into `reference/` (gitignored)
and copies `reference/test/` to `test/conformance/` (committed, unmodified, with
its `README` pointer). Python `__pycache__` excluded.
- Pass: `test/conformance` has 393 `.py` files and `diff -r reference/test test/conformance` is empty except `__pycache__`.

0.4 **Harness skeleton.** `tools/conform.py`: a port of `run-all.py`'s verdict
logic that drives **our** CLI (`pure-py parse|check|check-program|run`) instead
of the Python scripts, with `--impl PATH`, `--filter SUBSTR`, `--show N`,
`--phase parse|check|program|run|all`, and a `--reference` mode that drives the
reference scripts instead (needs `reference/` and Python) to write
`test/golden/{parse,check,program}.txt`. `test/conform-policy.json` with every
bucket's floor at `0` and its total. `justfile` targets: `check`, `test`, `fmt`,
`build`, `info`, `quick`, `ci`, `goldens`, `conform`, `reference-fetch`,
`boundary-check`.
- Pass: `tools/conform.py --reference --regen` writes goldens and reports
  `288/288` for the reference; `tools/conform.py` against the stub CLI reports
  `0/288` and exits 0 because every floor is 0; `just ci` passes.

0.5 **Repository hygiene.** `AGENTS.md` gains the project's rules (layering,
"the reference is the specification for the checker, CPython for the runtime",
goldens are regenerated not edited, ratchet policy), `README.md` states scope
and status, `.github/workflows/check.yml` runs `just ci` on Ubuntu with MoonBit
installed from `cli.moonbitlang.com` and Python 3 from the runner, `.githooks/pre-commit`
runs `just quick`, `tools/boundary-check.sh` greps that only `error/` names
`error-report` and only `program/` and `cmd/` name `moonbitlang/x`.
- Pass: `tools/boundary-check.sh` exits 0; CI is green on the pushed commit.

Commit: `Scaffold the port: packages, vendored suite, harness skeleton`.

### Phase 1 — Positions and the tokenizer

Goal: `pure-py tokens` agrees with CPython's `tokenize` on every file in the
suite.

1.1 **`basic`**: `Pos {line : Int, col : Int, offset : Int}` (1-based line,
0-based code-point column, code-unit offset), `Span`, `Span::merge`, `Source
{name, text, line_starts}` with `line_col`, `line_text`, `byte_col(pos)`.
- Pass: unit tests for `byte_col` on a line with `é` and an astral character.

1.2 **`token`**: `TokenKind` = `Name | Number | String(prefix~) | FString(prefix~) | Bytes(prefix~) | Op(String) | Newline | NL | Indent | Dedent | Comment | EndMarker | Error(msg)`;
`Token {kind, text, span}`; `Token::name()` in `tokenize`'s spelling
(`NAME`, `NUMBER`, `STRING`, `FSTRING_START`… collapsed as described in the
oracle).
- Pass: `moon info` shows the interface; snapshot test of a token list.

1.3 **Lexer core**: `lex(source) -> Array[Token] raise LexError`; line
structure (NEWLINE/NL/INDENT/DEDENT, bracket depth, backslash continuation,
comments, blank lines, EOF handling, tab columns with `col`/`altcol`).
- Pass: snapshot tests for: nested blocks, dedent to two levels, comment-only
  lines, continuation inside and outside brackets, trailing whitespace, no final
  newline, CRLF input, an inconsistent dedent (error message
  `unindent does not match any outer indentation level`), mixed tabs/spaces
  that CPython rejects.

1.4 **Names, keywords, operators**: identifiers per Python (`XID_Start`/
`XID_Continue`; implement ASCII + "any letter or digit or `_` by Unicode
general category" via core's `char` predicates, and note the approximation);
every Python operator and delimiter including `->`, `:=`, `**=`, `//=`, `@=`,
`...`, `<>` rejected.
- Pass: snapshot of a line containing every operator; `tools/tokdiff.py` on
  `test/corpus/python/operators.py`.

1.5 **Numbers**: all forms of §7.1, value parsing in `token` helpers
(`Token::int_value() -> BigInt`, `float_value() -> Double`, `is_imaginary`).
- Pass: table test against `test/golden/numbers.txt` generated by
  `tools/gen_number_cases.py` (CPython `repr(eval(lexeme))`), including
  `1_000`, `0x_ff`, `0o17`, `0b1_0`, `1e10`, `1.`, `.5`, `1_0.0_1e-1_0`, `3j`,
  and the invalid `1__0`, `0_`, `09`.

1.6 **Strings**: prefixes, single/triple quotes, escapes, raw, bytes ASCII
check, f-strings tokenised as one `FString` token (matching quotes, nested
braces balanced, no escape processing).
- Pass: table test against `test/golden/strings.txt` (CPython `repr` of the
  value for each literal); unterminated string error at the right position.

1.7 **`pure-py tokens` and the token oracle.** Output format:
`L:C-L:C KIND text` per token with `text` as Python `repr`; `tools/pytokens.py`
produces the same from `tokenize.generate_tokens`, mapping `FSTRING_START…END`
sequences to one `FSTRING` with the full text, dropping `ENCODING`, and
`tools/tokdiff.py` compares sha1 digests per file against
`test/golden/tokens.index`.
- Pass: `tools/tokdiff.py --show 0` reports `393/393`; `conform-policy.json`
  `tokens` floor set to 393.

Commit per substep; phase commit message: `Tokenize Python 3.12 source and match CPython's tokenize on the suite`.

### Phase 2 — AST, parser, dump, unparse

Goal: `pure-py dump` agrees with CPython's `ast` on every file in the suite
and on a corpus that covers the grammar; `pure-py unparse` round-trips.

2.1 **`ast` package** exactly as §3.1 plus `span()` accessors, `walk`,
`dump(module, pos~)`, builders (§3.2). No parser yet.
- Pass: `ast/ast_test.mbt` builds `print("Hello, World!")` by hand and its
  `dump` is
  `(Module body=[(Expr value=(Call func=(Name id=print ctx=Load) args=[(Constant value='Hello, World!')] keywords=[]))])`.

2.2 **Parser skeleton**: `Parser {tokens, i}` with one-token lookahead,
`expect`, `peek_name`, error type `PythonSyntax(msg, span)`, `parse_module`,
statement dispatch, `parse_block` (NEWLINE INDENT stmts DEDENT | simple stmts on
one line separated by `;`).
- Pass: `pass`, `x = 1`, `x = 1; y = 2`, nested `if` blocks parse; a stray
  DEDENT yields a syntax error with a span.

2.3 **Expressions** in Python's precedence (lambda < if-else < or < and < not
< comparison (chained; `in`, `not in`, `is`, `is not`) < `|` < `^` < `&` <
shifts < `+ -` < `* / // % @` < unary `+ - ~` < `**` (right-assoc, binds tighter
than unary on its left, looser on its right: `-2**2` is `-(2**2)`, `2**-1` ok)
< await < primary (call, subscript with slices and tuples of slices, attribute)
< atom (name, number, strings with implicit concatenation, f-string, `...`,
`None/True/False`, parenthesised expr / tuple / generator, list / list-comp,
dict / set / dict-comp / set-comp, starred, walrus in the allowed places)).
Store/Load/Del contexts assigned by the statement parser.
- Pass: `test/corpus/python/expr_*.py` (precedence, calls with every argument
  kind, comprehensions with several `for`/`if`, nested lambdas, slices) agree
  with CPython under `tools/astdiff.py`.

2.4 **Simple statements**: expression, assignment with chained targets and
tuple/list/starred targets, annotated, augmented, `pass break continue return
raise global nonlocal del assert import from-import` (relative levels, `*`,
parenthesised names, `as`).
- Pass: `test/corpus/python/stmt_simple.py` agrees with CPython.

2.5 **Compound statements**: `if/elif/else`, `while/else`, `for/else`,
`try/except/else/finally` and `except*`, `with` (parenthesised items),
`def` (all parameter kinds, defaults, annotations, `->`), `class`, decorators,
`async` variants, `match` with the full pattern grammar of PEP 634 (literal,
capture, wildcard, value `a.b.c`, group, sequence with `*rest`, mapping with
`**rest`, class with positional and keyword sub-patterns, `|`, `as`, guards)
including the soft-keyword disambiguation.
- Pass: `test/corpus/python/stmt_compound.py`, `match_*.py`, `def_*.py`,
  `class_*.py` agree with CPython; every `excluded/syntactic` file parses.

2.6 **AST oracle**: `tools/pyast_dump.py` (Python side of §3.4, including the
`MatchSequence` classification from source and byte→code-point columns),
`tools/astdiff.py` (digests against `test/golden/ast.index`, `--pos`
variant against `test/golden/ast-pos.index`).
- Pass: `tools/astdiff.py --show 0` and `tools/astdiff.py --pos --show 0` both
  report all files matching: the suite's 393 files plus `test/corpus/python/*`
  (target ≥ 60 files written during 2.3–2.5, each ≤ 80 lines, each named for the
  production it covers); policy floors set to those totals.

2.7 **Syntax errors**: message and position for the errors the suite can reach
through `check-program`'s `load` (`parse error: …`), plus the common ones
(unexpected indent, expected `:`, unmatched bracket, invalid assignment target,
`return` outside function is NOT a parser error in CPython — it is a compile
error, so the parser must accept it and the sieve/checker reject it as the
reference does).
- Pass: snapshot tests; `python-error/syntactic-only` is handled by the harness
  as in `run-all.py` (it only runs Python).

2.8 **`write` (unparse)**: the inverse of the parser with CPython's
`ast.unparse` layout rules (precedence-driven parenthesisation, 4-space
indentation, `repr` for constants, one statement per line, `elif` chains
recovered from nested `If` in `orelse`).
- Pass: for every file in the corpora, `dump(parse(unparse(parse(f)))) == dump(parse(f))`
  (`moon test` over embedded corpus or `just unparse-check` via the CLI); when
  Python is present, `ast.dump(ast.parse(unparse(f))) == ast.dump(ast.parse(f))`
  for every file.

Commit per substep; phase commit: `Parse Python 3.12 into a CPython-shaped AST and print it back`.

### Phase 3 — The sieve (`syntax.py`)

Goal: `pure-py parse` reproduces `syntax.py` on every file.

3.1 **Port `check_stmt`, `check_classdef`, `check_field`, `check_pattern`,
`check_expr`, `check_keyword`, `check_generator`, `check_arguments`,
`check_top_level`** with the messages of Appendix A verbatim and the same
traversal order (the first violation in traversal order is the one reported).
`NotYetSupported` carries the issue number.
- Pass: `sieve/sieve_test.mbt` has one test per message (36 prohibited, 22 not
  yet supported) built from small sources, checking message, exit code and the
  node's position.

3.2 **`pure-py parse`**: `FILE: ok` / `FILE:L:C: msg`, exit 0/1/2, several files
in one invocation with the last non-zero code winning, as the reference does;
a Python syntax error is `FILE:L:C: parse error: msg`, exit 1.
- Pass: `tools/conform.py --phase parse --show 0` reports all 393 files matching
  `test/golden/parse.txt` (exit code, line, column, message); policy floor set.

Commit: `Reject the Python that PurePy excludes syntactically, as syntax.py does`.

### Phase 4 — Syntactic analyses and contexts (`aux.py`, `contexts.py`)

Goal: the auxiliary functions of Annex A.1–A.2 with unit tests; no user-facing
change yet.

4.1 **`analysis`**: `statements` (mutual regions), `assigns_stmt/body/seq`,
`binds`, `binds_seq`, `binds_quals`, `fv_e`, `fv_stmt`, `captures`,
`captures_e`, `captures_quals`, `captures_region`, `names_in_target`,
`find_first_reassigning`, `find_nested_import`, `split_imports`, `find_import`,
`own_fields`, `qualified_name`, `is_qualified_name`.
- Pass: `analysis/*_test.mbt` reproduce the spec's Annex A.1 equations on
  hand-built sources, e.g. `captures` of `mutual_split_by_assign.py`'s region is
  `{c, g}` minus region names, `assigns` of a match is the union of `binds` and
  bodies, `captures_e` of `[lambda x: x**i for i in range(10)]` is `{}` while
  the body alone captures `{i}`.

4.2 **`context`**: `Status`, `Entry`, `Context` (sorted map), `ClassEntry`,
`ModuleContext {gamma, program, q}`, `override_gamma`, `override_var`,
`var_status`, `class_of`, `module_of`, `entry_of`, `class_entry`, `short_name`,
`ancestors`, `fields`, `field_map`, `ResultType`, `merge_results`,
`override_results`, `merge_delta`, `extend_entry`, `extend_context`,
`PREDEFINED_MEMBERS`, `predefined_context`.
- Pass: unit tests for the algebra of Figure 2.2 and Definition 3.1 (⊥ units,
  `ff` when defined on one side only, ⊲ preferring loaded over stub, `Returns`
  as zero of ⊗ and unit of ⊕), `field_map` positional/keyword/duplicate/over-
  and under-saturated cases.

Commit: `Port the syntactic analyses and context algebra of Annex A`.

### Phase 5 — Module well-formedness (`statements.py`, `patterns.py`, `reasons.py`, `check_module.py`)

Goal: `pure-py check` reproduces `check_module.py` on every module-level file,
with the predefined modules as the only importable ones.

5.1 **`error::Reason`** with all 31 reasons and messages (Appendix B).
- Pass: `error/reasons_test.mbt` snapshots every message against the Python
  text (copied into the test as expected strings).

5.2 **`check/patterns.mbt`**: `is_catch_all`, `literal_value` (Python equality
of constants: `1 == 1.0`, `-0 == 0`), `dict_key`, `subsumes`, `check_pattern`,
`check_pattern_list`.
- Pass: unit tests for every `sub-*` rule of Figure 3.3 and every failure of
  Figure 3.4 (nonlinear, arity, unknown class, duplicate keyword, duplicate dict
  key, unreachable).

5.3 **`check/statements.mbt`**: `result_type`, `result_type_body`, `check_seq`,
`next_ctx_after`, `check_mutual_region`, `check_bodies`, `check_assign_targets`,
`check_distinct_names`, `check_stmt`, `check_match_cases`, `check_expr`,
`check_comprehension`, `check_quals`, `class_entry_for`, `check_class_decl`.
- Pass: one unit test per rule of Figures 3.1–3.2, written from the spec's
  prose examples, and the `excluded/static` sources embedded as tests with their
  `.error.expected` message.

5.4 **`check/module.mbt`**: `check_module` (cache, loading stack, cycle →
`Program`), `check_module_` (nested import, stray import, prefix, `__name__`,
top-level return, `check_seq`, submodule clash, signature), `imports`,
`import_bindings`, `loads_as`, `submods`, `imported_entry`, `own_members`,
`signature`, `find_binder`, `binds_name`, `proper_prefixes`, `prefix_of`.
- Pass: unit tests with an in-memory `SourceTree` for each of Figures 3.5–3.7's
  rules, including `import a.b.c` producing a nested `ModuleLoaded` chain and
  `from pkg import sub` loading the stub.

5.5 **`pure-py check`**: runs the sieve first (exit 1/2 as `parse`), then
`check_module` with `M = predefined ∪ {__main__}`; output
`FILE: ok` or `FILE:L:C: msg`, exit 3 for ill-formed. `--error-format human`
renders through `error-report` with the primary label at the node and any
`related` label.
- Pass: `tools/conform.py --phase check --show 0` matches `test/golden/check.txt`
  for all 240 module-level files (exit, line, column, message); floor set; a
  snapshot test of the human rendering for `shadow_captured.py` shows both the
  capture site and the reassignment.

Commit: `Decide module well-formedness as check_module.py does`.

### Phase 6 — Program well-formedness (`check_program.py`)

Goal: `pure-py check-program` reproduces `check_program.py` on all 48
program-level tests.

6.1 **`program`**: `SourceTree::from_entry(path)` implementing `is_module`,
`module_name`, `source_tree`, `load` (reads and parses each file; a parse
error or a sieve rejection of an imported module is `Program("path: parse error: …")`
or `Program("path: msg")`, exit 4), `import_targets`, `with_proper_prefixes`,
`discover`, namespace packages as empty bodies, predefined modules as empty
bodies with `<name>` paths.
- Pass: unit tests over a temporary directory tree (native target only, gated
  with `options(targets: …)`) for discovery of `pkg/__init__.py`, `pkg/sub.py`,
  a namespace package, and `__pycache__` exclusion.

6.2 **`check/program.mbt`**: `walk_program`, error attribution (`path: msg` for
a module other than `__main__`), `check_program`.
- Pass: `tools/conform.py --phase program --show 0` matches
  `test/golden/program.txt` for all 48 directories (exit code and message
  substring); floor set.

Commit: `Decide program well-formedness over a source tree`.

### Phase 7 — Values, formatting, arithmetic (Annex A.3)

Goal: the runtime's data and every operator, tested against tables generated
by CPython, before any statement is evaluated.

7.1 **`value` types** (§6), `Env` operations (`override`, `extend` with the
⊲ rules on `Mod` values, lookup), `ClassEntry` reuse from `context`.
- Pass: `moon test`; `Env::extend` prefers loaded modules and merges same-name
  modules recursively.

7.2 **Python `str`/`repr`** (§7.4) and float repr (§7.3), `Value::str`,
`Value::repr`, object and container printing, `-0.0`, nested quoting.
- Pass: `test/golden/float_repr.txt` (generated by `tools/gen_value_cases.py`
  from a fixed list of ~200 doubles as hex bit patterns → `repr`) matches
  entirely; `test/golden/repr.txt` (strings with quotes, escapes, non-ASCII,
  nested containers, objects) matches entirely.

7.3 **Arithmetic and comparison** (§7.2): `binop`, `unop`, `eq`, `eq_elems`,
`contains`, `contains_elems`, `elems`, `iter`, `getitem`, `entries`, `update`,
`outcome`, each returning `Outcome` with `Aborts`/`Stuck` as A.3 prescribes.
- Pass: `test/golden/arith.txt` — a table of ~400 expressions over
  literals (`-7 // 2`, `2 ** 100`, `2 ** -1`, `7 / 2`, `10 % 3.0`, `-7.5 // 2`,
  `1e308 * 10`, `"a" < "b"`, `[1, 2] < [1, 3]`, `(1,) < (1, 2)`, `"é"[0]`,
  `len("héllo")`, `"xyz"[-1]`, `[1, "a"] == [2, 3]`, NaN cases, `True == 1`,
  `1 == "a"`, `1 / 0`) with CPython's `repr` of the result or the exception
  name, generated by `tools/gen_value_cases.py`; our side evaluates each through
  `pure-py eval-expr` (a hidden CLI command that parses an expression and
  evaluates it in an empty environment). Every row matches, where rows that
  PurePy declares undefined are marked `stuck` in the table by hand and must
  produce `Stuck` (`True == 1`, `1 == "a"`, `not 1`, `[1, "a"] == [1, 3]`).

Commit: `Runtime values with Python's printing and arithmetic`.

### Phase 8 — The interpreter, module level

Goal: `pure-py run` produces CPython's output on every module-level test.

8.1 **Patterns** (Figure 4.2): `match_pattern(env, p, v) -> MatchResult`.
- Pass: unit tests per rule including the stuck cases of §7.6 and subclass
  matching.

8.2 **Expressions** (Figures 4.5–4.9, 4.10): `eval_expr`, `eval_exprs`,
`eval_quals`, primitives, closures, constructor calls (`resolve_class`,
`field_map`), attribute on modules/objects, subscript, `and`/`or`/conditional,
arity errors, non-callable.
- Pass: unit tests per rule; `python-error/dynamic` sources embedded with their
  expected kinds.

8.3 **Statements** (Figures 4.3–4.4): `eval_stmt`, `eval_seq` over
`analysis::statements`, `eval_def` (regions), `eval_match` with `dispatch`,
classes, assert.
- Pass: unit tests per rule; `semantically-valid/functions` and `scopes` sources
  embedded with their `.expected` output captured through a `Printer` sink.

8.4 **`pure-py run`** for a single file: builtins environment, `__name__`,
`sys.argv`, stdout buffering that flushes before an abort message, exit codes
(§2.1), `Stuck` reporting.
- Pass: `tools/conform.py --phase run --show 0` for module-level:
  `semantically-valid` (77 files) stdout byte-exact and exit 0;
  `python-error/dynamic` (11): nine abort with the kind on stderr, exit 1, and
  prior stdout matching `.output.expected`; two are stuck in PurePy although
  Python raises — `assert_falsy` (`assert 0`, the condition is not a Bool) and
  `attr_non_object` (attribute reference on a number) — and must exit 5; the
  policy file names them; `excluded/dynamic` and `dynamic-semantic` (7) exit 5;
  `excluded/static/pending` (6) exit 5 with the operation named (they are
  "static pending" upstream; until then they are stuck runs); floors set.

Commit: `Evaluate modules by the operational semantics and match CPython`.

### Phase 9 — Imports and program evaluation

Goal: `pure-py run main.py` on every program-level test.

9.1 **`eval/load.mbt`** (Figures 4.11–4.13): `load(q)` with the per-run cache,
`eval_imports`, `imports_name`, `loads_as`, ancestors before descendants,
`submods` stubs, predefined modules' environments, `eval_program`.
- Pass: unit tests with in-memory `SourceTree`s for each rule, including
  `import_twice` printing once and `import_failing_ancestor` aborting during
  the ancestor's load.

9.2 **CLI**: `run MAIN` builds the `SourceTree`, checks the program first
(a program that is ill-formed does not run: the harness never asks it to, but a
person may; report the check diagnostic and exit with its code), then runs.
- Pass: `tools/conform.py --phase run` over program-level: `semantically-valid`
  (39 dirs) stdout and exit; `python-error/dynamic` (2) kind and exit; floors
  set. `tools/conform.py` (all phases) reports **288/288** and
  `conform-policy.json` has every floor at its total.

Commit: `Load and evaluate programs; the conformance suite passes`.

### Phase 10 — Diagnostics for people

Goal: `check --error-format human` is worth reading. No conformance change.

10.1 **Related spans** for `CapturedReassignment` (the capturing lambda/def),
`SelfCaptureAssignment`, `UnreachableCase` and `UnreachableStatement` (the
`return`), `DuplicateClassName`/`DuplicateMutualName` (the first declaration),
`InheritedFieldClash` (the base's field), `ImportAfterStatement` (the statement).
10.2 **Help lines** for the definite-assignment family (`assign it in every
branch, or before the if`), `ModuleAsValue`, `ClassAsValue`, `CapturedGeneratorVariable`.
10.3 **Codes** `purepy::<reason>` and `--error-format json`.
- Pass: `error/render_test.mbt` snapshots ten renderings with `mono_theme`,
  `color: Never`; `tools/conform.py` still 288/288.

Commit: `Explain rejections with source-annotated reports`.

### Phase 11 — Library surface, codegen consumer, publishing

11.1 **Façade** (`pure-py.mbt`): `parse(source, name~) -> Module raise`,
`sieve(module)`, `check_module(module, tree~)`, `check_program(tree)`,
`run(tree, argv~, out~)`, `unparse(module)`; `README.mbt.md` with doctests for
each, compiled as tests.
11.2 **`test/embed`**: builds a small PurePy program with the `ast` builders
(a dataclass, a mutual region, a match) and prints it with `write`;
`tools/embed-smoke.sh` builds it and greps the link map for `lexer`, `parser`,
`check`, `eval` — none may appear.
11.3 **`.mbti` review**: every package's public surface reviewed against the
minimum the façade, the CLI and the harness need; the rest made private.
11.4 **`moon publish --dry-run`** from a clean checkout; `CHANGELOG.md`.
- Pass: doctests pass; `tools/embed-smoke.sh` exits 0; dry run succeeds;
  `git diff --exit-code` after `moon info && moon fmt`.

Commit: `Public API, a code-generation consumer, and a publishable module`.

### Phase 12 — Hardening

12.1 **Property tests** with `moonbitlang/core/quickcheck`: generated ASTs
round-trip through `write` and `parser`; generated values satisfy `eq`
reflexivity where defined and `repr` round-trips through the parser for
literals and containers.
12.2 **Fuzz the tokenizer and parser** with mutated corpus files (`tools/fuzz.py`,
opt-in): no crash, no non-termination; every rejection carries a span.
12.3 **Nesting limits**: `max_depth` on the parser and evaluator (as the
Starlark port and shrubbery do for wasm stacks), with a diagnostic rather than
a stack overflow.
12.4 **Performance baseline**: `moon bench` for tokenize/parse/check/run on the
largest corpus file; recorded in `CHANGELOG.md`, no target beyond "does not
regress by 2× unnoticed".
- Pass: `moon test --target all` (wasm, wasm-gc, js, native) green; fuzz run of
  10 000 mutations clean.

Commit: `Harden the front end and the evaluator`.

### After the plan: the pending features

The parser already accepts everything below; each is a sieve relaxation plus
checker and evaluator rules, and each has tests waiting in
`semantically-valid/pending` (exit 2 today). In the order upstream is likely
to specify them, with the issue numbers the sieve cites:

| feature | issue | sieve | checker | evaluator |
|---|---|---|---|---|
| chained comparison, chained `and`/`or` | #82 | drop `len > 1` checks | none | desugar to nested binary forms |
| identity `is` / `is not` | #81 | allow ops | none | `None` only, else stuck |
| case guards | #83 | allow guard | guard checked under pattern bindings; reachability weakens | evaluate guard |
| default arguments | #56 | allow | defaults are expressions of Γ | arity range |
| `*args` / `**kwargs` | #57 | allow | | |
| destructuring assignment / comprehension targets | #54 | allow tuples | `binds` of targets | pattern-like assignment |
| slicing | #59 | allow `Slice` | none | `getitem` on slices |
| f-strings | #55 | parse `JoinedStr` parts | expressions of Γ | `str` of parts |
| import-as, multi-import, relative, `*` | #53 | allow | context of aliases | |
| star / or / rest patterns, attribute values | #84 #85 #86 | allow | subsumption extended | matching extended |
| sets | #147 | allow | | new value kind |
| decorators, enums | #58 #86 | | | |

---

## 9. Decisions made under assumption

Each of these is a judgement call recorded so it can be reversed knowingly.

1. **One AST, CPython-shaped**, not a separate PurePy core tree (§3.3).
2. **Stuck is exit 5 and is checked**, not tolerated (§2.1).
3. **A per-run module cache**, to agree with CPython where the spec is silent
   about observable effects of repeated loading (§6).
4. **`typing.Callable` follows the reference, not the spec table** (§7.5).
5. **Ints are `BigInt` throughout**; an `Int64` fast path is deferred.
6. **Strings are UTF-16 with a code-point view**, not a `Bytes`/UTF-8 or a
   code-point array; the corpus never indexes astral characters, and the view
   keeps the runtime simple.
7. **Identifier classes are approximated** by Unicode general categories rather
   than the full `XID` tables; the token oracle covers the suite, which is ASCII.
8. **`repr` printability** is exact for ASCII/Latin-1 and treats every other
   code point as printable (§7.4).
9. **The harness is Python**, as in shrubbery: the CLI is the thing under test,
   and process-level comparison is what the conformance suite specifies.
10. **Goldens for `parse`/`check`/`program` are regenerated from the reference
    checker**, never edited; a diff there means upstream changed or we did, and
    the commit says which.

---

## Appendix A — The sieve's messages (verbatim from `syntax.py`)

Prohibited (exit 1): `multiple assignment targets`, `item assignment prohibited`,
`attribute assignment prohibited`, `return type annotations prohibited`,
`augmented assignment (+=, etc.) prohibited`, `annotated assignment prohibited`,
`del prohibited`, `for loops prohibited`, `while loops prohibited`,
`with statements prohibited`, `async prohibited`, `raise prohibited`,
`try/except prohibited`, `global prohibited`, `nonlocal prohibited`,
`class declaration only at module top level`, `break prohibited`,
`continue prohibited`, `unknown statement type: <T>`,
`class must have exactly the @dataclass decorator`,
`only the @dataclass decorator is supported on classes`,
`multiple inheritance prohibited`, `base class must be a simple name`,
`class keyword arguments prohibited`,
`dataclass body may contain only field declarations`,
`field target must be a simple name`, `field default values prohibited`,
`field type annotation must be Any`, `class pattern head must be a qualified name`,
`dict pattern keys must be string literals`, `unknown pattern type: <T>`,
`<bytes|complex> literals prohibited`, `prohibited literal type: <T>` (`ellipsis`),
`binary operator '<sym>' prohibited` (`| & ^ << >> @`),
`unary operator '~' prohibited`, `generator expressions prohibited`,
`walrus operator (:=) prohibited`, `starred expressions prohibited`,
`yield prohibited`, `async comprehensions prohibited`,
`keyword-only arguments prohibited`, `positional-only arguments prohibited`,
`unknown expression type: <T>`.

Not yet supported (exit 2), as `<feature> not yet supported (#N)`:
`destructuring assignment` #54, `decorators` #58,
`multi-target import (import a, b)` #53, `import-as` #53, `relative imports` #53,
`from-import with no module` #53, `from M import *` #53, `from-import-as` #53,
`case guards` #83, `enum classes` #86, `attribute value patterns` #86,
`complex value patterns` #83, `star patterns` #84, `rest capture in dict patterns` #84,
`or-patterns` #85, `chained boolean operator` #82, `chained comparison` #82,
`identity operator (is/is not)` #81, `set literals` #147, `set comprehensions` #147,
`slicing` #59, `f-strings` #55, `destructuring in comprehensions` #54,
`*args` #57, `**kwargs` #57, `default arguments` #56.

## Appendix B — The reasons (verbatim from `reasons.py`)

| reason | message |
|---|---|
| DuplicateFieldName(name, cls) | `duplicate field name '{name}' in class '{cls}'` |
| UnknownBaseClass(base) | `base class '{base}' is not declared in this module` |
| InheritedFieldClash(field, base) | `field '{field}' clashes with inherited field from '{base}'` |
| DuplicateClassName(name, module) | `duplicate class name '{name}' in module '{module}'` |
| UnassignedVariable(name) | `'{name}' is not definitely assigned` |
| CapturedReassignment(name) | `'{name}' captured by previous statement, reassigned here` |
| SelfCaptureAssignment(name) | `'{name}' captured by right-hand side` |
| CapturedGeneratorVariable(name) | `'{name}' bound by a generator, captured by a lambda` |
| UnreachableStatement | `unreachable statement` |
| ConstructorArityMismatch(cls, expected, got) | `constructor for '{cls}' expects {expected} arguments, got {got}` |
| UnknownConstructorKeyword(cls, fields) | `constructor keywords for '{cls}' must be {fields joined by ", "}` |
| PatternArityMismatch(cls, expected, got) | `pattern for '{cls}' expects {expected} sub-patterns, got {got}` |
| UnknownClassInPattern(cls) | `'{cls}' is not a declared class` |
| UnknownFieldInPattern(cls, fields) | `pattern keywords for '{cls}' must be {fields}` |
| DuplicatePatternKeyword(cls) | `duplicate keyword in pattern for '{cls}'` |
| DuplicateDictKey(key) | `duplicate key '{key}' in dict pattern` |
| NonlinearPattern(index) | `repeated variable in pattern {index}` |
| UnreachableCase(index, subsumed_by) | `case {index} unreachable: subsumed by case {subsumed_by}` |
| DuplicateMutualName(name) | `duplicate name '{name}' in mutual region` |
| NonTopLevelImport | `import only allowed at module top level` |
| ImportAfterStatement | `imports must precede all other statements` |
| SubmoduleNameClash(name, submodule) | `binding '{name}' clashes with submodule '{submodule}'` |
| SubmoduleNotImported(q) | `submodule '{q}' is not imported` |
| UnassignedMember(x, q) | `member '{x}' of module '{q}' is not definitely assigned` |
| TopLevelReturn | `top-level return not allowed (module body must not return)` |
| EmptyFromImport | `empty name list` |
| UnknownModule(q) | `unknown module {q!r}` (Python `repr` quoting) |
| UnknownMember(x, q) | `module {q!r} has no member {x!r}` |
| ModuleAsValue(name) | `'{name}' refers to a module; modules are not first-class values` |
| OwnDescendantImport(q, q0) | `'{q}' is a descendant of the importing module '{q0}'; import it with a from-import` |
| ClassAsValue(name) | `'{name}' refers to a class; classes are not first-class values` |

Program-level (exit 4): `import cycle: a -> b -> a`, `module 'x' not found under <dir>`,
`<path>: parse error: <msg>`, `<path>: <sieve msg>`; and an `IllFormedModule`
raised while checking a module other than `__main__` is reported as
`<path>: <msg>` with exit 3.

## Appendix C — Conformance suite inventory (commit f850209)

| bucket | files | our phase | our expectation |
|---|---|---|---|
| module-level/semantically-valid (+conditionals, functions, scopes) | 58 + 4 + 11 + 4 | 3, 5, 8 | parse 0, check 0, run = `.expected` |
| module-level/semantically-valid/pending | 25 | 3 | parse 2 |
| module-level/excluded/syntactic | 36 | 3 | parse 1 + message |
| module-level/excluded/static | 41 | 5 | parse 0, check 3 + message, run not required |
| module-level/excluded/static/pending | 6 | 5, 8 | parse 0, check 0, run 5 (stuck) |
| module-level/excluded/dynamic, dynamic-semantic | 6 + 1 | 8 | check 0, run 5 |
| module-level/python-error/static (+pending) | 19 + 1 | 5 | check 3 + message (pending: check 0) |
| module-level/python-error/dynamic | 11 | 8 | run: kind on stderr, exit 1 (9); stuck, exit 5 (`assert_falsy`, `attr_non_object`) |
| module-level/python-error/syntactic-only | 1 (+2 helpers) | — | Python-only; the harness runs Python if present, else skips |
| program-level/semantically-valid | 39 dirs | 6, 9 | check-program 0, run = `expected` |
| program-level/excluded | 15 dirs | 6 | check-program = `expected_exit` (3) + `expected_error` |
| program-level/python-error | 14 dirs (2 dynamic) | 6, 9 | check-program = `expected_exit` (3 or 4); dynamic: run kind |
