///|
/// What the printer writes, parsed again, is the tree it was given -- on
/// trees no corpus contains.
///
/// The corpus round trip (`tools/unparse_check.sh`) covers real Python; this
/// covers shapes nobody wrote: an `if` inside a `match` case, a conditional
/// expression as the left operand of a power, a string with both quotes in it.
test "a generated tree survives being printed and read back" {
  for seed = 1UL; seed <= 400UL; seed = seed + 1UL {
    let g = @prop.Gen::new(seed)
    let m = g.whole_module()
    let printed = @write.unparse(m)
    let reparsed = @purepy.parse(printed) catch {
      e =>
        // Print the source, not just the seed: a failure is worth reading.
        return fail(
          "seed \{seed}: what we printed does not parse: \{e}\n\{printed}",
        )
    }
    assert_eq(
      @ast.dump(reparsed),
      @ast.dump(m),
      msg="seed \{seed}: the tree changed\n\{printed}",
    )
  }
}

///|
/// A generated tree is inside PurePy: the sieve accepts it.
///
/// This is a claim about the BUILDERS, not about the language: a builder that
/// produced a form the sieve rejects would be a trap for a code generator.
test "the builders produce trees the sieve accepts" {
  for seed = 1UL; seed <= 200UL; seed = seed + 1UL {
    let g = @prop.Gen::new(seed)
    let m = g.whole_module()
    match @purepy.sieve(m) {
      None => ()
      Some(d) => fail("seed \{seed}: \{d.message()}\n\{@write.unparse(m)}")
    }
  }
}

///|
/// `repr` of a value is source for that value: printing it and running the
/// result prints the same text back.
///
/// This ties the printer, the parser and the evaluator to one another over
/// values the corpus does not contain -- nested containers of floats, strings
/// with both quotes, negative zero.
test "a value's repr is source for that value" {
  let values : Array[@value.Value] = [
    None,
    Bool(true),
    Bool(false),
    Int(0N),
    Int(-1N),
    Int(123456789012345678901234567890N),
    Float(0.0),
    Float(-0.0),
    Float(1.0),
    Float(1.0e16),
    Float(1.0e-5),
    Float(0.1),
    Str(""),
    Str("a"),
    Str("it's"),
    Str("say \"hi\""),
    Str("both ' and \""),
    Str("tab\there"),
    Str("nl\nhere"),
    Str("héllo"),
    Str("🐍"),
    List([]),
    List([Int(1N), Str("a")]),
    Tuple([]),
    Tuple([Int(1N)]),
    Tuple([Int(1N), Int(2N)]),
    Dict([]),
    Dict([("a", Int(1N)), ("b", List([Float(1.5)]))]),
    List([Tuple([Dict([("k", Str("v"))])]), None, Bool(true)]),
  ]
  for v in values {
    let text = v.repr().unwrap()
    let modules = Map([("__main__", @purepy.parse("print(" + text + ")"))])
    let (output, result) = @purepy.run(@purepy.source_tree(modules))
    assert_true(result is Finished, msg=text)
    // `print` uses `str`, which differs from `repr` only for a bare string.
    let want = match v {
      Str(s) => s
      _ => text
    }
    assert_eq(output, want + "\n", msg=text)
  }
}

///|
/// Equality is reflexive wherever it is defined at all.
///
/// The exception is the one the spec makes: `nan` against `nan` has no rule,
/// so a value containing one is not equal to itself either.
test "equality is reflexive where it is defined" {
  let values : Array[@value.Value] = [
    None,
    Bool(true),
    Int(7N),
    Float(1.5),
    Str("a"),
    List([Int(1N), Str("b")]),
    Tuple([]),
    Dict([("k", Int(1N))]),
    List([List([Int(1N)])]),
  ]
  for v in values {
    assert_eq(@value.eq(v, v), Some(true), msg=v.repr().unwrap())
  }
  let nan = @value.Value::Float(0.0 / 0.0)
  assert_eq(@value.eq(nan, nan), None)
  assert_eq(@value.eq(List([nan]), List([nan])), None)
}

///|
/// Nesting is bounded, and reaching the bound is an answer rather than a
/// segmentation fault.
///
/// A recursive-descent parser turns nesting in the input into nesting on the
/// machine stack, and an evaluator does the same with a recursive call. Both
/// used to crash; both now report.
test "nesting is bounded in the parser and in the evaluator" {
  let deep = "x = " + "(".repeat(4000) + "1" + ")".repeat(4000) + "\n"
  try @purepy.parse(deep) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("four thousand brackets should not parse")
  }
  // A shallow one still parses.
  let shallow = "x = " + "(".repeat(50) + "1" + ")".repeat(50) + "\n"
  @purepy.parse(shallow) |> ignore
  // An unbounded recursion is reported, not crashed into.
  let modules = Map([
    ("__main__", @purepy.parse("def f(n):\n    return f(n)\nprint(f(1))\n")),
  ])
  // A small limit, so that the test runs on every backend: a JavaScript
  // engine's stack holds far fewer frames than a native thread's, and the
  // limit is the HOST's ceiling rather than this evaluator's.
  let (_, result) = @purepy.run(@purepy.source_tree(modules), max_depth=64)
  match result {
    Undefined(op) => assert_eq(op, "a call stack deeper than 64")
    _ => fail("an unbounded recursion has no answer")
  }
}
