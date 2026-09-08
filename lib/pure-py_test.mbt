///|
/// The façade is total: it answers rather than crashing, whatever tree it is
/// given.
///
/// The checker is written against the subset the sieve leaves and has no case
/// for a `for` loop, so the façade sieves first. A caller who wants only the
/// well-formedness answer can reach `@check.check_single`, and that is where
/// the precondition lives.
test "check answers on a tree the sieve would reject" {
  let m = @purepy.parse("for x in [1]:\n    pass\n")
  match @purepy.check(m) {
    Some(d) => {
      assert_eq(d.message(), "for loops prohibited")
      assert_eq(d.exit_code(), 1)
    }
    None => fail("a for loop is not PurePy")
  }
}

///|
test "check_program answers on a module the sieve would reject" {
  let modules = Map([
    ("__main__", @purepy.parse("import lib\nprint(lib.x)\n")),
    ("lib", @purepy.parse("x = 1\nwhile x:\n    pass\n")),
  ])
  match @purepy.check_program(@purepy.source_tree(modules)) {
    Some(d) => assert_eq(d.message(), "lib: while loops prohibited")
    None => fail("a while loop is not PurePy")
  }
}

///|
/// Evaluation was already total: an unsieved construct is an operation the
/// semantics does not cover, which is an answer.
test "run answers on a tree the sieve would reject" {
  let modules = Map([("__main__", @purepy.parse("for x in [1]:\n    pass\n"))])
  let (_, result) = @purepy.run(@purepy.source_tree(modules))
  match result {
    Undefined(op) => assert_eq(op, "statement For")
    _ => fail("a for loop has no rule")
  }
}

///|
/// A program assembled in memory can import the predefined modules.
///
/// A tree read off a disk has them because discovery put them there; one
/// built by an embedder has never seen them, and `import math` in it used to
/// be an unknown module.
test "an in-memory program can import math, sys and the rest" {
  let modules = Map([
    (
      "__main__",
      @purepy.parse(
        "import math\nimport sys\nfrom dataclasses import dataclass\n" +
        "from typing import Any\nprint(math.floor(2.7), len(sys.argv))\n",
      ),
    ),
  ])
  let tree = @purepy.source_tree(modules)
  assert_eq(@purepy.check_program(tree), None)
  let (output, result) = @purepy.run(tree, argv=["main.py"])
  assert_true(result is Finished)
  assert_eq(output, "2 1\n")
}

// ---------------------------------------------------------------------------
// Profiles

///|
/// The whole of a profile, from the outside: a program PurePy refuses, run by
/// a caller who asked for the superset that has it.
///
/// Note what does NOT appear here. `run` takes no profile, because the
/// evaluator already evaluates an n-ary `and` correctly -- it always did, the
/// sieve simply never let one through. A profile is not a mode the runtime is
/// in; it is what a caller was allowed to write.
test "a profile is opted in to, per call" {
  let source = "print(True and True and True)\n"
  let m = @purepy.parse(source)

  // Refused by default, with the message the reference prints.
  let refused = @purepy.sieve(m).unwrap()
  assert_eq(refused.exit_code(), 2)
  assert_eq(
    refused.message(),
    "chained boolean operator not yet supported (#82)",
  )
  assert_eq(@purepy.check(m).unwrap().message(), refused.message())

  // Accepted, checked and run under the profile that has it.
  let profile = @profile.pending()
  assert_eq(@purepy.sieve(m, profile~), None)
  assert_eq(@purepy.check(m, profile~), None)
  let tree = @purepy.source_tree(Map([("__main__", m)]))
  assert_eq(@purepy.check_program(tree, profile~), None)
  let (output, result) = @purepy.run(tree)
  assert_true(result is Finished)
  assert_eq(output, "True\n")
}

///|
/// Passing `@profile.core` explicitly is passing nothing, which is what makes
/// the default safe to rely on.
test "core is the default, spelled out" {
  let m = @purepy.parse("x = a and b and c\n")
  assert_eq(
    @purepy.sieve(m, profile=@profile.core).unwrap().message(),
    @purepy.sieve(m).unwrap().message(),
  )
  assert_eq(@purepy.check(m, profile=@profile.core), @purepy.check(m))
}

///|
/// A profile relaxes what the sieve refuses with an issue number and nothing
/// else. `print(5 and 6)` was never a syntax question -- it type-checks and is
/// undefined at run time -- and it stays that way.
test "a profile does not make an undefined operation defined" {
  let m = @purepy.parse("print(1 and 2 and 3)\n")
  assert_eq(@purepy.check(m, profile=@profile.pending()), None)
  let tree = @purepy.source_tree(Map([("__main__", m)]))
  let (_, result) = @purepy.run(tree)
  assert_true(result is Undefined(_))
}

///|
/// Run one source under a profile and say how it ended.
fn outcome_under(source : String, profile : @profile.Profile) -> String raise {
  let m = @purepy.parse(source)
  match @purepy.check(m, profile~) {
    Some(d) => return "refused: " + d.message()
    None => ()
  }
  let tree = @purepy.source_tree(Map([("__main__", m)]))
  // The SAME profile the check used. Handing the run a poorer one is the
  // mismatch "the checker and the run want the same profile" is about, and a
  // helper that made it would report every added builtin as an unbound name.
  match @purepy.run(tree, profile~) {
    (out, Finished) => "ok: " + out
    (_, Terminated(k, _)) => "aborts: " + k.to_text().to_string()
    (_, Undefined(op)) => "undefined: " + op
    (_, Suspended) => "suspended"
  }
}

///|
/// Where a profile's features are UNDEFINED rather than wrong.
///
/// These cannot live in `test/profile/`, whose whole claim is that our answer
/// is CPython's: CPython has an answer for every one of them and PurePy
/// deliberately does not. Being undefined is the answer, and it is worth
/// pinning, because the alternative to a rule is not "no rule" but "someone
/// invents one later".
test "a pending feature is undefined where PurePy has no rule" {
  let p = @profile.pending()
  // `is` between two things that are not `None` has no answer. Where an
  // operand is a LITERAL it is visible in the source, and the sieve refuses it
  // before the run rather than stopping halfway through one -- see
  // "identity against a literal is refused, not deferred". Where it is not,
  // there is nothing to see, so it stops when it runs. Still a stop, and never
  // an invented answer.
  assert_true(
    outcome_under("x = 1\ny = 1\nprint(x is y)\n", p).has_prefix("undefined: "),
  )
  // A slice step of zero is a ValueError in Python, which is not one of the
  // seven terminations PurePy models.
  assert_eq(
    outcome_under("print([1, 2][::0])\n", p),
    "undefined: a slice with a step of zero",
  )
  // An arity mismatch is a ValueError too.
  assert_eq(
    outcome_under("a, b = 1, 2, 3\n", p),
    "undefined: unpacking 3 values into 2 targets",
  )
  // A chain is only as defined as its links: PurePy's `<` between an int and
  // a str has no rule, and neither does the chain that contains one.
  assert_true(
    outcome_under("print(1 < 2 < \"a\")\n", p).has_prefix("undefined: "),
  )
}

///|
/// Where a profile's features ABORT, which is a different thing.
test "a pending feature aborts where Python raises" {
  let p = @profile.pending()
  assert_eq(outcome_under("print(1[1:2])\n", p), "aborts: TypeError")
  assert_eq(outcome_under("a, b = 1\n", p), "undefined: unpacking int")
  // A chain short-circuits: the third comparison is never made, so its
  // undefined operand never matters.
  assert_eq(outcome_under("print(2 < 1 < \"a\")\n", p), "ok: False\n")
}

///|
/// The added builtins do not coerce, because PurePy does not.
///
/// Every line here is something Python answers and this declines to. That is
/// the whole difference between adding a LIBRARY to PurePy and adding Python
/// to it: `sum([True])` is 1 in Python only because a bool is an int there,
/// and `any([1])` is True only because 1 is truthy. PurePy says neither, so a
/// builtin that said them would be smuggling in a rule the language refused.
test "an added builtin declines where Python coerces" {
  let p = @profile.builtins()
  let undefined = [
    // No truthiness: `any` and `all` want the real bools `if` wants.
    "print(any([1, 2]))\n", "print(all([1]))\n", "print(any(['']))\n",
    // A bool is not a number, so `+` over one has no rule.
     "print(sum([True, False]))\n",
    // A partial order stays partial: no total order over these, so no sort.
     "print(sorted([1, 'a']))\n", "print(min(1, 'a'))\n",
    // Python raises ValueError, which PurePy does not model.
     "print(int('twelve'))\n", "print(min([]))\n",
  ]
  for source in undefined {
    let got = outcome_under(source, p)
    assert_true(got.has_prefix("undefined: "), msg=source + " -> " + got)
    // Not undefined because the NAME was missing -- that would make this test
    // pass under any profile at all, including one with no builtins in it.
    assert_false(got.has_prefix("undefined: the unbound name"), msg=source)
  }
  // A bool handed to a builtin that says what it takes is a TypeError and not
  // undefined, which is the better answer of the two: `TypeError` is a
  // termination the semantics HAS, and Python raises one here too. Undefined
  // is for where PurePy has no rule at all, not for where it has one and the
  // argument fails it.
  for source in ["print(abs(True))\n", "print(int(True))\n"] {
    assert_eq(outcome_under(source, p), "aborts: TypeError", msg=source)
  }
}

///|
/// An added builtin is a NAME, and a profile that does not have it does not
/// have the name -- so the failure is the checker's, before anything runs.
test "an added builtin is not in scope without the profile" {
  let m = @purepy.parse("print(sorted([2, 1]))\n")
  assert_eq(@purepy.sieve(m), None)
  assert_eq(
    @purepy.check(m).unwrap().message(),
    "'sorted' is not definitely assigned",
  )
  assert_eq(
    @purepy.check(m, profile=@profile.pending()).unwrap().message(),
    "'sorted' is not definitely assigned",
  )
  assert_eq(@purepy.check(m, profile=@profile.builtins()), None)
}

///|
/// A profile handed to the checker and not to the run is a name that
/// type-checks and is then not there. The facade cannot prevent it -- they are
/// two calls -- so this is what says out loud that it is the caller's job.
test "the checker and the run want the same profile" {
  let m = @purepy.parse("print(sorted([2, 1]))\n")
  let tree = @purepy.source_tree(Map([("__main__", m)]))
  assert_eq(@purepy.check_program(tree, profile=@profile.builtins()), None)
  // Checked under `builtins`, run under `core`: the name is gone.
  let (_, mismatched) = @purepy.run(tree)
  assert_true(mismatched is Undefined(_))
  let (out, agreed) = @purepy.run(tree, profile=@profile.builtins())
  assert_true(agreed is Finished)
  assert_eq(out, "[1, 2]\n")
}

///|
/// A profile that adds methods does not make anything mutable.
///
/// This is the claim the whole embedding guide rests on, so it is asserted
/// against the names rather than described. Every mutating method Python has
/// on a list or a dict is absent from `lib/value/method.mbt`, and absent is
/// the same undefined operation an unknown attribute has always been.
///
/// The regression this catches is somebody adding `sort` by analogy with the
/// `sorted` of the profile below -- one letter apart, and one of them mutates.
test "no method a profile adds can mutate" {
  let p = @profile.methods()
  let mutators = [
    "xs = [1, 2]\nxs.append(3)\n", "xs = [1, 2]\nxs.extend([3])\n", "xs = [1, 2]\nxs.insert(0, 3)\n",
    "xs = [1, 2]\nxs.pop()\n", "xs = [1, 2]\nxs.remove(1)\n", "xs = [1, 2]\nxs.sort()\n",
    "xs = [1, 2]\nxs.reverse()\n", "xs = [1, 2]\nxs.clear()\n", "d = {'a': 1}\nd.update({'b': 2})\n",
    "d = {'a': 1}\nd.setdefault('b', 2)\n", "d = {'a': 1}\nd.pop('a')\n", "d = {'a': 1}\nd.clear()\n",
  ]
  for source in mutators {
    let got = outcome_under(source, p)
    assert_true(got.has_prefix("undefined: an attribute of"), msg=source)
  }
}

///|
/// Methods are not first class, and the bare attribute is untouched.
///
/// A bound method would be a new kind of `Value`, needing a `repr`, an `eq`
/// and an ordering the specification does not define -- and it would start
/// crossing the host boundary, which is an embedding change wearing an
/// evaluator change's clothes. So the profile adds a rule for the CALL, and
/// `"a".upper` is the undefined operation it has always been.
test "a method is a call and not a value" {
  let p = @profile.methods()
  assert_eq(outcome_under("print(\"a\".upper())\n", p), "ok: A\n")
  assert_eq(
    outcome_under("f = \"a\".upper\n", p),
    "undefined: an attribute of str",
  )
  // A name no table has reads the way a typo has always read.
  assert_eq(
    outcome_under("print(\"a\".uper())\n", p),
    "undefined: an attribute of str",
  )
  assert_eq(
    outcome_under("print((1).bit_length())\n", p),
    "undefined: an attribute of int",
  )
}

///|
/// The method rule must not have taken the paths that were already there.
///
/// `eval_call` looks at an `Attribute` callee before it evaluates it now, so
/// a module member and a dataclass field reach their own rules through new
/// code. Both are ordinary PurePy and are what would break silently.
test "a module member and a field still resolve as they did" {
  for p in [@profile.core, @profile.methods()] {
    assert_eq(
      outcome_under("import math\nprint(math.floor(2.7))\n", p),
      "ok: 2\n",
    )
    assert_eq(
      outcome_under(
        "from dataclasses import dataclass\nfrom typing import Any\n" +
        "@dataclass\nclass P:\n    x: Any\n\np = P(1)\nprint(p.x)\n",
        p,
      ),
      "ok: 1\n",
    )
    // A module member that is not there is the CHECKER's answer, before
    // anything runs -- the one attribute PurePy can decide statically, and
    // the one the method rule must not have moved to run time.
    assert_eq(
      outcome_under("import math\nprint(math.nope())\n", p),
      "refused: module 'math' has no member 'nope'",
    )
    assert_eq(
      outcome_under(
        "from dataclasses import dataclass\nfrom typing import Any\n" +
        "@dataclass\nclass P:\n    x: Any\n\np = P(1)\nprint(p.y())\n",
        p,
      ),
      "aborts: AttributeError",
    )
  }
}

///|
/// A default argument fills the parameters a call left out, and nothing else.
///
/// Arity is still checked: a default widens the shapes a call may take, from
/// one to a range, and outside that range it is the `TypeError` Python raises.
test "a default argument fills a missing parameter" {
  let p = @profile.pending()
  let f = "def f(a, b=2, c=3):\n    return [a, b, c]\n"
  assert_eq(outcome_under(f + "print(f(1))\n", p), "ok: [1, 2, 3]\n")
  assert_eq(outcome_under(f + "print(f(1, 9))\n", p), "ok: [1, 9, 3]\n")
  assert_eq(outcome_under(f + "print(f(1, 9, 8))\n", p), "ok: [1, 9, 8]\n")
  // Too few for the required parameters, and too many for the whole list.
  assert_eq(outcome_under(f + "print(f())\n", p), "aborts: TypeError")
  assert_eq(outcome_under(f + "print(f(1, 2, 3, 4))\n", p), "aborts: TypeError")
  // A lambda takes the same rule, through the same code.
  assert_eq(
    outcome_under("g = lambda x, y=10: x + y\nprint(g(1), g(1, 2))\n", p),
    "ok: 11 3\n",
  )
  assert_eq(
    outcome_under("g = lambda x, y=10: x\nprint(g())\n", p),
    "aborts: TypeError",
  )
}

///|
/// A default is a literal, so WHEN it is evaluated cannot be observed.
///
/// This is the restriction's whole justification, and it is worth a test that
/// would fail if the restriction were lifted without the machinery to support
/// it: a `Def` closure is rebuilt every time one member of its mutual region
/// is called, so a default with an effect would fire once per call and Python
/// fires it once per `def`. With literals there is nothing to fire.
test "a default argument cannot be evaluated at an observable time" {
  let p = @profile.pending()
  let source =
    #|def even(n, step=1):
    #|    if n == 0:
    #|        return True
    #|    return odd(n - step)
    #|
    #|def odd(n, step=1):
    #|    if n == 0:
    #|        return False
    #|    return even(n - step)
    #|
    #|print(even(4), odd(4), even(3, 3))
    #|
  // Sixteen calls through a mutual region, each rebuilding both closures and
  // each re-reading the same two defaults. Nothing observes the difference.
  assert_eq(outcome_under(source, p), "ok: True False False\n")
}

///|
/// An f-string reads names the way the rest of the language reads them.
///
/// The holes are real expressions at their real positions in the file, not a
/// fragment parsed somewhere else, so the checker's rules reach into them:
/// definite assignment, the capture rules, everything.
test "an f-string is checked like the expressions it holds" {
  let p = @profile.pending()
  assert_eq(outcome_under("x = 1\nprint(f\"{x} {x + 1}\")\n", p), "ok: 1 2\n")
  // Not definitely assigned, reported at the name inside the hole.
  let m = @purepy.parse("a = 1\nprint(f\"x is {nope} here\")\n")
  let d = @purepy.check(m, profile=p).unwrap()
  assert_eq(d.message(), "'nope' is not definitely assigned")
  assert_eq(d.span.unwrap().start.line, 2)
  assert_eq(d.span.unwrap().start.col, 14)
  // The capture rule reaches inside one too.
  assert_eq(
    @purepy.check(
      @purepy.parse("x = 1\nf = lambda: f\"{x}\"\nx = 2\n"),
      profile=p,
    )
    .unwrap()
    .message(),
    "'x' captured by previous statement, reassigned here",
  )
}

///|
/// A hole is `str`, and `!r` is `repr` -- the same two `print` has always had,
/// and not the `str` BUILTIN, which is a different profile away.
test "an f-string formats with the printing rules PurePy already had" {
  let p = @profile.pending()
  assert_eq(
    outcome_under("print(f\"{1} {2.5} {None} {True}\")\n", p),
    "ok: 1 2.5 None True\n",
  )
  assert_eq(
    outcome_under("print(f\"{[1, 2]} {(1,)}\")\n", p),
    "ok: [1, 2] (1,)\n",
  )
  assert_eq(outcome_under("print(f\"{'a'} {'a'!r}\")\n", p), "ok: a 'a'\n")
  // A closure has no printable form, and an f-string is a print by another
  // name -- the same undefined operation `print` gives.
  assert_eq(
    outcome_under("f = lambda: 1\nprint(f\"{f}\")\n", p),
    "undefined: formatting function",
  )
}
