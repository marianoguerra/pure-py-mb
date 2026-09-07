# Embedding PurePy

PurePy is a pure language, and that is why it is worth embedding: a guest
program cannot reach anything the host did not hand it. There is no mutation,
no ambient authority, no filesystem, no clock and no way to install a callback
the host does not see. A guest can compute, and it can call what the host gave
it.

This document is the whole of the embedding surface. Its examples are
compiled and run as tests, so nothing here is aspirational.

```
import {
  "marianoguerra/pure-py" @purepy,
  "marianoguerra/pure-py/eval",
  "marianoguerra/pure-py/value",
}
```

## The shape of it

Four steps, and the middle two are where a host does its work.

1. **Parse** each module the guest is made of.
2. **Describe the host**: where output goes, what `sys.argv` is, which modules
   the guest may import, and what the functions in them do.
3. **Check** the program against that host. The semantics is defined for
   well-formed programs, so this is not optional.
4. **Run** it.

## A run with no host at all

The smallest embedding: a program that can only compute and print.

```mbt check
///|
test "the smallest embedding" {
  let modules = Map([
    (
      "__main__",
      @purepy.parse(
        "def sum_to(n):\n" +
        "    if n == 0:\n" +
        "        return 0\n" +
        "    return n + sum_to(n - 1)\n" +
        "print(sum_to(3))\n",
      ),
    ),
  ])
  let tree = @purepy.source_tree(modules)
  assert_true(@purepy.check_program(tree) is None)
  let (output, result) = @purepy.run(tree)
  inspect(result is Finished, content="true")
  inspect(
    output,
    content=(
      #|6
      #|
    ),
  )
}
```

Note what the guest could not have done. There is no `import os`, because
`os` is not a module it was given; no `open`, because the only names in scope
are `print`, `len` and `range`; and no way to reach the host's memory, because
a `Value` is a value.

## Output, as it happens

`run` collects the transcript, which is convenient and wrong for anything
long-running. `Host` takes a `write` that is called once per `print`, while
the run is still going, and `run_with` uses it.

```mbt check
///|
test "output arrives one print at a time" {
  let lines : Array[String] = []
  let host = @eval.Host::new(write=fn(text) { lines.push(text) })
  let modules = Map([
    ("__main__", @purepy.parse("print(1)\nprint(2, 3)\nprint()\n")),
  ])
  let result = @purepy.run_with(@purepy.source_tree(modules), host)
  inspect(result is Finished, content="true")
  // One call per `print`, in order, each ending in the newline `print` adds.
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "1\n")
  assert_eq(lines[1], "2 3\n")
  assert_eq(lines[2], "\n")
}
```

A host that streams to a terminal writes each piece out; one that drives a
progress bar counts them; one that has seen enough can stop reading. What it
cannot do is stop the run from inside `write` -- there is no mechanism for
that, deliberately, because a `write` that could abort would make output an
effect the semantics does not model.

## Giving the guest arguments

`sys.argv` is whatever the host says it is. `argv[0]` is the program's own
name, as in Python.

```mbt check
///|
test "sys.argv" {
  let sink = @eval.Sink::new()
  let host = @eval.Host::new(write=fn(t) { sink.write(t) }, argv=[
    "report.py", "--since", "monday",
  ])
  let modules = Map([
    (
      "__main__",
      @purepy.parse("import sys\nprint(len(sys.argv), sys.argv[1])\n"),
    ),
  ])
  @purepy.run_with(@purepy.source_tree(modules), host) |> ignore
  inspect(
    sink.text(),
    content=(
      #|3 --since
      #|
    ),
  )
}
```

## Giving the guest functions

This is the part that makes embedding worth doing. A host declares a module,
puts values in it, and answers calls to the functions among them.

A host function is a NAME, not a closure: `@value.host_fn("clock.now")` is a
value the guest can call, and the host's `call` is handed that name and the
arguments. Keeping it a name rather than a closure is what lets a `Value` stay
comparable, printable, and free of the host's types.

```mbt check
///|
test "a host module with a function in it" {
  // What the host exposes: two constants and two functions.
  let store = @eval.HostModule::{
    name: "store",
    members: [
      ("VERSION", @value.Value::Str("1.4")),
      ("LIMIT", @value.Value::Int(100N)),
      ("get", @value.host_fn("store.get")),
      ("put", @value.host_fn("store.put")),
    ],
  }
  // The host's own state, which the guest can only reach through the two
  // functions above.
  let rows : Map[String, String] = Map([("greeting", "hello")])
  let sink = @eval.Sink::new()
  let host = @eval.Host::new(write=fn(t) { sink.write(t) }, modules=[store], call=fn(
    name,
    args,
  ) {
    match (name, args) {
      ("store.get", [Str(key)]) =>
        match rows.get(key) {
          Some(v) => Val(Str(v))
          // A missing key is Python's KeyError, which is one of the
          // terminations the semantics already has a name for.
          None => Aborts(KeyError)
        }
      ("store.put", [Str(key), Str(v)]) => {
        rows[key] = v
        Val(None)
      }
      // Anything else: an operation the semantics does not cover. The run
      // stops and says so, rather than guessing.
      _ => Stuck("store." + name + " called with the wrong shape")
    }
  })
  let modules = Map([
    (
      "__main__",
      @purepy.parse(
        "from store import get, put, VERSION\n" +
        "put(\"greeting\", \"hei\")\n" +
        "print(VERSION, get(\"greeting\"))\n",
      ),
    ),
  ])
  let tree = @purepy.source_tree(modules)
  // The host is passed to the CHECKER too, so `from store import get`
  // type-checks before it runs.
  assert_true(@purepy.check_program(tree, host~) is None)
  inspect(@purepy.run_with(tree, host) is Finished, content="true")
  inspect(
    sink.text(),
    content=(
      #|1.4 hei
      #|
    ),
  )
  // The host's own state changed, because the host changed it.
  assert_eq(rows.get("greeting"), Some("hei"))
}
```

The host is given to the checker as well as to the evaluator, and it must be
the same one. The checker needs the member NAMES so that
`from store import get` resolves; it never sees the values, because what a
host function is is none of its business.

## What a host function may answer

`call` returns an `Outcome`, and there are exactly three kinds:

| answer | what it means | what the guest sees |
|---|---|---|
| `Val(v)` | it worked | the value |
| `Aborts(k)` | it failed the way Python fails | the run ends with that termination, sited at the call |
| `Stuck(why)` | the host cannot answer | the run ends undefined, with `why` |

The terminations are the semantics' own: `TypeError`, `IndexError`,
`KeyError`, `ZeroDivisionError`, `AttributeError`, `AssertionError` and
`SystemExit`. A host that wants to say "no such row" says `KeyError`, and the
guest's `print` never runs.

```mbt check
///|
test "a host function that fails" {
  let host = @eval.Host::new(
    modules=[
      @eval.HostModule::{
        name: "db",
        members: [("row", @value.host_fn("db.row"))],
      },
    ],
    call=fn(_, _) { Aborts(KeyError) },
  )
  let modules = Map([
    ("__main__", @purepy.parse("from db import row\nprint(row(\"missing\"))\n")),
  ])
  let tree = @purepy.source_tree(modules)
  assert_true(@purepy.check_program(tree, host~) is None)
  match @purepy.run_with(tree, host) {
    Terminated(k, site) => {
      inspect(k.to_text(), content="KeyError")
      // The host had no position to give -- it is not running guest source --
      // so the site is the CALL, in the guest, that asked for the missing row.
      inspect(site.unwrap().to_display(), content="__main__:2:6")
    }
    _ => fail("a missing row is a KeyError")
  }
}
```

A host that does not recognise a call gets the default, which is `Stuck`. That
is the honest answer for anything the semantics does not cover, and it is
reported the same way as PurePy's own undefined operations.

## Where a run aborted

`Terminated` carries a `Site` beside the termination kind: the module the
guest was running in, and the span within it. It is the INNERMOST expression
that aborted -- in `a + f(b)`, the call and not the sum -- and the module is
the one the failing code was WRITTEN in, not the one that imported it.

The kind and the site are separate on purpose. The specification fixes which
kind a run yields and leaves reporting open: *"An implementation must agree on
which kind a run yields, though how it reports one is not prescribed"*
(`operational-semantics.tex`). So a `Site` never changes a `Termination`, two
runs that abort in different places still agree on the kind, and a host that
matches on `Terminated(KeyError, _)` keeps working.

```mbt check
///|
test "where a run aborted, across two modules" {
  let modules = Map([
    ("helper", @purepy.parse("def pick(d):\n    return d[\"missing\"]\n")),
    (
      "__main__",
      @purepy.parse("from helper import pick\nprint(pick({\"k\": 1}))\n"),
    ),
  ])
  let tree = @purepy.source_tree(modules)
  assert_true(@purepy.check_program(tree) is None)
  match @purepy.run(tree) {
    (_, Terminated(k, Some(site))) => {
      inspect(k.to_text(), content="KeyError")
      // Line 2 of `helper`, not of `__main__`: the subscript that failed is
      // written in the module that defines `pick`.
      inspect(site.to_display(), content="helper:2:11")
    }
    _ => fail("the missing key is a KeyError")
  }
}
```

A site is `None` when there is no guest position to give: an abort a host
returned before any guest expression was entered, or one from a tree built by
a code generator, whose nodes carry no source.

## A host function that answers later

`call` is `async`, so those three answers are what a host may say, and *when*
is a separate question. A host that has to read a socket, await a promise or
ask a person suspends: it takes the continuation it is handed, returns, and
calls it when the answer arrives.

The run parks where it stood -- mid-expression, inside a call, anywhere -- and
resumes on the value supplied. **The guest cannot tell.** PurePy has no
`await` and no concurrency; a call that answered a second later is a call that
answered.

What changes is the EMBEDDER's side, because a synchronous caller cannot wait
for something that has not happened. `run_with` therefore returns when the run
ends *or* when it parks, whichever comes first, and says which:

| | return value | `done` |
|---|---|---|
| nothing suspended | the answer | already called, with the answer |
| a call parked | `Suspended` | called later, from the host's continuation |

```mbt check
///|
/// The compiler's own suspension primitive, which a host declares once: it
/// hands `register` the continuation of the parked run and returns whatever
/// that continuation is eventually called with.
async fn[T] suspend(register : ((T) -> Unit) -> Unit) -> T noraise = "%async.suspend"
```

```mbt check
///|
test "a host function that answers later" {
  // The host's queue of parked runs. A real one would hold these until a
  // socket, a timer or a person produced the answer.
  let waiting : Array[(@value.Value) -> Unit] = []
  let sink = @eval.Sink::new()
  let host = @eval.Host::new(
    write=t => sink.write(t),
    modules=[
      @eval.HostModule::{
        name: "slow",
        members: [("fetch", @value.host_fn("slow.fetch"))],
      },
    ],
    call=(_, _) => Val(suspend(answer => waiting.push(answer))),
  )
  let modules = Map([
    (
      "__main__",
      @purepy.parse("from slow import fetch\nprint(fetch() + fetch())\n"),
    ),
  ])
  let tree = @purepy.source_tree(modules)
  let mut ended : @eval.RunResult? = None
  // Both calls are operands of one addition, so the run parks twice inside a
  // single expression.
  let returned = @purepy.run_with(tree, host, done=r => ended = Some(r))
  inspect(returned is Suspended, content="true")
  inspect(ended is None, content="true")
  // The host's work finishes and it resumes the run, which parks again in the
  // second call and then finishes on the second answer.
  waiting.pop().unwrap()(Int(2N))
  waiting.pop().unwrap()(Int(40N))
  inspect(ended is Some(Finished), content="true")
  inspect(
    sink.text(),
    content=(
      #|42
      #|
    ),
  )
}
```

An embedder that is itself asynchronous needs none of this. `Interp::run` is
an `async` function, so a host running under `moonbitlang/async` -- or driving
its own loop on the JavaScript or wasm side -- can simply await it, and a
parked host call is an awaited one.

Two things suspension does NOT bring. It is not concurrency: there is one
guest, it is at exactly one point, and the host holds the only continuation.
And it is not a scheduler: a continuation that is dropped is a run that never
finishes, with no timeout and no cleanup -- if a host can give up on its own
work, it answers `Stuck` instead of walking away.

## Passing values across

A `Value` is data. Building one and reading one back are the same few
constructors either way.

```mbt check
///|
test "values in and out" {
  let seen : Array[String] = []
  let host = @eval.Host::new(
    modules=[
      @eval.HostModule::{
        name: "host",
        members: [
          (
            "config",
            @value.Value::Dict([
              ("retries", @value.Value::Int(3N)),
              ("names", @value.Value::List([Str("a"), Str("b")])),
            ]),
          ),
          ("record", @value.host_fn("host.record")),
        ],
      },
    ],
    call=fn(_, args) {
      // Reading a guest value: match on it. `repr` gives Python's own text,
      // and is `None` for a closure, which has no printable form.
      for a in args {
        seen.push(
          match a.repr() {
            Some(t) => t
            None => "<" + a.kind_name() + ">"
          },
        )
      }
      Val(None)
    },
  )
  let modules = Map([
    (
      "__main__",
      @purepy.parse(
        "from host import config, record\n" +
        "record(config[\"retries\"], config[\"names\"], {\"k\": 1.5}, None)\n",
      ),
    ),
  ])
  let tree = @purepy.source_tree(modules)
  assert_true(@purepy.check_program(tree, host~) is None)
  @purepy.run_with(tree, host) |> ignore
  assert_eq(seen, ["3", "['a', 'b']", "{'k': 1.5}", "None"])
}
```

## Refusing a guest before it runs

A guest that is not PurePy, or not well formed, is refused with a message and
a position. This is the half of embedding that a sandbox usually cannot do:
the answer comes before anything has run.

```mbt check
///|
test "a guest that is refused" {
  // Not PurePy: a `while` loop.
  let looping = Map([("__main__", @purepy.parse("while True:\n    print(1)\n"))])
  match @purepy.check_program(@purepy.source_tree(looping)) {
    Some(d) => inspect(d.message(), content="__main__: while loops prohibited")
    None => fail("a while loop is not PurePy")
  }
  // PurePy, but not well formed: a name that is not definitely assigned.
  let unassigned = Map([
    ("__main__", @purepy.parse("c = True\nif c:\n    x = 1\nprint(x)\n")),
  ])
  match @purepy.check_program(@purepy.source_tree(unassigned)) {
    Some(d) =>
      inspect(d.message(), content="__main__: 'x' is not definitely assigned")
    None => fail("x is assigned in one branch only")
  }
}
```

## Bounding a run

A guest can still loop forever -- PurePy is Turing-complete, and no check can
say otherwise. Two bounds are available, and neither is a substitute for the
other.

`max_depth` bounds recursion, which is how a PurePy program loops. Past it the
run ends undefined rather than overflowing the host's stack, and the limit is
a parameter because the ceiling belongs to the host: a JavaScript engine holds
far fewer frames than a native thread.

```mbt check
///|
test "an unbounded recursion is reported, not crashed into" {
  let modules = Map([
    ("__main__", @purepy.parse("def f(n):\n    return f(n)\nprint(f(1))\n")),
  ])
  match @purepy.run(@purepy.source_tree(modules), max_depth=64) {
    (_, Undefined(why)) => inspect(why, content="a call stack deeper than 64")
    _ => fail("f calls itself forever")
  }
}
```

There is no instruction budget: a guest that loops without recursing -- a
comprehension over a long range, say -- runs until it is done. A host that
needs a wall-clock bound runs the guest on a thread it can abandon, or on a
backend where it can.

## Where the guest's code comes from

A `SourceTree` is a value: a map from module name to parsed module, with the
entry under `__main__`. Nothing about it touches a filesystem, so a host whose
guest code lives in a database, a zip file or a text box builds one directly,
as every example above does.

`source_tree_from` is the other way, for a host whose guest really is a
directory of files. It takes a path and discovers what is beside it.

## The whole surface

Everything a host can supply, in one place:

| what | how | default |
|---|---|---|
| where output goes | `Host::new(write=...)` | dropped |
| `sys.argv` | `Host::new(argv=...)` | empty |
| importable modules | `Host::new(modules=[HostModule::{...}])` | none |
| what those functions do | `Host::new(call=...)` | `Stuck` |
| the guest's code | `source_tree` or `source_tree_from` | — |
| what those functions do, later | `Host::new(call=...)` and `run_with(done=...)` | answers now |
| how deep it may recurse | `max_depth` | 500 |

And everything a host does NOT have to defend against, because the language
has no way to express it: mutation of a guest value, a guest reaching a name
it was not given, a guest holding a reference to host memory, a callback the
host did not ask for, or a module appearing that was not in the tree.
