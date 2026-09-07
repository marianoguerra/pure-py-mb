# pure-py

**PurePy** in MoonBit: a tokenizer and parser for Python 3.12 producing a
CPython-shaped abstract syntax tree, a sieve that rejects the Python PurePy
excludes, a well-formedness checker, an interpreter, a printer that turns the
tree back into Python source, and a command-line tool.

PurePy is a pure functional subset of Python with a small-step operational
semantics and a static well-formedness judgement, specified in
[pure-py/pure-py-spec](https://github.com/pure-py/pure-py-spec). This module is
a port of that specification. The reference checker is the specification for
what `check` decides; CPython is the oracle for what `run` prints.

## Playground

<https://marianoguerra.github.io/pure-py-mb/> — the whole library in a browser
tab, with twenty-seven examples covering what PurePy runs, what a host can
hand it, what is refused before it runs, and what ends without an answer.

The page is a real embedder rather than a demonstration of one: the `host`
module its examples import does not exist in PurePy, and the page supplies it
through the interface [docs/embedding.mbt.md](docs/embedding.mbt.md)
describes.

## Status

The conformance suite passes in full: 983 assertions across four oracles,
compared against the reference's own answers for every one of its sources.
Two more oracles compare the token stream and the parse tree against CPython's
directly, and a third round-trips the printer.

## Installing

```sh
moon add marianoguerra/pure-py
```

A package is the unit of naming, so import the façade for the calls and the
packages whose types you name:

```
import {
  "marianoguerra/pure-py" @purepy,
  "marianoguerra/pure-py/ast",
  "marianoguerra/pure-py/eval",
  "marianoguerra/pure-py/value",
}
```

## Parsing

The tree is CPython's, node for node.

```mbt check
///|
test "parsing" {
  let m = @purepy.parse("print(\"hello\")\n")
  inspect(
    @ast.dump(m),
    content=(
      #|Module
      #|  body:
      #|    Expr
      #|      value:
      #|        Call
      #|          func:
      #|            Name id=print ctx=Load
      #|          args:
      #|            Constant value='hello'
      #|          keywords:
      #|
    ),
  )
}
```

## Deciding whether it is PurePy

Two questions, in order. The sieve asks whether the syntax is within the
subset; the checker asks whether the module is well formed.

```mbt check
///|
test "the sieve rejects what PurePy excludes" {
  let m = @purepy.parse("for x in [1]:\n    print(x)\n")
  match @purepy.sieve(m) {
    Some(d) => {
      inspect(d.message(), content="for loops prohibited")
      // 1 for a form PurePy excludes, 2 for one it plans to accept.
      inspect(d.exit_code(), content="1")
    }
    None => fail("a for loop is not PurePy")
  }
}

///|
test "the checker decides definite assignment and the capture rules" {
  let good = @purepy.parse("x = 1\nprint(x)\n")
  inspect(@purepy.check(good) is None, content="true")
  let bad = @purepy.parse("x = 1\nf = lambda: x\nx = 2\n")
  match @purepy.check(bad) {
    Some(d) =>
      inspect(
        d.message(),
        content="'x' captured by previous statement, reassigned here",
      )
    None => fail("a captured name may not be reassigned")
  }
}
```

## Running

A program is a map from module name to parsed module, with the entry under
`__main__`. `run` answers with everything the program printed and how it
ended.

```mbt check
///|
test "running a program" {
  let modules = Map([
    ("__main__", @purepy.parse("from lib import double\nprint(double(21))\n")),
    ("lib", @purepy.parse("def double(n):\n    return n * 2\n")),
  ])
  let (output, result) = @purepy.run(@purepy.source_tree(modules))
  inspect(result is Finished, content="true")
  inspect(
    output,
    content=(
      #|42
      #|
    ),
  )
}
```

An operation the semantics leaves undefined is reported rather than guessed
at. Python's truthiness is not PurePy's, so a non-boolean condition has no
rule:

```mbt check
///|
test "an undefined operation" {
  let modules = Map([("__main__", @purepy.parse("if 5:\n    print(1)\n"))])
  let (_, result) = @purepy.run(@purepy.source_tree(modules))
  match result {
    Undefined(op) => inspect(op, content="an if condition on int")
    _ => fail("Python's truthiness is not PurePy's")
  }
}
```

## Embedding

PurePy is worth embedding because a guest cannot reach anything the host did
not hand it: no mutation, no ambient authority, no filesystem, no clock. A
host says where output goes, what `sys.argv` is, which modules the guest may
import, and what the functions in them do.

```mbt check
///|
test "a guest calling a function the host supplied" {
  let sink = @eval.Sink::new()
  let host = @eval.Host::new(
    write=fn(t) { sink.write(t) },
    modules=[
      @eval.HostModule::{
        name: "clock",
        members: [("now", @value.host_fn("clock.now"))],
      },
    ],
    call=fn(name, _) {
      match name {
        "clock.now" => Val(Int(1757260800N))
        _ => Stuck("no such host function")
      }
    },
  )
  let modules = Map([
    ("__main__", @purepy.parse("from clock import now\nprint(now())\n")),
  ])
  let tree = @purepy.source_tree(modules)
  // The host goes to the checker too, so `from clock import now` resolves
  // before anything runs.
  inspect(@purepy.check_program(tree, host~) is None, content="true")
  inspect(@purepy.run_with(tree, host) is Finished, content="true")
  inspect(
    sink.text(),
    content=(
      #|1757260800
      #|
    ),
  )
}
```

[docs/embedding.mbt.md](https://github.com/marianoguerra/pure-py-mb/blob/main/docs/embedding.mbt.md)
is the whole surface, with worked examples for output, arguments, host modules, values crossing the
boundary, a host function that answers later rather than now, refusing a guest
before it runs, and bounding one that will not stop.

## Generating Python

`ast` has builders that supply positions, and `write` prints a tree back as
source. Neither links the tokenizer, the parser, the checker or the
evaluator, so a code generator pays for neither.

```mbt check
///|
test "building a tree and printing it" {
  let m = @ast.module_of([
    @ast.Stmt::dataclass("Point", ["x", "y"]),
    @ast.Stmt::expr_stmt(
      @ast.Expr::call(@ast.Expr::name("print"), [
        @ast.Expr::call(@ast.Expr::name("Point"), [
          @ast.Expr::int(1),
          @ast.Expr::int(2),
        ]),
      ]),
    ),
  ])
  inspect(
    @purepy.unparse(m),
    content=(
      #|@dataclass
      #|class Point:
      #|    x: Any
      #|    y: Any
      #|print(Point(1, 2))
      #|
    ),
  )
}
```

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

Exit codes follow the reference's: `0` accepted, `1` a prohibited form or an
abort, `2` a form that is planned and not yet supported, `3` an ill-formed
module, `4` an ill-formed program, and `5` -- this port's own -- an operation
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

## Development

`just` lists every task. The three that matter:

```
just quick        type-check, format, unit tests, layering, conformance
just conform      every oracle, held to its ratchet
just one PATTERN  the tests whose name contains PATTERN, in full
```

The conformance suite under `test/conformance/` is the reference's own, copied
verbatim, and the expected answers under `test/golden/` are the reference's
answers. Both are committed, so the suite runs with nothing but MoonBit and
Python 3 installed. Regenerating them needs the reference checkout:
`just reference-fetch`, then `just goldens`.

## License

Apache-2.0.
