///|
/// The equations of Annex A.1, on sources rather than on hand-built trees:
/// what the reference computes for a program is what a reader can check
/// against the spec.
fn parse(source : String) -> Array[@ast.Stmt] {
  @parser.parse_string(source).body catch {
    e => abort("the test source does not parse: \{e}")
  }
}

///|
fn set_text(s : @analysis.NameSet) -> String {
  "{" + s.to_array().join(", ") + "}"
}

///|
test "a run of defs is one mutual region" {
  let body = parse(
    "x = 1\ndef f():\n    return g()\ndef g():\n    return 1\ny = 2\n",
  )
  let items = @analysis.statements(body)
  assert_eq(items.length(), 3)
  assert_true(items[0] is Single(_))
  match items[1] {
    Region(defs) => assert_eq(defs.length(), 2)
    _ => fail("expected a region of two definitions")
  }
  assert_true(items[2] is Single(_))
  assert_eq(set_text(@analysis.assigns_statement(items[1])), "{f, g}")
}

///|
test "a region captures what its bodies need from outside itself" {
  // `even` and `odd` name each other, so neither is captured; `c` is.
  let body = parse(
    "def even(n):\n    return odd(n - c)\ndef odd(n):\n    return even(n - c)\n",
  )
  let items = @analysis.statements(body)
  assert_eq(set_text(@analysis.captures_statement(items[0])), "{c}")
}

///|
test "a lambda captures its free variables, less its parameters" {
  let body = parse("f = lambda x: x + i\n")
  assert_eq(set_text(@analysis.captures(body[0])), "{i}")
  assert_eq(set_text(@analysis.assigns_stmt(body[0])), "{f}")
}

///|
/// The spec's own example: the comprehension binds `i`, so the whole
/// expression captures nothing, while the lambda alone captures `i`.
test "a comprehension binds its target for the element" {
  let body = parse("xs = [lambda x: x ** i for i in range(10)]\n")
  assert_eq(set_text(@analysis.captures(body[0])), "{}")
  match body[0] {
    Assign(value=ListComp(elt~, ..), ..) =>
      assert_eq(set_text(@analysis.captures_e(elt)), "{i}")
    _ => fail("expected a list comprehension")
  }
}

///|
test "a comprehension's own iterable is outside its binding" {
  let body = parse("xs = [y for y in ys for z in y]\n")
  assert_eq(set_text(@analysis.fv_stmt(body[0])), "{ys}")
}

///|
test "an if assigns the union of its branches; a match adds what it binds" {
  let body = parse("if c:\n    a = 1\nelse:\n    b = 2\n")
  assert_eq(set_text(@analysis.assigns_stmt(body[0])), "{a, b}")
  let m = parse(
    "match v:\n    case C(p):\n        a = 1\n    case _:\n        b = 2\n",
  )
  assert_eq(set_text(@analysis.assigns_stmt(m[0])), "{a, b, p}")
  // A case body's free variables exclude what its pattern bound -- and the
  // pattern's own class name is not among them: `fv_stmt` of a match is the
  // subject plus the bodies, which is what the reference computes.
  assert_eq(set_text(@analysis.fv_stmt(m[0])), "{v}")
}

///|
test "a function's free variables exclude its parameters and its own name" {
  let body = parse("def f(a):\n    return f(a) + b\n")
  assert_eq(set_text(@analysis.fv_stmt(body[0])), "{b}")
}

///|
test "an import inside anything is found; one at the top is not" {
  let top = parse("import sys\nx = 1\n")
  assert_true(@analysis.find_nested_import(top) is None)
  assert_true(@analysis.find_import(top) is Some(_))
  let nested = parse("def f():\n    import sys\n    return 1\n")
  assert_true(@analysis.find_nested_import(nested) is Some(_))
  let in_branch = parse("if c:\n    import sys\n")
  assert_true(@analysis.find_nested_import(in_branch) is Some(_))
  let in_case = parse("match v:\n    case _:\n        import sys\n")
  assert_true(@analysis.find_nested_import(in_case) is Some(_))
}

///|
test "imports are split off the front of a body" {
  let body = parse("import sys\nfrom math import pi\nx = 1\nimport os\n")
  let (imports, rest) = @analysis.split_imports(body)
  assert_eq(imports.length(), 2)
  assert_eq(rest.length(), 2)
  // The stray one is what "imports must precede all other statements" finds.
  assert_true(@analysis.find_import(rest) is Some(_))
}

///|
test "a pattern binds its captures in source order, repeats included" {
  let body = parse("match v:\n    case C(a, b, y=a):\n        pass\n")
  match body[0] {
    Match(cases~, ..) => {
      assert_eq(@analysis.binds_seq(cases[0].pattern), ["a", "b", "a"])
      assert_eq(set_text(@analysis.binds(cases[0].pattern)), "{a, b}")
    }
    _ => fail("expected a match")
  }
}

///|
test "a class declares its fields in order, and its name is what it assigns" {
  let body = parse("@dataclass\nclass P:\n    x: Any\n    y: Any\n")
  assert_eq(@analysis.own_fields(body[0]), ["x", "y"])
  assert_eq(set_text(@analysis.assigns_stmt(body[0])), "{P}")
  assert_eq(set_text(@analysis.captures(body[0])), "{}")
}

///|
test "the first statement that reassigns a captured name" {
  let body = parse("f = lambda: g\nx = 1\ng = 2\n")
  let items = @analysis.statements(body)
  let captured = @analysis.captures_statement(items[0])
  assert_eq(set_text(captured), "{g}")
  match @analysis.find_first_reassigning(items[1:], captured) {
    Some(s) => assert_eq(s.span().start.line, 3)
    None => fail("expected the assignment to g")
  }
}

///|
test "a qualified name is its dotted spelling" {
  let body = parse("x = a.b.c\n")
  match body[0] {
    Assign(value~, ..) => {
      assert_true(@analysis.is_qualified_name(value))
      assert_eq(@analysis.qualified_name(value), "a.b.c")
    }
    _ => fail("expected an assignment")
  }
}
