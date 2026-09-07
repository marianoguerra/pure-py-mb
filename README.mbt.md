# pure-py

**PurePy** in MoonBit: a tokenizer and parser for Python 3.12 producing a
CPython-shaped abstract syntax tree, a sieve that rejects the Python that
PurePy excludes, a well-formedness checker, an interpreter, a printer that
turns the tree back into Python source, and a command-line tool.

PurePy is a pure functional subset of Python with a small-step operational
semantics and a static well-formedness judgement, specified in
[pure-py/pure-py-spec](https://github.com/pure-py/pure-py-spec). This module is
a port of that specification: the reference checker is the specification for
what `check` decides, and CPython is the oracle for what `run` prints.

## Status

Under construction, phase by phase. See
[implementation-plan.md](implementation-plan.md) for the plan and
`test/conform-policy.json` for exactly how much of the conformance suite passes
today.

## The command

```
pure-py tokens FILE           one token per line
pure-py dump FILE [--pos]     the abstract syntax tree
pure-py unparse FILE          Python source regenerated from the tree
pure-py parse FILE...         reject what PurePy excludes syntactically
pure-py check FILE...         decide module well-formedness
pure-py check-program MAIN    decide program well-formedness
pure-py run MAIN [ARGS...]    evaluate a program
```

Exit codes follow the reference's: `0` accepted, `1` a prohibited form, `2` a
form that is planned but not yet supported, `3` an ill-formed module, `4` an
ill-formed program, and `5` -- this port's own -- an operation the semantics
leaves undefined.

## Development

`just` lists every task. The three that matter:

```
just quick        type-check, format, unit tests, layering, conformance
just conform      the conformance suite, held to its ratchet
just one PATTERN  the tests whose name contains PATTERN, in full
```

The conformance suite under `test/conformance/` is the reference's own, copied
verbatim, and the expected answers under `test/golden/` are the reference's
answers. Both are committed, so the suite runs with nothing but MoonBit and
Python 3 installed. Regenerating them needs the reference checkout:
`just reference-fetch`, then `just goldens`.

## License

Apache-2.0.
