# pure-py-mb

**PurePy** in MoonBit: a tokenizer and parser for Python 3.12 producing a
CPython-shaped abstract syntax tree, a sieve that rejects the Python PurePy
excludes, a well-formedness checker, an interpreter, a printer, a
command-line tool and an embedding interface.

PurePy is a pure functional subset of Python with a small-step operational
semantics and a static well-formedness judgement, specified in
[pure-py/pure-py-spec](https://github.com/pure-py/pure-py-spec). This is a
port of that specification. The reference checker is the specification for
what `check` decides; CPython is the oracle for what `run` prints.

**Playground:** <https://marianoguerra.github.io/pure-py-mb/> — the whole
library in a browser tab, with 27 examples. The page is a real embedder: the
`host` module its examples import is supplied through the embedding
interface.

## What is here

| | | |
|---|---|---|
| [`lib/`](lib) | `marianoguerra/pure-py` | the library — [readme](lib/README.mbt.md) |
| [`cli/`](cli) | `marianoguerra/pure-py-cli` | the `pure-py` command |
| [`docs/`](docs) | | [embedding guide](docs/embedding.mbt.md), examples compiled as tests |
| [`playground/`](playground) | | the page, built to wasm-gc |
| [`test/`](test) | | the conformance suite, the goldens, the corpora |
| [`tools/`](tools) | | the differential harness and the generators |

The repository root is a development module that is never published. It
exists so that the harness, the corpora, the documentation and the playground
reach the two real modules through their public API only, which is what keeps
that API honest — and so that publishing the library does not publish half a
megabyte of test fixtures.

```sh
moon add marianoguerra/pure-py       # the library
moon add marianoguerra/pure-py-cli   # the command
```

## Conformance

Eight oracles, every one compared against something outside this port.

| oracle | compared with | result |
|---|---|---|
| tokens | CPython's `tokenize` | 416/416 |
| trees, no positions | CPython's `ast` | 416/416 |
| trees, with positions | CPython's `ast` | 416/416 |
| printer round trip | this parser and CPython's | 415/415 |
| `parse` | the reference checker | 392/392 |
| `check` | the reference checker | 392/392 |
| `check-program` | the reference checker | 63/63 |
| `run` | CPython's output | 136/136 |

The conformance suite under `test/conformance/` is the reference's own,
copied verbatim, and the expected answers under `test/golden/` are the
reference's answers. Both are committed, so the suite runs with nothing but
MoonBit and Python 3.

## Development

`just` lists every task, grouped. The ones that matter:

```
just quick        type-check, format, unit tests, layering, conformance
just conform      every oracle, held to its ratchet
just one PATTERN  the tests whose name contains PATTERN, in full
just diffrun      generated programs, compared against CPython
just playground   build the page and serve it on :8000
just publish-dry  what would go to mooncakes, without sending it
```

Regenerating the goldens needs the reference checkout: `just reference-fetch`,
then `just goldens`. Neither runs in CI.

## License

Apache-2.0.
