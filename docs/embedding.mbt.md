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

A value with no printable form -- a closure, a module, a class, a builtin --
answers `None` to both, because Python prints an address no implementation can
reproduce. `kind_name` names the kind, and for a builtin `Primitive::name`
names the one it is:

```mbt check
///|
test "naming a value that cannot be printed" {
  let host = @eval.Host::new(modules=[
    { name: "host", members: [("search", @value.host_fn("search"))], },
  ])
  // Whatever the host put in its own module, read back by name.
  let members = host.modules.get("host").unwrap()
  match members.get("search").unwrap() {
    Prim(p) => {
      inspect(p.name(), content="search")
      inspect(@value.Value::Prim(p).repr() is None, content="true")
      inspect(@value.Value::Prim(p).kind_name(), content="builtin")
    }
    _ => fail("host_fn makes a primitive")
  }
}
```

`Primitive::name` answers the name a member is bound under -- `floor` for
`math.floor`, and for a host function whatever the host registered it as --
which is enough to render `<builtin search>` where Python would print an
address. It is the same table `Interp::predefined` binds from, read back, and
a test in the library says so, so a builtin added by a later profile does not
leave an embedder spelling out a list that has quietly grown.

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
say otherwise. `max_depth` is the bound, and it bounds recursion, which is how
a PurePy program loops.

**It is a policy and not a measurement.** The evaluator keeps its continuation
on the heap -- `lib/eval/machine.mbt` -- so the host's stack does not grow with
the guest's recursion, and one host frame drives a guest twenty thousand calls
deep on every backend. `max_depth` therefore answers a question about your
application: how deep may a guest go before you would rather stop it? It used
to answer a question about the host -- how deep can a guest go before the
engine throws a `RangeError` no MoonBit code can catch -- and that question is
gone.

Past the limit the run ends undefined, with a message a page can render and a
program can be rewritten around:

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

And depth costs memory rather than stack, so a large limit buys a large array
of frames instead of a crash:

```mbt check
///|
test "a guest may recurse as deep as it is allowed to" {
  let source =
    #|def count(n):
    #|    if n == 0:
    #|        return 0
    #|    return 1 + count(n - 1)
    #|
    #|print(count(20000))
    #|
  let modules = Map([("__main__", @purepy.parse(source))])
  let (out, result) = @purepy.run(
    @purepy.source_tree(modules),
    max_depth=100000,
  )
  inspect(result is Finished, content="true")
  inspect(out, content="20000\n")
}
```

Twenty thousand levels, none of them tail calls -- `1 + count(n - 1)` has work
left to do at every one -- on `wasm`, `wasm-gc`, `js` and `native` alike.

**The default is 10000, on every backend.** It used to be two numbers -- 500 on
a native thread and 12 on the three that run on a JavaScript engine -- because
the host's stack was the real limit and a JavaScript engine's is two orders of
magnitude smaller. There is nothing left for the backend to decide, so there is
one number, and it is a policy rather than a measurement: deep enough that no
reasonable program meets it, shallow enough that a runaway stops in an array of
ten thousand frames rather than in an out-of-memory.

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
| how deep it may recurse | `max_depth` | 10000, on every backend |
| how large a language the guest may use | `profile`, on every call that decides what a program may say AND on `run` | `@profile.core`: PurePy |

And everything a host does NOT have to defend against, because the language
has no way to express it: mutation of a guest value, a guest reaching a name
it was not given, a guest holding a reference to host memory, a callback the
host did not ask for, or a module appearing that was not in the tree.
