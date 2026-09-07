# pure-py-cli

The `pure-py` command: tokenize, parse, check and run
[PurePy](https://github.com/pure-py/pure-py-spec), a pure functional subset of
Python 3.12.

```sh
moon add marianoguerra/pure-py-cli
```

```
pure-py tokens FILE           one token per line
pure-py dump FILE [--pos]     the abstract syntax tree
pure-py unparse FILE          Python source regenerated from the tree
pure-py parse FILE...         reject what PurePy excludes syntactically
pure-py check FILE...         decide module well-formedness
pure-py check-program MAIN    decide program well-formedness
pure-py run MAIN [ARGS...]    evaluate a program
```

Exit codes follow the reference implementation's, because the conformance
suite compares this binary against it: `0` accepted, `1` a prohibited form or
an abort, `2` a form that is planned and not yet supported, `3` an ill-formed
module, `4` an ill-formed program, and `5` — this port's own — an operation
the semantics leaves undefined.

`check --error-format human` renders a rejection with the source around it:

```
error[purepy::captured-reassignment]: 'x' captured by previous statement, reassigned here
  ╭─[ shadow_captured.py:6:5 ]
  │
4 │ ╭     def g():
5 │ ├         return x
  │ ╰─ 'x' captured here
6 │       x = 6
  │       ──┬──
  │         ╰─ reassigned here
  │
  ├─ help: a closure captured this name, and PurePy has no cell for it to see
  │        a later value; bind a new name instead
  ╰─
```

The library it is built on is
[`marianoguerra/pure-py`](https://mooncakes.io/docs/marianoguerra/pure-py).
Everything is in
[pure-py-mb](https://github.com/marianoguerra/pure-py-mb).

## License

Apache-2.0.
