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
