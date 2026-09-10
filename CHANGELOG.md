# Changelog

## 0.10.0 — 2026-09-10

One addition: `redefined`, on `Host`, which replaces a member of a module
the specification predefines. Additive, so an 0.9.1 consumer upgrades by
changing the version.

### A host can redefine what the specification predefines

`Host.write` is handed text: `str` of each argument, joined by a space,
terminated by a newline. That is the right shape for a terminal and the wrong
one for anything that wanted the arguments, because by then they are gone. An
embedder capturing what a guest prints -- a notebook rendering a value, a test
harness collecting them -- had one way to get at them, and it was a trick:
prepend `from cap import print` to the guest's body, so a host function shadows
the binding. It mutates a tree nobody wrote, it needs a module invented for the
checker, and the guest can see around it -- `from builtins import print`
reaches the real one, and so does `import builtins`.

`Host::new(redefined=...)` replaces the member instead of shadowing it. A key
is a predefined module's name, a dot, and the member within it, so `sys.exit`
and `math.pi` are the same field:

```
let host = @eval.Host::new(
  redefined=[("builtins.print", @value.host_fn("cap.print"))],
  call=(_, args) => { captured.push(args); Val(None) },
)
```

**It invents nothing.** The value is an ordinary `host_fn`, answered by the
`call` a host already writes, so `async`, suspension, `Val`/`Aborts`/`Stuck`
and an abort sited at the guest's call all work because they already did. There
is no second way for host code to answer a guest call, and nothing new to
learn.

**There is one `print`.** `print(1)`, `from builtins import print` and
`import builtins` all reach the redefinition. That is the whole difference
between a binding and a shadow, and it is what the trick could not claim.

**The checker hears nothing about it.** Every predefined member is typed `TT`,
so a redefinition moves the value behind a name the checker already had:
`check_program` takes no new argument, the goldens do not move, and a redefined
`print` may take any number of arguments -- nothing ever said how many it took.

**And the cost, which is real.** This is the one part of a host that changes
what a program MEANS. A run under any other part is a run CPython is the oracle
for; a run that redefines a builtin is not. It is the admission the profiles
already make, and the answer is the same: own the divergence rather than
pretend the oracle still applies.

Two things come with it. `@value.print_text` is the text `print` would have
written, so a host that wants the transcript beside the values does not write
the join a second time and drift from CPython on the first argument that
renders unusually -- `print` itself now calls it, so there is one
implementation rather than two. And `Host::unknown_redefinitions` answers with
the keys that name nothing: a redefinition is matched by NAME, so
`builtins.pirnt` lands in no environment and the run proceeds as though the
host had said nothing at all. That silence is the failure mode this feature
has, and it is one assertion to break it.

Asked for by an embedder who was about to shadow `print`.

## 0.9.1 — 2026-09-09

Nothing in the API moved and no `.mbti` changed. This is the release that
builds: 0.9.0 does not, against either the current compiler or the current
`moonbitlang/x`, and a consumer resolving both for the first time gets the
newest of each. An 0.9.0 consumer upgrades by changing the version.

### `moonbitlang/x` 0.5.4, whose `read_dir` answers with a view

`@fs.read_dir` returned `Array[String]` and returns `ArrayView[String]` since
x 0.5.2 -- the one break in the three releases between 0.5.1 and 0.5.4 that
reaches this library. One call site, `program`'s directory walk, which sorts
what it gets so a `SourceTree` is the same on every platform rather than in
the filesystem's own order. Sorting is in place and a view is not a place, so
the listing is copied first.

**This is why the release exists.** `moon.mod` states a minimum and not a pin,
so pure-py 0.9.0 resolved against x 0.5.2 or later is a type error in a
library the consumer did not touch, and every new consumer resolves the
newest. `marianoguerra/error-report` is at 0.1.0 and 0.1.0 is the latest, so
it does not move.

### `%async.suspend` is declared `nocancel` now

A host that answers later declares the compiler's suspension primitive itself
-- the embedding guide has the line, and `docs/embedding.mbt.md` is where an
embedder copies it from. moonc grew cancellation, `%async.suspend` carries a
`nocancel` effect in its declared type, and the old spelling no longer
compiles. It is `noraise + nocancel` in the guide and in this library's own
suspension tests.

`nocancel` is true of this library rather than a formality: it never abandons
a parked run, so a continuation it hands out is one that will be called. The
guide says so, beside the line.

Nothing in the shipped package declared one, so an 0.9.0 consumer who is not
suspending is unaffected. One who is has the fix in a document rather than in
a package: the guide is in the repository, which is the copy they read.

### What `--deny-warn` now rejects

`Array::new()` is deprecated in favour of `Array(capacity=...)`, and a
deprecation is an error under the flag CI gates on, so CI had been red at its
first step since the 2026-09-07 toolchain. Two calls, both wanting an empty
array, both now `Array()`. Behind that: `lib/token` imported itself for a test
directory with no test files, scaffolding left by the three-module split,
unreadable as a warning until the package compiled again.

### And so do the upgrade notes

Same defect, one document over, found by running the same check twice instead
of once. This file is in the root module and the root module is never
published, so a consumer who upgraded 0.6.0 to 0.7.0 met a compile error from
three removed functions with nothing in the package to explain it. The shipped
README now links here, in the section about installing, where somebody about to
change a version number is looking.

### The two bounds reach a consumer who never opens the repository

`docs/` is in the root module, which is never published, so everything written
about bounding a run lived somewhere a registry consumer does not go.
`lib/README.mbt.md` -- the one document that ships -- mentioned neither
`max_depth` nor `max_steps`, and one of its two links to the guide was
relative, which resolves for a reader of the repository and is dead for
everyone else.

It now carries both bounds, what runs away past each, that the defaults are
backstops rather than settings, and that a host with a person waiting should
measure its own workload rather than copy a figure. Both links are absolute.

### How to choose `max_steps`

0.9.0 shipped the bound with a default and no advice, so the first embedder to
set one had to work out the method themselves. The guide now carries it: measure
your heaviest genuine workload, take a multiple, then measure what exhausting
the budget costs in the slowest build and caller you actually ship -- because
that pause is what a runaway buys you, and a budget which is itself a freeze has
not prevented one.

Deliberately no rate. What a step costs depends on the build, the backend and
what the guest is doing, and a number measured in one configuration and carried
into another is the mistake the recursion ceiling took three releases to stop
making. The method transfers; the figures do not.

## 0.9.0 — 2026-09-08

One addition: `max_steps`, on `run` and `run_with`. Additive, so an 0.8.0
consumer upgrades by changing the version.

### `max_steps`: the runaway that does not recurse

PurePy has no loops, so for a long time recursion looked like the only way to
run forever and `max_depth` was enough. It is not, and three shapes get past
it, none of which calls anything:

  * a comprehension loops without recursing -- `[y for y in xs for z in xs]`;
  * `range(10 ** 9)` builds a whole sequence from a NUMBER, in one move;
  * `[0] * 10 ** 9` builds one by repetition, also in one move.

On a browser tab each is a page that stops answering, with nothing to read and
nothing to interrupt. It was the last way a guest could take the tab: with the
machine, recursion is not one any more.

`max_steps` bounds all three. A step is one move of the machine, charged in the
driver loop -- the one place every move passes through, which is a thing the
recursive walk did not have. The two that build in a single move are charged
for what they build BEFORE they build it, so the answer is a limit that was
reached rather than a host that ran out of memory.

The default is 100000000: far more than any program a person waits on, few
enough that a runaway ends in an answer. The playground passes 2000000 and
hmtp's notebook will want less again.

**It is deterministic, and a wall-clock timeout would not be.** Two runs of the
same program over the same host answers stop in the same place, so a guest that
hits the limit hits it reproducibly and a test can pin it -- there is one that
does. Stopping a run because a person pressed Cancel is a different feature and
this is not it.

Asked for by an embedder, as the last one standing.

## 0.8.0 — 2026-09-08

One addition, and nothing else: `@value.Primitive::name`. Additive, so an
0.7.0 consumer upgrades by changing the version.

### `Primitive::name`, so an embedder stops keeping a fourth table

A `Prim` has no printable form -- `str` and `repr` answer `None`, because
Python prints an address no implementation can reproduce -- so a host that
wants to show something in its place has to name it, and until now that meant
spelling out all thirty. That was a fourth table agreeing with the three
`predefined_wbtest.mbt` already keeps in line, and the only one of the four
this library could not test: a consumer with a list of thirty names has no way
to learn that a thirty-first arrived.

`pub fn Primitive::name(Self) -> String` answers the name a member is bound
under -- `floor` for `math.floor`, and for a host function whatever the host
registered it as. There is no fourth table now: `Interp::predefined` is the one
that decides, and a test reads it back, asserting under every profile that
whatever is bound answers with the name it is bound under. Breaking one name
fails it by member.

Asked for by an embedder; thank you.

## 0.7.0 — 2026-09-08

The evaluator no longer spends host stack on a guest's recursion, so the
recursion limit is a policy instead of a measurement: **10000 on every
backend**, where it was 500 on a native thread and 12 on the three that run on
a JavaScript engine.

**Three functions left the API**, all helpers of the recursive walk that is
gone: `@eval.Interp::eval_exprs`, `eval_bound` and `eval_quals`. `eval_expr`,
`eval_body`, `eval_seq` and `apply` keep their signatures and are entry points
into the machine, so an embedder that uses the facade -- `run`, `run_with`,
`check` -- has nothing to change.

### The evaluator is a machine with an explicit stack

`lib/eval/machine.mbt` replaces the recursive tree walk. The continuation is a
value now -- an `Array[Frame]` on the heap -- and the driver loop is ONE host
frame however deep the guest goes.

PurePy has no loops, so recursion is the only iteration a guest has, and a
tree-walking evaluator spent host stack in proportion to how deep the guest
went: about a dozen host frames per guest call once MoonBit's `async` transform
was counted. That is why `default_max_depth` was 12 on the backends that run on
a JavaScript engine, why it had to be measured rather than chosen, and why it
had to be RE-measured whenever the evaluator changed shape -- adding one match
arm to `eval_expr` cost four frames of guest depth in this same release,
because a frame is sized by the whole function.

None of that is true any more. Twenty thousand levels of NON-tail recursion --
`1 + count(n - 1)`, with work left to do at every level -- run on `wasm`,
`wasm-gc`, `js` and `native` alike. `max_depth` still bounds a runaway, and now
it answers a question about the application rather than about the engine.

It is also closer to what is being ported: PurePy is specified as a small-step
operational semantics, and a machine with an explicit continuation is that
semantics written down. The recursive walk was the paraphrase.

`Ctl` has five states and `Frame` about twenty, and three things still recurse
because none of them can recurse WITH the guest: patterns are bounded by their
own nesting, a `MatchValue` head is a qualified name with no call in it, and
imports are bounded by the module graph and already guarded against cycles.

**The defaults are unchanged** -- 500 on `native`, 12 on the rest -- and are now
conservative leftovers rather than measurements. Choosing them is a one-line
decision that wants making on its own.

Three functions left the API with the walk that needed them:
`Interp::eval_exprs`, `Interp::eval_bound` and `Interp::eval_quals`.
`eval_expr`, `eval_body`, `eval_seq` and `apply` keep their signatures and are
entry points into the machine.

### One recursion limit, and the probe is gone

`default_max_depth` is **10000 on every backend**. It was two numbers -- 500 on
a native thread, 12 on the three that run on a JavaScript engine -- because the
evaluator recursed and the real limit was the HOST's stack. With the
continuation on the heap there is nothing left for the backend to decide, so
`depth_native.mbt` and `depth_js.mbt` are one `depth.mbt`, and the number is a
policy: deep enough that no reasonable program meets it, shallow enough that a
runaway stops in an array of ten thousand frames rather than in an
out-of-memory.

`tools/depth-probe.mjs` and `tools/depth-probe-page/` are deleted, with the
three `just` recipes that drove them. They measured how many guest calls a host
could hold before its stack gave out -- warm against cold, V8 against
SpiderMonkey, debug against `-Oz`, and how much of the stack the caller had
already spent. Every one of those axes mattered, and none of them does now. The
guest's depth costs an array.

The playground keeps an explicit 250, and for a different reason than it had:
not because a browser tab cannot hold more, but because "not stopping" should
stop while you are looking at it.

## 0.6.0 — 2026-09-08

A library user can opt in to a superset of PurePy. `@profile.core` is PurePy
exactly as specified and is the default of every call that takes one, so a
consumer who never heard of profiles gets what they got before: the same
verdicts, the same messages, 983/983 conformance with no floor moved.
Everything below is opt-in.

**The API changes are additive except in three places**, which is why this is a
minor bump. `@ast.JoinedStr` gained a `parts` field, `@value.LamClosure` gained
`defaults`, and `@value.Primitive` gained eighteen arms -- so a consumer who
CONSTRUCTS one of the first two, or matches `Primitive` exhaustively, has a
line to change. Everything else is a new optional argument or a new name.

### f-strings

`f"the answer is {x}"` joins `pending`, with `!r` and `!s`. A format spec --
the `>10` of `f"{x:>10}"` -- is a language of its own and is refused by name,
as is the `f"{x=}"` debug form, which would mean keeping the source of the
expression.

The AST node kept only `raw`, the source text of the whole adjacent-string
group, because `tools/pyast_dump.py` renders CPython's `JoinedStr` the same way
-- the AST oracle agreed to disagree about f-string internals. So `raw` stays
and is still all that `dump` prints and `unparse` writes; a `parts` field
beside it carries the pieces, and everything that looks INSIDE an f-string uses
that. The AST oracle is untouched at 416/416.

A hole's expression is parsed over a source that is the FILE up to the hole,
blanked, wrapped in brackets, then the hole. The blanking makes line, column
and offset land exactly where they land in the file, so `f"{nope}"` reports the
`nope` rather than a character in a fragment nobody wrote. The brackets are
what make it parse at all: blank space at the start of a line is indentation,
and inside brackets the tokenizer joins lines implicitly and indentation means
nothing.

A hole is `str` and `!r` is `repr` -- the same two `print` has always used, and
not the `str` builtin, which is a different profile away.

### A big match arm costs stack even when it is not taken

Writing the f-string evaluation inline as an arm of `eval_expr` cost the guest
four frames of recursion depth on wasm-gc, and two tests that pin `max_depth`
against a real stack caught it. A frame is sized by the whole function, so a
big arm makes every call of `eval_expr` cost more whether or not it takes that
arm -- and `max_depth` on a JavaScript engine is calibrated against exactly
that. Moved to a function of its own, with a note saying why it is one.

Default arguments got the same treatment for the same reason: a function with
no defaults now takes the code it took before the feature existed, with no call
and no allocation on the way.

### Default arguments, where the default is a literal

`def f(x=1)` and `lambda x=1: x` join `pending`, provided the default is a
literal int, float, str, bool or `None`. Anything else is still #56.

The restriction IS the feature. Python evaluates a default once, when the `def`
runs, and that is observable for anything with an effect or a free name -- a
default of `print("hi")` prints once however often `f` is called. This
evaluator has nowhere to put a once: calling one function of a mutual region
rebuilds the whole region, so a `Def` closure is remade per call. A general
default would therefore have to be evaluated at the wrong time. A literal has
no effect and reads no name, so when it is evaluated cannot be observed, and
the question stops existing rather than being answered wrongly. The feature is
drawn exactly at the line where the difference disappears.

Arity is still checked. A default widens the shapes a call may take from one to
a range, and outside that range it is the `TypeError` Python raises.

### `is` against a literal is refused rather than left to stop

`1 is 1` had no answer and said so when it ran. It says so before it runs now.
A PurePy value has no identity and `None` is the whole of the exception, so an
`is` with an operand that is literally not `None` can never mean anything --
and that is visible in the token, with no types needed. It is `prohibited`
rather than `not yet`, because nothing is pending and no profile should lift
it.

Where the operand is not a literal there is nothing to see, so `x is y` still
stops when it runs. That is still a stop: exit 5, before any value comes back,
never an invented answer.

### `methods`: the builtin types get their non-mutating half

`@profile.methods()` adds `"a".upper()`, `s.split(",")`, `",".join(parts)`,
`xs.index(x)`, `d.get(k, 0)` and the rest of what `str`, `list`, `tuple` and
`dict` can be asked without being changed. It is the profile that makes PurePy
read like Python rather than like a calculator.

**It does not make anything mutable**, and that needed care rather than
intention. The absence of methods is what made a list immutable in the first
place: the evaluator had no attribute rule for a builtin value, so
`xs.append(1)` was unreachable rather than forbidden. So the profile adds a
rule for the CALL and only for methods that answer with a new value.
`append`, `extend`, `insert`, `pop`, `remove`, `sort`, `reverse`, `clear`,
`update` and `setdefault` are absent from `lib/value/method.mbt`, and absent is
the same undefined operation an unknown attribute has always been. It could not
be otherwise -- a `Value` is an immutable enum with no identity, so a mutating
method would have nothing to write to -- but there is a test naming all ten,
because `sort` and the `sorted` of the profile below are one letter apart.

Methods are not first class either. `"a".upper()` works and `f = "a".upper` is
the `Stuck` it has always been, because a bound method would be a new kind of
`Value` -- needing a `repr`, an `eq` and an ordering the specification does not
define -- and it would start crossing the host boundary, which is an embedding
change wearing an evaluator change's clothes.

`d.keys()`, `d.values()` and `d.items()` answer with lists rather than views,
as `range` answers with a list.

### The profile oracle asks the whole pipeline, not just `check`

Question 1 was "still refused by `pure-py check`". For a methods corpus that
asked nothing: the checker carries no types, so `s.upper()` type-checks under
`core` and is an undefined operation only when it runs. Every methods file
recorded `ok` and the question was vacuous.

It asks `pure-py run` now, and requires a NON-ZERO exit -- a corpus file that
works without its profile is not testing a profile, and `--regen` refuses to
write that down rather than recording it. Where a profile bites then shows up
in the expectation itself: exit 4 and `slicing not yet supported (#59)` for a
syntax feature, exit 3 and `'abs' is not definitely assigned` for a builtin,
exit 5 and `stuck: an attribute of str` for a method.

### `builtins`: a profile that adds names and no syntax

`@profile.builtins()` is `pending` plus eighteen builtin functions -- `abs`,
`all`, `any`, `divmod`, `enumerate`, `float`, `int`, `list`, `max`, `min`,
`repr`, `reversed`, `round`, `sorted`, `str`, `sum`, `tuple`, `zip`. Nothing
about the syntax changes: a program written against it parses as PurePy and
would be refused only for the names it uses. Three builtins is a small language
to write in, and this is the cheapest superset to reason about.

**None of them coerces.** `sum([True])` is 1 in Python only because a bool is
an int there, and `any([1])` is True only because 1 is truthy. PurePy says
neither, so both are undefined here. That is the whole difference between
adding a library to PurePy and adding Python to it. `bool` is absent for the
same reason and not by oversight: it is Python's truthiness in a function, and
there is no truthiness to put in it. `sorted` and `min` refuse a list their
order does not cover rather than falling back on position, which is the
discipline `@value.eq` already follows.

`enumerate`, `zip`, `reversed`, `sorted`, `list` and `tuple` answer with a list
rather than a lazy object. That follows `range`, which Figure 2.7 already
defines as a list, and it is observable in the same way: `print(zip(a, b))`
prints the pairs here and `<zip object at 0x...>` in Python. Everything that
consumes one agrees.

A profile now decides what `builtins` exports, so `run` and `run_with` take one
too, and **the checker and the run must be handed the same profile** -- they
are two calls, and a run given the poorer one finds a name that type-checked
and is not there.

Three tables had to agree for this and nothing made them:
`@context.predefined_members` names the builtins for the checker,
`Interp::predefined` binds their values, and `call_primitive` implements them.
They cannot become one -- `lib/check` does not import `lib/value`, deliberately
-- so `lib/eval/predefined_wbtest.mbt` is what keeps them from drifting, per
profile. Forgetting either half makes a name that type-checks and is not there,
or is there and cannot be named, and neither half looks wrong on its own.

### `pending` holds five features, and CPython is its oracle

The profile grew from one feature to five: chained boolean operators and
chained comparisons (#82), `is` and `is not` (#81), slicing (#59), and
destructuring assignment (#54).

Each is a whole vertical slice -- a sieve gate, a case wherever the checker and
`lib/analysis` would otherwise have walked a node they had none for, and a rule
in the evaluator -- because opening a gate without the rest of it does not
produce a rejection, it produces an `abort("unreachable after the sieve")`.

Two of the five have an edge PurePy declines to invent an answer for.

`is` asks whether two expressions denote the same object, and a PurePy value
has no identity: nothing is mutable, so no program can tell two equal values
apart. `None` is the exception and the reason `is` is worth having -- it is a
singleton, `x is None` is how Python spells the question, and here it is total.
`1 is 1` and `True is True` are undefined, not True: CPython answers True by
interning, which is an implementation's answer and not a language's.

A slice step of zero, and an arity mismatch in a destructuring target, are both
`ValueError` in Python. PurePy models seven terminations and `ValueError` is
not one of them, so both are undefined rather than borrowing a kind that means
something else.

### A conformance oracle for profiles, because the reference cannot be one

`tools/conform.py` drives our CLI against the reference checker's answers, and
that works because the reference decides what PurePy is. A profile is the case
it has no answer for: it accepts what the reference refuses, so pointing the
reference at a profile corpus would only reproduce the refusal.

But **every profile feature is outside the specification and inside Python**,
and CPython is already this project's oracle for what a run prints. So
`tools/profile-conform.py` asks three things of every file in `test/profile/`:

  1. still refused under `core`, with the message in `.core.expected` -- the
     question that makes it a profile test rather than a Python test, and the
     one a feature that leaked into the default would fail;
  2. accepted under the profile, so the sieve gate and the checker agree;
  3. prints what `python3` prints.

`test/profile/refused/` asks the opposite: a file there must stay refused under
every profile there is. That is the corpus form of "no profile lifts a
prohibition", which is the claim everything in `docs/embedding.mbt.md` rests
on, tested from outside rather than only in a unit test.

`test/profile-policy.json` is a second ratchet, separate on purpose: a profile
must never be able to move a PurePy floor. PurePy's own numbers are unchanged
at 983/983.

### Profiles: a superset a library user can opt in to

`sieve`, `check`, `check_program` and `source_tree_from` take a `profile`,
which is how a caller asks for a language slightly larger than PurePy. The new
`marianoguerra/pure-py/profile` package holds it. `@profile.core` is the
default of all four -- PurePy exactly as specified -- so a caller who never
heard of profiles gets the answer they got before, and the conformance suite
still reports 983/983 with no floor moved.

`@profile.pending()` is the first named one. It holds the forms the sieve
refuses today with an upstream issue number, and it starts with one:

```
$ pure-py check chained.py
chained.py:1:6: chained boolean operator not yet supported (#82)
$ pure-py --profile pending run chained.py
True
```

It is a set, and it grows one feature per commit until it covers the table in
`implementation-plan.md` § "After the plan: the pending features". `pure-py
profiles` prints what it actually holds. `--profile` must come before the
command, because `run` gives everything after the entry file to the guest's
`sys.argv`, and running under the wrong language silently is worse than being
told where the flag goes.

Two limits are worth stating, because they are the point rather than an
omission.

**A profile never lifts a prohibition.** The sieve refuses two kinds of form:
one PurePy plans to have (`not yet supported (#82)`, exit 2) and one it
excludes on purpose (`for loops prohibited`, exit 1). The second list -- `for`,
`while`, `try`, `raise`, `del`, `+=`, item and attribute assignment -- is what
makes the language pure, and it is what every guarantee in
`docs/embedding.mbt.md` rests on. `Sieve::gate` exists for the first list and
there is deliberately no counterpart for the second.

**A profile is not a mode the runtime is in.** `run` takes no profile and the
evaluator reads none. It always evaluated an n-ary `and` correctly; the sieve
simply never let one through. A profile widens what a host will accept from its
guest, and changes nothing about what the semantics does with what it accepted
-- `1 and 2 and 3` is accepted under `pending` and still undefined when it
runs.

The playground has a selector beside the example list, and `analyze` keeps its
one-argument shape: `analyze_with(source, profile)` is the new export.

## 0.5.0 — 2026-09-08

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
Over the playground's release module, in guest calls:

| engine | tail | accumulating | nested |
|---|---|---|---|
| V8 (Node 24) | 1488 | 992 | 781 |
| V8 (Chromium 152, headless) | 1500 | 987 | 783 |
| SpiderMonkey (Firefox 155, headless) | 3687 | 2456 | 1965 |

Each shape is swept from two stack positions, after an `await` and from a
fresh `setTimeout` callback, and both are reported. They agree to within one
call in both engines here; they are reported anyway, because an embedder
measuring a different module found them disagreeing, and a harness with one
column cannot tell an engine's behaviour from its own mistake. The same
module also read 1966 on Firefox 154 before the browser updated mid-session,
which is the only evidence here about how these numbers move across engine
versions.

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
