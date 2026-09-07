///|
/// The static semantics, on sources: what a reader can check against the
/// spec's own examples.
fn verdict(source : String) -> String {
  let m = @parser.parse_string(source) catch { e => return "syntax: \{e}" }
  match @check.check_single(m) {
    None => "ok"
    Some(d) => d.message()
  }
}

///|
/// A whole program, as a map from module name to source.
fn program_verdict(modules : Array[(String, String)], entry : String) -> String {
  let parsed : Map[String, @ast.Module] = Map([])
  for p in @check.predefined_module_names() {
    parsed[p] = { body: [], span: @basic.nowhere, }
  }
  for m in modules {
    parsed[m.0] = @parser.parse_string(m.1) catch {
      e => return "syntax in \{m.0}: \{e}"
    }
  }
  let program = @check.Program::new(parsed)
  try @check.check_module(program, entry) |> ignore catch {
    @err.PurePyError(d) => d.message()
    e => "\{e}"
  } noraise {
    _ => "ok"
  }
}

// ---------------------------------------------------------------------------
// Definite assignment

///|
test "a name must be definitely assigned before it is used" {
  assert_eq(verdict("x = 1\nprint(x)\n"), "ok")
  assert_eq(verdict("print(x)\n"), "'x' is not definitely assigned")
  // Assigned in one branch only.
  assert_eq(
    verdict("if c:\n    x = 1\nprint(x)\n"),
    "'c' is not definitely assigned",
  )
  assert_eq(
    verdict("c = True\nif c:\n    x = 1\nprint(x)\n"),
    "'x' is not definitely assigned",
  )
  // Assigned in both branches.
  assert_eq(
    verdict("c = True\nif c:\n    x = 1\nelse:\n    x = 2\nprint(x)\n"),
    "ok",
  )
  // A branch that returns does not have to assign, inside a function.
  assert_eq(
    verdict(
      "def f(c):\n    if c:\n        x = 1\n    else:\n        return 0\n    return x\n",
    ),
    "ok",
  )
}

///|
test "a match assigns only what every case assigns, and only if exhaustive" {
  assert_eq(
    verdict(
      "v = 1\nmatch v:\n    case 1:\n        x = 1\n    case _:\n        x = 2\nprint(x)\n",
    ),
    "ok",
  )
  // Without a catch-all the match may fall through, so `x` is not certain.
  assert_eq(
    verdict("v = 1\nmatch v:\n    case 1:\n        x = 1\nprint(x)\n"),
    "'x' is not definitely assigned",
  )
  // What a pattern binds is definitely assigned in its own body.
  assert_eq(verdict("v = 1\nmatch v:\n    case a:\n        print(a)\n"), "ok")
}

///|
test "a module body may not return" {
  assert_eq(
    verdict("return 1\n"),
    "top-level return not allowed (module body must not return)",
  )
  assert_eq(
    verdict("c = True\nif c:\n    return 1\nelse:\n    return 2\n"),
    "top-level return not allowed (module body must not return)",
  )
}

///|
test "nothing follows a return" {
  assert_eq(
    verdict("def f():\n    return 1\n    x = 2\n"),
    "unreachable statement",
  )
  assert_eq(verdict("def f():\n    x = 2\n    return 1\n"), "ok")
}

// ---------------------------------------------------------------------------
// Capture

///|
test "a captured name may not be reassigned afterwards" {
  assert_eq(
    verdict("g = 1\nf = lambda: g\ng = 2\n"),
    "'g' captured by previous statement, reassigned here",
  )
  // Reassigning something the closure does not see is fine.
  assert_eq(verdict("g = 1\nf = lambda: g\nh = 2\n"), "ok")
  // A definition captures too.
  assert_eq(
    verdict("g = 1\ndef f():\n    return g\ng = 2\n"),
    "'g' captured by previous statement, reassigned here",
  )
  // A mutual region may name itself.
  assert_eq(
    verdict(
      "def even(n):\n    return odd(n)\ndef odd(n):\n    return even(n)\nprint(even(1))\n",
    ),
    "ok",
  )
}

///|
test "a right-hand side may not capture the name it binds" {
  assert_eq(
    verdict("f = 1\nf = lambda: f\n"),
    "'f' captured by right-hand side",
  )
  // Without the earlier binding the name is simply not assigned yet, and the
  // definite-assignment rule speaks first.
  assert_eq(verdict("f = lambda: f\n"), "'f' is not definitely assigned")
}

///|
test "a generator variable may not be captured by a lambda" {
  assert_eq(
    verdict("xs = [lambda: i for i in [1]]\n"),
    "'i' bound by a generator, captured by a lambda",
  )
  // Capturing the enclosing scope's variable is fine.
  assert_eq(verdict("k = 1\nxs = [lambda: k for i in [1]]\n"), "ok")
  // Using the generator variable without closing over it is fine.
  assert_eq(verdict("xs = [i for i in [1]]\n"), "ok")
}

///|
test "a mutual region's names are distinct" {
  assert_eq(
    verdict("def f():\n    return 1\ndef f():\n    return 2\n"),
    "duplicate name 'f' in mutual region",
  )
  // Separated by a statement, they are two regions and the second shadows.
  assert_eq(
    verdict("def f():\n    return 1\nx = 1\ndef f():\n    return 2\n"),
    "ok",
  )
}

// ---------------------------------------------------------------------------
// Classes

///|
let point : String = "@dataclass\nclass P:\n    x: Any\n    y: Any\n"

///|
test "a class declaration and its fields" {
  assert_eq(verdict(point + "p = P(1, 2)\n"), "ok")
  assert_eq(verdict(point + "p = P(1, y=2)\n"), "ok")
  assert_eq(verdict(point + "p = P(x=1, y=2)\n"), "ok")
  assert_eq(
    verdict(point + "p = P(1)\n"),
    "constructor for 'P' expects 2 arguments, got 1",
  )
  assert_eq(
    verdict(point + "p = P(1, 2, 3)\n"),
    "constructor for 'P' expects 2 arguments, got 3",
  )
  assert_eq(
    verdict(point + "p = P(1, z=2)\n"),
    "constructor keywords for 'P' must be y",
  )
  assert_eq(
    verdict("@dataclass\nclass P:\n    x: Any\n    x: Any\n"),
    "duplicate field name 'x' in class 'P'",
  )
  assert_eq(
    verdict(point + "@dataclass\nclass P:\n    z: Any\n"),
    "duplicate class name 'P' in module '__main__'",
  )
  assert_eq(
    verdict("@dataclass\nclass D(B):\n    z: Any\n"),
    "base class 'B' is not declared in this module",
  )
  assert_eq(verdict(point + "@dataclass\nclass D(P):\n    z: Any\n"), "ok")
  assert_eq(
    verdict(point + "@dataclass\nclass D(P):\n    x: Any\n"),
    "field 'x' clashes with inherited field from 'P'",
  )
  // Inherited fields come first, so the subclass takes three arguments.
  assert_eq(
    verdict(point + "@dataclass\nclass D(P):\n    z: Any\nd = D(1, 2, 3)\n"),
    "ok",
  )
  assert_eq(
    verdict(point + "@dataclass\nclass D(P):\n    z: Any\nd = D(1, 2)\n"),
    "constructor for 'D' expects 3 arguments, got 2",
  )
}

///|
test "a class is not a value" {
  assert_eq(
    verdict(point + "c = P\n"),
    "'P' refers to a class; classes are not first-class values",
  )
}

// ---------------------------------------------------------------------------
// Patterns

///|
test "a pattern's class, arity and keywords" {
  let head = point + "v = P(1, 2)\nmatch v:\n"
  assert_eq(verdict(head + "    case P(a, b):\n        print(a)\n"), "ok")
  assert_eq(verdict(head + "    case P(a, y=b):\n        print(a)\n"), "ok")
  assert_eq(
    verdict(head + "    case Q(a):\n        print(a)\n"),
    "'Q' is not a declared class",
  )
  assert_eq(
    verdict(head + "    case P(a):\n        print(a)\n"),
    "pattern for 'P' expects 2 sub-patterns, got 1",
  )
  assert_eq(
    verdict(head + "    case P(x=a, x=b):\n        print(a)\n"),
    "duplicate keyword in pattern for 'P'",
  )
  assert_eq(
    verdict(head + "    case P(a, z=b):\n        print(a)\n"),
    "pattern keywords for 'P' must be y",
  )
}

///|
test "a pattern binds each name once" {
  assert_eq(
    verdict(
      point + "v = P(1, 2)\nmatch v:\n    case P(a, a):\n        print(a)\n",
    ),
    "repeated variable in pattern 1",
  )
  assert_eq(
    verdict("v = 1\nmatch v:\n    case [a, a]:\n        print(a)\n"),
    "repeated variable in pattern 1",
  )
}

///|
test "a case a previous case already covers is unreachable" {
  assert_eq(
    verdict(
      "v = 1\nmatch v:\n    case _:\n        pass\n    case 1:\n        pass\n",
    ),
    "case 2 unreachable: subsumed by case 1",
  )
  assert_eq(
    verdict(
      "v = 1\nmatch v:\n    case 1:\n        pass\n    case 1:\n        pass\n",
    ),
    "case 2 unreachable: subsumed by case 1",
  )
  // `1` and `1.0` are equal in Python, so the second case cannot run.
  assert_eq(
    verdict(
      "v = 1\nmatch v:\n    case 1:\n        pass\n    case 1.0:\n        pass\n",
    ),
    "case 2 unreachable: subsumed by case 1",
  )
  // A list pattern and a tuple pattern match disjoint values.
  assert_eq(
    verdict(
      "v = 1\nmatch v:\n    case [a]:\n        pass\n    case (b,):\n        pass\n",
    ),
    "ok",
  )
  // A subclass pattern after its base is unreachable.
  assert_eq(
    verdict(
      point +
      "@dataclass\nclass D(P):\n    z: Any\nv = P(1, 2)\nmatch v:\n" +
      "    case P(a, b):\n        pass\n    case D(c, d, e):\n        pass\n",
    ),
    "case 2 unreachable: subsumed by case 1",
  )
  // The base after the subclass is fine: it covers more.
  assert_eq(
    verdict(
      point +
      "@dataclass\nclass D(P):\n    z: Any\nv = P(1, 2)\nmatch v:\n" +
      "    case D(c, d, e):\n        pass\n    case P(a, b):\n        pass\n",
    ),
    "ok",
  )
  assert_eq(
    verdict("v = 1\nmatch v:\n    case {\"a\": p, \"a\": q}:\n        pass\n"),
    "duplicate key 'a' in dict pattern",
  )
}

// ---------------------------------------------------------------------------
// Imports

///|
test "a module's members, and what an import binds" {
  assert_eq(
    program_verdict([("__main__", "import sys\nprint(sys.argv)\n")], "__main__"),
    "ok",
  )
  assert_eq(
    program_verdict([("__main__", "import nowhere\n")], "__main__"),
    "unknown module 'nowhere'",
  )
  assert_eq(
    program_verdict([("__main__", "import sys\nprint(sys)\n")], "__main__"),
    "'sys' refers to a module; modules are not first-class values",
  )
  assert_eq(
    program_verdict([("__main__", "import sys\nprint(sys.nope)\n")], "__main__"),
    "module 'sys' has no member 'nope'",
  )
  assert_eq(
    program_verdict([("__main__", "from math import nope\n")], "__main__"),
    "module 'math' has no member 'nope'",
  )
  assert_eq(
    program_verdict([("__main__", "x = 1\nimport sys\n")], "__main__"),
    "imports must precede all other statements",
  )
  assert_eq(
    program_verdict(
      [("__main__", "def f():\n    import sys\n    return 1\n")],
      "__main__",
    ),
    "import only allowed at module top level",
  )
}

///|
test "a from-import names a member that must be definitely assigned" {
  assert_eq(
    program_verdict(
      [("__main__", "from lib import x\nprint(x)\n"), ("lib", "x = 1\n")],
      "__main__",
    ),
    "ok",
  )
  assert_eq(
    program_verdict(
      [
        ("__main__", "from lib import x\nprint(x)\n"),
        ("lib", "c = True\nif c:\n    x = 1\n"),
      ],
      "__main__",
    ),
    "member 'x' of module 'lib' is not definitely assigned",
  )
  assert_eq(
    program_verdict(
      [("__main__", "from lib import y\n"), ("lib", "x = 1\n")],
      "__main__",
    ),
    "module 'lib' has no member 'y'",
  )
}

///|
test "import a.b.c binds a, whose b is a module whose c is the one imported" {
  let program = [
    ("__main__", "import a.b.c\nprint(a.b.c.x)\n"),
    ("a", "p = 1\n"),
    ("a.b", "q = 2\n"),
    ("a.b.c", "x = 3\n"),
  ]
  assert_eq(program_verdict(program, "__main__"), "ok")
  // The intermediate module is loaded, so its own members are reachable too.
  assert_eq(
    program_verdict(
      [
        ("__main__", "import a.b.c\nprint(a.b.q)\n"),
        ("a", "p = 1\n"),
        ("a.b", "q = 2\n"),
        ("a.b.c", "x = 3\n"),
      ],
      "__main__",
    ),
    "ok",
  )
  // A submodule that was never imported is named but not loaded.
  assert_eq(
    program_verdict(
      [
        ("__main__", "import a\nprint(a.b.q)\n"),
        ("a", "p = 1\n"),
        ("a.b", "q = 2\n"),
      ],
      "__main__",
    ),
    "submodule 'a.b' is not imported",
  )
  // A from-import of a submodule loads it.
  assert_eq(
    program_verdict(
      [
        ("__main__", "from a import b\nprint(b.q)\n"),
        ("a", "p = 1\n"),
        ("a.b", "q = 2\n"),
      ],
      "__main__",
    ),
    "ok",
  )
}

///|
test "a binding that shadows a submodule" {
  assert_eq(
    program_verdict(
      [
        ("__main__", "import a\nprint(a.p)\n"),
        ("a", "p = 1\nb = 2\n"),
        ("a.b", "q = 2\n"),
      ],
      "__main__",
    ),
    "binding 'b' clashes with submodule 'a.b'",
  )
}

///|
test "a module may not import its own descendant by name" {
  assert_eq(
    program_verdict(
      [
        ("__main__", "from a import p\n"),
        ("a", "import a.b\np = 1\n"),
        ("a.b", "q = 2\n"),
      ],
      "__main__",
    ),
    "'a.b' is a descendant of the importing module 'a'; import it with a from-import",
  )
}

///|
test "an import cycle is a program-level error naming the cycle" {
  assert_eq(
    program_verdict(
      [("__main__", "import helper\n"), ("helper", "import __main__\n")],
      "__main__",
    ),
    "import cycle: __main__ -> helper -> __main__",
  )
  assert_eq(program_verdict([("m", "import m\n")], "m"), "import cycle: m -> m")
}
