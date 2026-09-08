///|
/// Environments, and the two ways of putting one on top of another.
fn env(entries : Array[(String, @value.Value)]) -> @value.Env {
  @value.env_of(entries)
}

///|
test "override lets the right-hand side win outright" {
  let a = env([("x", Int(1N)), ("y", Int(2N))])
  let b = env([("y", Int(3N)), ("z", Int(4N))])
  let out = @value.override_env(a, b)
  assert_true(out.get("x") is Some(Int(_)))
  match out.get("y") {
    Some(Int(n)) => assert_eq(n, 3N)
    _ => fail("y should be 3")
  }
  assert_true(out.get("z") is Some(_))
}

///|
test "extension prefers a loaded module to a stub of the same module" {
  let members = env([("p", Int(1N))])
  let loaded = @value.Value::Mod("m", members)
  let stub = @value.Value::ModStub("m")
  // A stub does not displace a loading.
  match @value.extend_value(loaded, stub) {
    Mod(q, _) => assert_eq(q, "m")
    _ => fail("expected the loaded module")
  }
  // A loading does displace a stub.
  match @value.extend_value(stub, loaded) {
    Mod(q, _) => assert_eq(q, "m")
    _ => fail("expected the loaded module")
  }
  // Two loadings of one module merge member by member.
  let other = @value.Value::Mod("m", env([("q", Int(2N))]))
  match @value.extend_value(loaded, other) {
    Mod(_, members) => {
      assert_true(members.get("p") is Some(_))
      assert_true(members.get("q") is Some(_))
    }
    _ => fail("expected a merge")
  }
}

///|
test "a statement's result read as the outcome of calling it" {
  assert_true(@value.StmtResult::Returns(Int(1N)).outcome() is Val(Int(_)))
  assert_true(@value.StmtResult::Assigns(env([])).outcome() is Val(None))
  assert_true(
    @value.StmtResult::ResultAborts(TypeError).outcome() is Aborts(TypeError),
  )
}

///|
test "sequential composition of results" {
  let a = @value.StmtResult::Assigns(env([("x", Int(1N))]))
  let b = @value.StmtResult::Assigns(env([("y", Int(2N))]))
  match a.then(b) {
    Assigns(e) => {
      assert_true(e.get("x") is Some(_))
      assert_true(e.get("y") is Some(_))
    }
    _ => fail("expected an assignment")
  }
  // Once anything returns or aborts, that is the result.
  assert_true(a.then(Returns(Int(3N))) is Returns(_))
  assert_true(a.then(ResultAborts(KeyError)) is ResultAborts(_))
  assert_true(@value.StmtResult::Returns(Int(3N)).then(b) is Returns(_))
}

///|
test "match results compose, and no-match absorbs" {
  let m = @value.MatchResult::Match(env([("a", Int(1N))]))
  let n = @value.MatchResult::Match(env([("b", Int(2N))]))
  match m.then(n) {
    Match(e) => {
      assert_true(e.get("a") is Some(_))
      assert_true(e.get("b") is Some(_))
    }
    _ => fail("expected a match")
  }
  assert_true(m.then(NoMatch) is NoMatch)
  assert_true(@value.MatchResult::NoMatch.then(m) is NoMatch)
  assert_true(m.then(MatchStuck("x")) is MatchStuck(_))
}

///|
test "dictionary entries replace in place and append otherwise" {
  let base : Array[(String, @value.Value)] = [("a", Int(1N)), ("b", Int(2N))]
  let updated = @value.update(base, "a", Int(9N))
  assert_eq(updated.map(fn(e) { e.0 }), ["a", "b"])
  match updated[0].1 {
    Int(n) => assert_eq(n, 9N)
    _ => fail("expected 9")
  }
  let appended = @value.update(base, "c", Int(3N))
  assert_eq(appended.map(fn(e) { e.0 }), ["a", "b", "c"])
  // `entries` folds `update` over the second list, so a repeated key keeps
  // its first position and takes the last value.
  let folded = @value.entries([], [
    ("a", Int(1N)),
    ("b", Int(2N)),
    ("a", Int(3N)),
  ])
  assert_eq(folded.map(fn(e) { e.0 }), ["a", "b"])
  match folded[0].1 {
    Int(n) => assert_eq(n, 3N)
    _ => fail("expected 3")
  }
}

///|
test "iteration draws keys from a dictionary and elements from everything else" {
  let d = @value.Value::Dict([("a", Int(1N)), ("b", Int(2N))])
  match @value.iter(d) {
    Some(xs) => assert_eq(xs.length(), 2)
    None => fail("a dictionary iterates")
  }
  // `elems` of a dictionary is undefined; only `iter` is defined for one.
  assert_true(@value.elems(d) is None)
  match @value.elems(Str("héllo")) {
    Some(xs) => assert_eq(xs.length(), 5)
    None => fail("a string has elements")
  }
  assert_true(@value.iter(Int(1N)) is None)
}

///|
test "floor division and modulo take the sign of the divisor" {
  assert_eq(@value.floor_div(-7N, 2N), -4N)
  assert_eq(@value.floor_div(7N, -2N), -4N)
  assert_eq(@value.floor_div(-7N, -2N), 3N)
  assert_eq(@value.floor_div(6N, 3N), 2N)
  assert_eq(@value.floor_mod(-7N, 2N), 1N)
  assert_eq(@value.floor_mod(7N, -2N), -1N)
  assert_eq(@value.floor_mod(6N, 3N), 0N)
}

///|
test "an integer and a float compare exactly, not through a conversion" {
  // 2**53 + 1 has no double; converting it would make the two equal.
  let big = 9007199254740993N
  let d = 9007199254740992.0
  assert_eq(@value.eq(Int(big), Float(d)), Some(false))
  assert_eq(@value.order(Int(big), Float(d)), Some(1))
  assert_eq(@value.eq(Int(1N), Float(1.0)), Some(true))
  assert_eq(@value.eq(Int(1N), Float(1.5)), Some(false))
  assert_eq(@value.order(Int(1N), Float(1.5)), Some(-1))
  assert_eq(@value.exact_integer(1.5), None)
  assert_eq(@value.exact_integer(4.0), Some(4N))
}

///|
test "a closure has no printable form, so printing one is undefined" {
  let f = @value.Value::Lam({
    env: env([]),
    params: ["x"],
    defaults: [],
    body: @ast.Expr::name("x"),
    in_module: "__main__",
  })
  assert_true(f.repr() is None)
  assert_true(f.str() is None)
  assert_eq(f.kind_name(), "function")
  assert_true(@value.eq(f, f) is None)
}
