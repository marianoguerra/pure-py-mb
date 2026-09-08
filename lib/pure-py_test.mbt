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
  match @purepy.run(tree) {
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
  // `is` asks about identity, and a PurePy value has none apart from `None`.
  // CPython says True for both of these, by interning.
  assert_true(outcome_under("print(1 is 1)\n", p).has_prefix("undefined: "))
  assert_true(
    outcome_under("print(True is True)\n", p).has_prefix("undefined: "),
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
