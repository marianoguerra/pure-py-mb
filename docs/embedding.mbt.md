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

### A site survives a tree the host rewrote

A host that assembles the program it runs -- a notebook prepending a prelude
of imports to a cell, a template wrapping a fragment -- does not lose the
positions of the part a person wrote. Builders make nodes with a `nowhere`
span, `parse` gives the parsed ones their own, and a site is only ever taken
from the node that aborted. So an abort in the written part reports the line
number the WRITER counted, not the line it ended up on:

```mbt check
///|
test "an injected prelude does not move the positions of what was written" {
  // What the person wrote. Three lines, and the third one fails.
  let written = @purepy.parse(
    "rows = {\"a\": 1}\nn = 3\nprint(rows[\"missing\"])\n",
  )
  // What the host puts in front of it: built, not parsed, so `nowhere`.
  let assembled : @ast.Module = {
    body: [@ast.Stmt::assign("cell", @ast.Expr::int(1)), ..written.body],
    span: @basic.nowhere,
  }
  let tree = @purepy.source_tree(Map([("__main__", assembled)]))
  match @purepy.run(tree) {
    (_, Terminated(_, Some(site))) =>
      // Line 3 -- the writer's third line -- although it is the fourth
      // statement of the program that actually ran.
      inspect(site.span.start.line, content="3")
    _ => fail("the missing key is a KeyError")
  }
}
```

This is a property of where sites come from rather than a feature added for
it, but it is the property that makes a position worth having for an embedder
that does not run the source it was handed.

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

## Asking for a larger language

Everything above is PurePy exactly as specified, which is what a host gets for
not asking. A host that wants a slightly larger language asks for a **profile**.

A profile is opt-in, and it stacks: `@profile.core` is PurePy, and each named
profile is the one below it plus features. `@profile.pending()` holds the forms
the specification intends to have and has not settled -- the ones the sieve
refuses today with an issue number: chained `and`/`or` and chained comparisons,
`is` and `is not`, slicing, destructuring assignment, default arguments and
f-strings.

Two of those are drawn narrower than Python's. A **default argument must be a
literal** -- Python evaluates a default once, when the `def` runs, and there is
nowhere in this evaluator to put a once; a literal has no effect and reads no
name, so when it is evaluated cannot be observed and the question stops
existing. An **f-string takes expressions and `!r`, and not a format spec** --
`f"{x:>10}"` is a language of its own, and refusing it by name beats
implementing a piece of it.

It is a set, and it grows. Ask it what it holds -- `Profile::features`, or
`pure-py profiles` -- rather than assuming a form from that table is in it.

`@profile.builtins()` is `pending` and a larger set of builtin functions:
`abs`, `min`, `max`, `sum`, `sorted`, `str`, `int`, `list`, `zip` and the rest.
No syntax changes at all, which makes it the cheapest superset to reason about
and the one an embedder most often wants -- three builtins is a small language
to write in.

None of them coerces. `sum([True])` is 1 in Python only because a bool is an
int there, and `any([1])` is True only because 1 is truthy; PurePy says
neither, so both are undefined here rather than smuggling in a rule the
language refused. `bool` is absent for the same reason: it is Python's
truthiness in a function, and there is no truthiness to put in it.

A profile decides what `builtins` exports, so **the checker and the run must be
handed the same one**. They are two calls and nothing can make that automatic;
give `run` a poorer profile than `check` and a name type-checks and is then not
there.

`@profile.methods()` is the largest, and adds the non-mutating methods of
`str`, `list`, `tuple` and `dict`: `",".join(parts)`, `s.split()`,
`xs.index(x)`, `d.get(k, 0)`.

**It does not make anything mutable.** That is worth saying plainly, because
the absence of methods is what made a list immutable in the first place: the
evaluator has no attribute rule for a builtin value, so `xs.append(1)` was
unreachable rather than forbidden. What the profile adds is a rule for the
CALL, and only for methods that answer with a NEW value. `append`, `extend`,
`insert`, `pop`, `remove`, `sort`, `reverse`, `clear`, `update` and
`setdefault` are absent from the table, and absent is the same undefined
operation an unknown attribute has always been. It could not be otherwise: a
`Value` is an immutable enum with no identity, so a mutating method would have
nothing to write to and nothing that could observe a write.

Methods are also not first class -- `"a".upper()` works and `f = "a".upper`
stays undefined. A bound method would be a new kind of value, needing a `repr`,
an `eq` and an ordering the specification does not define, and it would begin
crossing this boundary: `Host.call` receives `Value`s.

```mbt check
///|
test "a guest written in a superset" {
  let source = "print(True and True and True)\n"
  let m = @purepy.parse(source)

  // PurePy refuses a chained boolean operator, and says which issue it is.
  match @purepy.check(m) {
    Some(d) =>
      inspect(
        d.message(),
        content="chained boolean operator not yet supported (#82)",
      )
    None => fail("PurePy does not have chained boolean operators")
  }

  // A host that opted in gets it.
  let profile = @profile.pending()
  if @purepy.check(m, profile~) is Some(d) {
    fail("refused under a profile that has it: " + d.message())
  }
  let tree = @purepy.source_tree(Map([("__main__", m)]))
  let printed = StringBuilder()
  let host = @eval.Host::new(write=text => printed.write_string(text))
  @purepy.run_with(tree, host) |> ignore
  inspect(printed.to_string(), content="True\n")
}
```

The profile belongs to the calls that decide **what a program may say** --
`sieve`, `check`, `check_program`, and `source_tree_from`, which sieves each
file as it discovers it. It is not part of `Host` and is not an argument to
`run`, for a reason worth saying plainly: a profile is not a mode the runtime
is in. The evaluator already evaluated an n-ary `and` correctly; the sieve
simply never let one through. A profile widens what a host will accept from its
guest, and changes nothing about what the semantics does with what it accepted.

Two things a profile will never do.

It will not lift a **prohibition**. The sieve rejects two kinds of form: one it
plans to have (`not yet supported (#82)`, exit 2) and one it excludes on purpose
(`for loops prohibited`, exit 1). The second list -- `for`, `while`, `try`,
`raise`, `del`, `+=`, item and attribute assignment -- is what makes the
language pure, and it is the list this whole document's guarantees rest on. No
profile reaches it.

And it will not make an undefined operation defined. `1 and 2 and 3` is
accepted under `pending` and is still `Undefined` when it runs, because
PurePy's `and` wants a `bool` and always did.

## Bounding a run

A guest can still loop forever -- PurePy is Turing-complete, and no check can
say otherwise. Two bounds are available, and neither is a substitute for the
other.

`max_depth` bounds recursion, which is how a PurePy program loops. Past it the
run ends undefined rather than overflowing the host's stack, and the limit is
a parameter because the ceiling belongs to the host: a JavaScript engine holds
far fewer frames than a native thread.

**How much fewer is not a detail, and the backend is not the whole of it.**
Evaluation is `async`, so that a host function may suspend, and the transform
spends roughly a dozen host frames per guest call. Measured by recursing at
increasing depths until the host's own stack went, over a program with a small
expression in each frame:

| how the evaluator is called | debug | release | release + `-Oz` |
|---|---|---|---|
| `native`, as a process | about 1050 | over 6000 | — |
| `wasm-gc` under `moon test` | about 26 | about 130 | — |
| `wasm-gc` as a bare export | about 370 | about 600 | about 780 |

The build matters, as you would expect. **The caller matters more.** The same
`wasm-gc` module holds fourteen times as many guest calls entered directly as
it does under a test harness, because whatever is already on the stack is
stack the guest does not get. An embedder who measures under `moon test` and
ships a page is measuring the wrong number, and so is one who does the
reverse.

So the default is per backend -- 500 on `native`, **12** on the three that run
on a JavaScript engine -- and 12 is the tightest of the rows above rather than
a guess at yours. It is the configuration a consumer reaches without choosing
it: `moon test --target wasm-gc` on a debug build, where the ceiling really is
about 26.

Twelve is small, and it is deliberate. On a native thread an overflow is a
crash the developer sees; on a JavaScript engine it is a `RangeError` that no
MoonBit code can catch, and in a browser it takes the tab. `a call stack
deeper than 12` is an ordinary termination that a page can render, a model can
read and a program can be rewritten around.

**It is a floor, not a recommendation. Measure your own and pass
`max_depth`.** Call your module the way your application calls it -- same
build, same optimizer, same depth of caller beneath it -- at increasing depths
until the engine throws, and take about a third. Do it more than once at each
depth: the answer depends on what is already on the stack, so a single try can
disagree with itself. The playground does this and passes 250, against a
measured ceiling of about 780 for the release module it actually ships.

Pass it at every call site, including the ones where the default looks right
today. 0.5.0 moved this default from 500 to 12 on three backends, and that
release changed no type: a call site that had dropped its `max_depth` compiled
clean and landed on a number two orders of magnitude away from the one it was
written against. A default that can move under a release the type checker
approves of is the argument for passing it explicitly, not against it -- and a
local default that happens to equal the library's is a coincidence of
arithmetic, not agreement about what the number means.

`tools/depth-probe.mjs` in this repository is that measurement, and it will
sweep any wasm module exporting `analyze` -- point it at yours. `just
depth-probe` runs it over the page's own.

**And the engine is an axis of its own.** Node is V8, so a Node figure is not
a browser figure -- it is a Chromium figure. The playground's release module,
same probe, same five tries per depth, in guest calls:

| engine | tail | accumulating | nested |
|---|---|---|---|
| V8 (Node 24) | 1488 | 992 | 781 |
| V8 (Chromium 152, headless) | 1500 | 987 | 783 |
| SpiderMonkey (Firefox 155, headless) | 3687 | 2456 | 1965 |

The shapes do not order the way their names suggest and the spread between
them is a factor of two, which is why the worst one is what a limit should be
set against.

**And "where you call it from" is not a syntactic category.** What varies is
who RESUMED you: a promise settled by I/O resumes on the stack of whatever
drained the queue after that operation, while a timer callback starts near the
bottom. The same `await` keyword gives different answers depending on what the
promise was waiting for. So the probe sweeps each shape from several positions
and reports all of them. In Node, over the playground's release module:

| shape | top level | after I/O | fresh task |
|---|---|---|---|
| tail | 1487 | 1463 | 1488 |
| accumulating | 991 | 975 | 992 |
| nested | 781 | 768 | 781 |

Small -- under two per cent -- but consistent in direction and present on
every shape. In Chromium 152 and Firefox 155 the same comparison shows no gap
at all, and an embedder measuring a different module reports a much larger one
on one shape in one engine. None of that resolves into a rule, which is the
point: measure from the position your application actually calls from, and
report more than one so that an engine's behaviour can be told apart from the
harness's own mistake.

The columns are three positions and not a spectrum. Module top level in
particular is not reliably the shallow one: here it is within a call of the
timer, and the embedder above measures it a third TIGHTER than the timer on
the same shape. A probe that runs at module top level and reports one number
is not measuring the roomiest stack a caller can arrange, it is measuring one
arbitrary position that happens to be neutral here and pessimistic there.

`just depth-probe-browser firefox` is that measurement, and `chromium` the
other; with no argument it serves the page for an engine neither of us
automated. It also asks the question that actually decides whether a page
survives -- does the module we serve hold at its own limit, and report rather
than throw past it -- and for the playground's 250 the answer in both engines
is yes.

What is NOT safe to carry away is the ratio. An embedder measuring a different
module got SpiderMonkey at a third of V8 where this one gets it at two and a
half times, on the same worst shape and the same method. Which engine binds is
a property of the module, so **measure your own module in the engines you ship
to** -- and if you ship to WebKit or to a phone, measure there, because neither
of us could.

**A measured ceiling belongs to a VERSION of this library, not to PurePy.**
How many host frames a guest call costs is an implementation detail that
moves: the `async` transform in 0.3.0 spent about a dozen of them where there
had been one, and the abort sites in 0.4.0 spent a little more again. Probed
with `def down(n): return 0 if n == 0 else 1 + down(n - 1)` on `wasm-gc`
debug, the ceiling went from about 40 guest calls to about 38.

Two calls is nothing; the direction is the point. A number measured against
one version can sit above the ceiling in the next, and that regression does
not appear as a failing test -- it appears in production as the host's own
stack overflow, which on a JavaScript engine is a `RangeError` no MoonBit
code can catch and in a browser takes the tab. **Re-measure after upgrading**,
and leave the note in the code that says why the number is what it is.

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
| how deep it may recurse | `max_depth` | 500 native, 12 on a JavaScript engine |
| how large a language the guest may use | `profile`, on every call that decides what a program may say AND on `run` | `@profile.core`: PurePy |

And everything a host does NOT have to defend against, because the language
has no way to express it: mutation of a guest value, a guest reaching a name
it was not given, a guest holding a reference to host memory, a callback the
host did not ask for, or a module appearing that was not in the tree.
