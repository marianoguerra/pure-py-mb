# Replacing what a host cannot reach: `print` and its neighbours

A design note, not a feature. It records the alternatives so that whichever one
is taken, the ones that were not are on record with their reasons.

## The want

An embedder wants to intercept the guest's `print` and capture the **values**
passed to it -- `Array[@value.Value]` -- rather than the text. `Host.write` is
handed the already-`str`-ed, already-space-joined, already-newline-terminated
line (`lib/eval/prim.mbt:19`), and by then the values are gone.

The workaround available today is to *shadow* `print`: inject
`from cap import print` into the module's import prefix, so a
`Prim(Foreign("cap.print"))` from a `HostModule` wins over the `builtins`
binding -- the module environment is
`override_env(override_env(builtins, named), imported)`
(`lib/eval/load.mbt:78`). It works, and it is a trick rather than an API: it
mutates the guest's tree, it is visible to the guest, it needs a module the
checker has to be told about, and it is escapable -- `import builtins` reaches
the real `print` around the shadow.

## What the code already decides

Eight facts, because several of them rule an option in or out.

1. **`print` is the only caller of `write`.** `Interp::write`
   (`lib/eval/interp.mbt:170`) has exactly one call site. "Replace `print`" and
   "replace `write`" name the same surface today.

2. **The checker types every predefined member as `Var(TT)`**
   (`lib/context/context.mbt:428`) -- no arity, no type. So **redefining an
   existing name needs no checker change at all**, and a redefined `print` may
   take any number of arguments. Only *adding* a name needs the checker to
   agree. That splits any override design into a cheap half and an expensive
   one.

3. **`print(x, sep="")` and `print(x, file=...)` cannot be written.** A keyword
   argument on a call that is not a constructor is `Stuck`
   (`lib/eval/machine.mbt:1064`). No guest can ever select a separator or a
   stream, so a two-stream design has nothing that could trigger it. That is
   grammar, not taste.

4. **A host module can never be named `builtins` today.** Both lookups try the
   predefined side first: `Interp::load` (`lib/eval/load.mbt:22`) and
   `members_without_source` (`lib/check/module.mbt:343`). Such a module is
   accepted and ignored, which is why the tree injection in the workaround is
   load-bearing.

5. **A primitive is dispatched through an `async fn` returning `Outcome`**
   (`lib/eval/machine.mbt:694`, `lib/eval/prim.mbt:13`), in the same arm that
   already holds `Foreign(name) => (self.host.call)(name, args)`. A
   host-supplied `print` therefore gets `async`, suspension, and
   `Val`/`Aborts`/`Stuck` through machinery that is already written, already
   documented and already tested.

6. **`Interp::enter` (`lib/eval/machine.mbt:673`) is the one choke point for
   every guest call** -- `Prim`, `Lam` and `Def` alike -- and already holds
   `callee`, `actual` and the call expression. Returns are *not* single-sited:
   `CallBoundary` pops at `lib/eval/machine.mbt:1194` on a normal return and at
   `lib/eval/machine.mbt:284` on the unwind, which pops every frame at once,
   and a primitive pushes no boundary to pop.

7. **`@value.env_of` is FIRST-wins on a duplicate key**, not last-wins:
   `hash_map_from_array_by_add` folds the array backwards, and past
   `bulk_build_threshold = 64` a different builder runs entirely. Appending
   override entries to the `entries` array in `Interp::predefined` is silently
   wrong, and wrong differently on either side of 64 members. An override has to
   go through `@value.override_env`, which is `add` per key and unambiguous.

8. **Conformance is safe by construction rather than by care.** The suite runs
   through `run_program`, which builds its own `Host` (`lib/eval/load.mbt:306`),
   and the goldens are generated with no host at all. Any design whose default
   is "nothing supplied" cannot move the ratchet or a golden, and no amount of
   carelessness elsewhere changes that.

## The alternatives

### A -- a `print` field on `Host`

```moonbit
pub struct Host {
  write : (String) -> Unit
  argv : Array[String]
  modules : Map[String, @value.Env]
  call : async (String, Array[@value.Value]) -> @value.Outcome noraise
  print : (async (Array[@value.Value]) -> @value.Outcome noraise)?   // new
}
```

Declared with no default, so the field is `T?` and `None` means literally the
code in `prim.mbt` today -- the default *is* the current behaviour rather than a
reproduction of it that could drift. The `Print` arm becomes a two-line match.

**For.** The smallest change there is, and exactly the type the embedder asked
for.

**Against.** It is a special case for one builtin, and the next ask --
`sys.exit`, `len` over something lazy -- wants a fifth field, then a sixth. It
stands up a second mechanism beside `Foreign` + `call`, doing the same job with
a different type, so an embedder who has already written a `call` dispatcher now
has two places where host code answers a guest call. And `write` is dead
whenever `print` is `Some`, with nothing in the type saying so.

### B -- a table of redefined predefined members

```moonbit
pub struct Host {
  ...
  /// Members of the predefined modules the host redefines, by dotted name:
  /// `builtins.print`, `sys.exit`, `math.sqrt`. Empty is PurePy.
  redefined : Map[String, @value.Value]
}

pub fn Host::new(..., redefined? : Array[(String, @value.Value)] = []) -> Host
```

No new hook type: the value is an ordinary `host_fn`, answered by the `call` the
embedder has already written.

```moonbit
let host = @eval.Host::new(
  redefined=[("builtins.print", @value.host_fn("cap.print"))],
  call=fn(name, args) {
    match name {
      "cap.print" => { captured.push(args); Val(None) }
      _ => Stuck("no such host function")
    }
  },
)
```

`Interp::predefined` finishes with
`@value.override_env(@value.env_of(entries), @value.env_of(mine_for(q)))` --
never by pushing into `entries` (fact 7).

Two halves, and they want two releases:

* **B1, redefine only.** `lib/check` is untouched, because every predefined
  member is already `Var(TT)` (fact 2).
* **B2, add names as well.** `Program` gains the host's added builtins;
  `members_without_source` (`lib/check/module.mbt:343`) answers with the
  predefined names *followed by* the added ones -- appended, never inserted, for
  the reason `lib/context/context.mbt:370` already gives: `check_submodule_clash`
  reports the FIRST clash, so a reordering reorders a diagnostic the reference
  decides. `check_module`'s `gamma1` (`lib/check/module.mbt:186`) extends with
  them. The union belongs in `lib/check` and not in `lib/context`, which should
  not learn what a host is. `check` and `check_program` already take `host?`
  (`lib/pure-py.mbt:56`), so no public signature moves.

**For.** One field answers `print`, `sys.exit`, `math.*` and every future "can I
intercept this". It reuses `Foreign` + `call`, so `async`, suspension, the three
outcomes and abort-sited-at-the-guest's-call all come free and already have
tests. It retires the workaround rather than blessing it: no tree mutation,
nothing visible to the guest, and `from builtins import print` sees the same
redefinition the bare name does.

**For.** It stays inside what `lib/eval/host.mbt:1-45` claims. A redefined
`print` is not an ambient hook the guest triggers invisibly; it is a *binding*,
the same kind of thing `modules` already is.

**Against, and this is the real cost.** A run that redefines a builtin is no
longer a run CPython is the oracle for. That has to be said in the embedding
guide, in those words, beside the profile section which already makes the
analogous admission.

**Against.** A host can rebind `len` to nonsense. There is no way to offer
print-interception without offering that, short of A's whitelist of one.

**A cheaper spelling (B-prime).** No new field: let a `HostModule` be named
`builtins` and merge, the host's members winning. Fact 4 says such a module is
accepted and ignored today, so this costs no new API and reuses `member_names`
straight into the checker. It is cheaper and it reads worse: it hides a
divergence from the specification inside an ordinary-looking argument, and it
conflates declaring a module with amending a predefined one. `sys.exit` is the
case that settles it -- redefining it is not declaring `sys`.

### C -- bless the shadow

An `ambient : Bool` on `HostModule`, whose members bind beneath `builtins` in
every module's scope, as though each module began `from <name> import *`.

**For.** No tree mutation, and the module is real rather than fake -- a host
could also offer it as `import cap` for a guest that wants to be explicit.

**Against, decisively.** It produces two prints. The ambient one shadows the
builtin, but `from builtins import print` and `import builtins` still reach
`Prim(Print)`. A shadow you can see around is a shadow, which was the whole
complaint.

**Against.** `HostModule` is `pub(all)`, so a new field breaks every struct
literal in existing code -- including the compiled examples in
`docs/embedding.mbt.md` and `lib/README.mbt.md`. That is a worse break than B's,
on the type embedders touch most.

Worth keeping for later as its own feature -- "a prelude the host supplies" --
which is a different want from intercepting a builtin.

### D -- execution hooks: `enter` and `leave`

An observer, which is the only honest shape for this:

```moonbit
/// What the host watches while a run happens. It cannot change the run.
pub(all) struct Trace {
  enter : (@value.Value, Array[@value.Value], Site?) -> Unit
  leave : (@value.Outcome) -> Unit
}
// `Host` gains `trace : Trace?`
```

`enter` goes at the top of `Interp::enter`: one site, everything already in hand
(fact 6). Capturing `print`'s arguments is then a test for `Prim(Print)`, and
paired with a `write` that drops, it gives "record the values, produce nothing".

**For.** It generalises past `print` in a different direction than B does --
every call, guest functions included. It is the only thing here that serves a
debugger, a profiler or a call graph.

**For.** An observer that cannot alter a run keeps it deterministic and keeps
"the guest cannot tell" true.

**Against, for this want.** It can only watch. It cannot make
`print(some_function)` render instead of going `Stuck`, cannot suppress, cannot
abort. It answers "capture the values" and nothing a host might want next.

**Against.** `leave` is not single-sited (fact 6): a normal return, an unwind
that pops every boundary at once, and a primitive that pushes no boundary are
three different sites, and pairing them is the fiddly part of the change.

**Against, the durable cost.** It pins the machine's shape into the public API.
`Ctl`, `Frame` and `CallBoundary` are `priv` precisely so the evaluator can be
re-shaped; `Interp::enter`'s own comment records that `max_depth` "used to be a
guess about the host's stack, re-measured whenever the evaluator changed shape".
A published `enter`/`leave` granularity is a promise about that shape.

**Cost per call**, not per step: one option test and a closure call in
`Interp::enter`, which is affordable. A hook in `Interp::drive` would not be --
the default budget is 100000000 steps, so that one needs a sampling interval and
a measurement rather than a guess.

This is a feature, with its own doc section and its own performance tests. It
should not ride along with a change to `print`.

### E -- a rendering hook

`Host.render : ((@value.Value) -> String?)?`, tried before `Value::str`. It is
the only design here that could make `print(f)` produce `<function f>` where the
run goes `Stuck` today.

**Against.** It does not answer the question asked: the want is
`Array[Value]` and this hands back a `String` a second time. Everything E can do,
B can do by capturing the values and rendering them however it likes.

**Against.** The largest conformance blast radius of anything here, and it wants
`Value::str` -- a pure function of a value, in a package that has consistently
refused to be configurable -- to depend on a host.

Better later, and narrower: a `Value::str_with(fallback)` in `lib/value` that
nothing in `eval` calls, so a host uses it on values it captured rather than the
evaluator using it while printing.

## The recommendation

**B1 now. B2 when somebody asks to add a name rather than replace one. D as its
own feature, later.**

1. **It invents nothing.** The value is a `host_fn`, answered by the `call` the
   embedder already wrote -- already `async`, already an `Outcome`, already
   siting its aborts at the guest's call, already with a tested suspension
   story. A stands up a parallel mechanism; B hands out a *binding*, which
   `Host` is already in the business of doing.
2. **It retires the workaround** instead of blessing it, and unlike C there is
   no way for the guest to see around it.
3. **It answers `sys.exit` and the next three asks with the same field.**
   Exactly one thing on the survey below (D) would still want a mechanism of its
   own afterwards, which is why a trait-shaped `Host` with N defaulted methods
   does not pay for itself.
4. **The default is empty, so the ratchet and the goldens are safe by
   construction** (fact 8), and B1 touches `lib/check` not at all (fact 2).
5. It is small: one field, one function body, one test, one doc section.

Ship one companion with it, or every interception re-implements the join and
drifts from the oracle on its first edge case:

```moonbit
/// What `print` would have written for these arguments: `str` of each, joined
/// by a space, and a newline. `None` if one of them has no printable form,
/// which is the operation `print` leaves undefined.
pub fn print_text(args : Array[@value.Value]) -> String?
```

## What else is worth a hook

| effect | reachable today? | verdict |
|---|---|---|
| `print`, with values | only by mutating the guest's tree | the want -- B |
| `sys.exit` | only by mutating the guest's tree | free under B |
| `len`, `math.*` | no | free under B; rope, meet foot |
| call and return trace | no | D, as its own feature |
| steps spent, reported back | no | cheap, unrelated, worth its own change |
| value rendering | no | later and narrower, as `Value::str_with` |
| `input()` | **yes, fully** -- `HostModule`, `host_fn` and `suspend`; the guide's own suspension example already is this program | a doc example, not a feature. It must not become a builtin: `input` is not in the reference checker's `builtins`, and a profile is documented as never making an undefined operation defined |
| abort observer | subsumed by `RunResult` and `Site` | no |
| import resolution | partly: build `modules` before the run | no. The checker needs member names up front, and "the answer comes before anything has run" is what the guide advertises as the half a sandbox usually cannot do |
| wall-clock deadline | no | no. The guide argues this one on determinism, and the argument still holds |
| `sys.stderr`, two streams | moot | no. Fact 3: no guest can ask for it |

## If B1 is taken

**Files.** `lib/eval/host.mbt` (the field, the named argument, and an amendment
to the header comment) - `lib/eval/interp.mbt` (`Interp::predefined` alone) -
`lib/value/print.mbt` (`print_text`, which the `Print` arm of `lib/eval/prim.mbt`
then calls) - `lib/eval/predefined_wbtest.mbt` and a new
`lib/eval/redefine_test.mbt` - two `pkg.generated.mbti` - `docs/embedding.mbt.md`
(a section, and a row in "The whole surface"). `CHANGELOG.md` is NOT one of
them: in this repository a feature commit leaves it alone and the release
commit that cuts a version writes it.

**Two things to write down,** because burying either would be worse than not
having the feature:

* *A run that redefines a builtin is not a run CPython is the oracle for.*
* *The header comment at `lib/eval/host.mbt:1-45` wants an amendment and not a
  deletion.* "No way to install a callback the guest invokes implicitly" stays
  TRUE -- a redefined `print` is not implicit; the guest calls `print` and gets
  what the host bound to `print`, which is its relationship with `store.get`.
  Say so, or the next reader will think the paragraph went stale.

**The silent trap:** `@value.override_env`, never a longer `entries` array
(fact 7).

**Verification.**

* `moon test` at the root -- the compiled examples in `docs/embedding.mbt.md`
  and `lib/README.mbt.md` run here.
* A new example that captures: redefine `builtins.print` to a `host_fn`, run
  `print(1, "a", [2])`, assert the captured arguments, and assert `write` was
  never called.
* A redefined `print` that aborts: answer `Aborts(TypeError)` and check the
  `Site` lands on the guest's call.
* `from builtins import print` and `import builtins` both reach the
  redefinition. This is the test C cannot pass.
* Extend `predefined_wbtest.mbt`: with nothing redefined, every predefined
  environment is what it is today; with one redefinition, only that key moved.
  Cover a `builtins` past 64 members to pin fact 7.
* `just conform` and the ratchet: `test/conform-policy.json` untouched. That
  file staying still is the proof the default did not move.
* `just goldens`: an empty diff. They are generated with no host.
* `tools/boundary-check.sh`: B1 adds no import edge; confirm it.
* `moon info && moon fmt`, then read the `.mbti` diff -- exactly one new `Host`
  field, one new `Host::new` argument, and `print_text`.
