///|
/// The operational semantics, on whole programs: what a rule does is easier
/// to read as a source and its output than as a constructed environment.
fn run(source : String) -> String {
  program([("__main__", source)])
}

///|
/// A program of several modules, run from `__main__`.
fn program(modules : Array[(String, String)]) -> String {
  let parsed : Map[String, @ast.Module] = Map([])
  for m in modules {
    parsed[m.0] = @parser.parse_string(m.1, name=m.0) catch {
      e => return "syntax in \{m.0}: \{e}"
    }
  }
  let tree = @program.SourceTree::of(parsed)
  let (output, result) = @eval.run_program(tree, argv=["main.py"])
  match result {
    Finished => output
    Terminated(k) => output + "!" + k.to_text()
    Undefined(op) => output + "!stuck: " + op
  }
}

// ---------------------------------------------------------------------------
// Statements

///|
test "assignment, sequencing and printing" {
  assert_eq(run("x = 1\nprint(x)\n"), "1\n")
  assert_eq(run("x = 1\ny = x + 1\nprint(x, y)\n"), "1 2\n")
  assert_eq(run("print()\n"), "\n")
  assert_eq(run("pass\n"), "")
  assert_eq(run("print(\"a\")\nprint(\"b\")\n"), "a\nb\n")
}

///|
test "an if takes a branch only on an actual bool" {
  assert_eq(run("c = True\nif c:\n    print(1)\nelse:\n    print(2)\n"), "1\n")
  assert_eq(run("c = False\nif c:\n    print(1)\nelse:\n    print(2)\n"), "2\n")
  assert_eq(run("c = False\nif c:\n    print(1)\n"), "")
  // Python's truthiness is not PurePy's.
  assert_eq(run("if 5:\n    print(1)\n"), "!stuck: an if condition on int")
}

///|
test "assert evaluates its message only when the condition is false" {
  assert_eq(run("assert True\nprint(1)\n"), "1\n")
  assert_eq(run("assert True, \"never\"\nprint(1)\n"), "1\n")
  assert_eq(run("assert False\n"), "!AssertionError")
  assert_eq(run("assert False, \"boom\"\n"), "!AssertionError: boom")
  // A non-bool condition and a non-string message are both undefined.
  assert_eq(run("assert 0\n"), "!stuck: an assertion on int")
  assert_eq(
    run("assert False, 1\n"),
    "!stuck: an assertion message of type int",
  )
}

///|
test "a function body's locals do not escape it" {
  assert_eq(
    run("def f():\n    y = 2\n    return y\nprint(f())\ny = 1\nprint(y)\n"),
    "2\n1\n",
  )
  // A return with no value returns None.
  assert_eq(run("def f():\n    return\nprint(f())\n"), "None\n")
  // A body that completes without returning also gives None.
  assert_eq(run("def f():\n    x = 1\nprint(f())\n"), "None\n")
}

///|
/// The rule that makes a mutual region work: calling one of its functions
/// rebinds the WHOLE region in the callee's environment.
test "mutually recursive functions see each other" {
  assert_eq(
    run(
      "def even(n):\n    if n == 0:\n        return True\n    return odd(n - 1)\n" +
      "def odd(n):\n    if n == 0:\n        return False\n    return even(n - 1)\n" +
      "print(even(4), odd(4))\n",
    ),
    "True False\n",
  )
}

///|
test "a closure sees the environment it was made in" {
  assert_eq(run("i = 1\nf = lambda x: x + i\nprint(f(2))\n"), "3\n")
  // A comprehension's variable is local to it.
  assert_eq(run("xs = [lambda: 1 for i in [1, 2]]\nprint(len(xs))\n"), "2\n")
}

///|
test "the wrong number of arguments aborts with TypeError" {
  assert_eq(run("f = lambda x: x\nprint(f(1, 2))\n"), "!TypeError")
  assert_eq(run("def f(x):\n    return x\nprint(f())\n"), "!TypeError")
  assert_eq(run("x = 1\nprint(x(1))\n"), "!TypeError")
}

// ---------------------------------------------------------------------------
// Patterns

///|
let point : String = "@dataclass\nclass P:\n    x: Any\n    y: Any\n"

///|
test "a match takes the first case that matches" {
  let head = "v = 2\nmatch v:\n"
  assert_eq(
    run(
      head +
      "    case 1:\n        print(\"one\")\n    case _:\n        print(\"other\")\n",
    ),
    "other\n",
  )
  assert_eq(
    run(
      "v = 1\nmatch v:\n    case 1:\n        print(\"one\")\n    case _:\n        print(\"other\")\n",
    ),
    "one\n",
  )
  // A match that falls through does nothing at all.
  assert_eq(run("v = 2\nmatch v:\n    case 1:\n        print(1)\n"), "")
  // A negated literal.
  assert_eq(
    run(
      "v = -1\nmatch v:\n    case -1:\n        print(\"neg\")\n    case _:\n        print(\"no\")\n",
    ),
    "neg\n",
  )
}

///|
test "a pattern binds, and its bindings outlive the match" {
  assert_eq(
    run("v = 5\nmatch v:\n    case a:\n        pass\nprint(a)\n"),
    "5\n",
  )
  assert_eq(
    run("v = [1, 2]\nmatch v:\n    case [a, b]:\n        print(a, b)\n"),
    "1 2\n",
  )
  assert_eq(
    run("v = (1, 2)\nmatch v:\n    case (a, b):\n        print(a, b)\n"),
    "1 2\n",
  )
  assert_eq(
    run("v = {\"k\": 7}\nmatch v:\n    case {\"k\": a}:\n        print(a)\n"),
    "7\n",
  )
}

///|
/// The three cases the spec's rules leave narrower than "anything else".
test "a pattern and a value that are not comparable" {
  // A list pattern against a tuple: no rule covers it.
  assert_eq(
    run("v = (1,)\nmatch v:\n    case [a]:\n        print(a)\n"),
    "!stuck: a list pattern against tuple",
  )
  // A tuple pattern against an integer: an honest no-match.
  assert_eq(run("v = 1\nmatch v:\n    case (a,):\n        print(a)\n"), "")
  // A literal pattern against a list: `eq` between unrelated kinds.
  assert_eq(
    run("v = [1]\nmatch v:\n    case 1:\n        print(1)\n"),
    "!stuck: a literal pattern against list",
  )
}

///|
test "a constructor pattern matches a subclass and binds its own fields" {
  let classes = point + "@dataclass\nclass D(P):\n    z: Any\n"
  assert_eq(
    run(
      classes +
      "v = D(1, 2, 3)\nmatch v:\n    case P(a, b):\n        print(a, b)\n",
    ),
    "1 2\n",
  )
  // The other way round does not match.
  assert_eq(
    run(
      classes +
      "v = P(1, 2)\nmatch v:\n    case D(a, b, c):\n        print(a)\n    case _:\n        print(\"no\")\n",
    ),
    "no\n",
  )
  assert_eq(
    run(
      point +
      "v = P(1, 2)\nmatch v:\n    case P(a, y=b):\n        print(a, b)\n",
    ),
    "1 2\n",
  )
}

// ---------------------------------------------------------------------------
// Values

///|
test "objects print with their fields, inherited first" {
  assert_eq(run(point + "print(P(1, \"a\"))\n"), "P(x=1, y='a')\n")
  assert_eq(
    run(point + "@dataclass\nclass D(P):\n    z: Any\nprint(D(1, 2, 3))\n"),
    "D(x=1, y=2, z=3)\n",
  )
  // A field is reached by attribute; anything else aborts.
  assert_eq(run(point + "p = P(1, 2)\nprint(p.x)\n"), "1\n")
  assert_eq(run(point + "p = P(1, 2)\nprint(p.q)\n"), "!AttributeError")
  // The attributes of a built-in value are undefined.
  assert_eq(run("xs = [1]\nprint(xs.append)\n"), "!stuck: an attribute of list")
}

///|
test "comprehensions" {
  assert_eq(run("print([x for x in [1, 2, 3]])\n"), "[1, 2, 3]\n")
  assert_eq(run("print([x for x in [1, 2, 3] if x > 1])\n"), "[2, 3]\n")
  assert_eq(
    run("print([x for x in [1, 2] for y in [3, 4]])\n"),
    "[1, 1, 2, 2]\n",
  )
  assert_eq(
    run("print({x: 1 for x in [\"a\", \"b\"]})\n"),
    "{'a': 1, 'b': 1}\n",
  )
  // A generator over something with no elements aborts.
  assert_eq(run("print([x for x in 1])\n"), "!TypeError")
  // A dictionary iterates over its keys.
  assert_eq(run("print([k for k in {\"a\": 1, \"b\": 2}])\n"), "['a', 'b']\n")
}

///|
test "the builtins" {
  assert_eq(
    run("print(len([1, 2]), len(\"abc\"), len({\"a\": 1}))\n"),
    "2 3 1\n",
  )
  assert_eq(run("print(len(1))\n"), "!TypeError")
  assert_eq(run("print(range(3))\n"), "[0, 1, 2]\n")
  assert_eq(run("print(range(0))\n"), "[]\n")
  assert_eq(run("print(range(-1))\n"), "[]\n")
}

///|
test "sys.exit ends the run with its status and prints nothing more" {
  assert_eq(
    program([("__main__", "import sys\nprint(1)\nsys.exit(2)\nprint(3)\n")]),
    "1\n!SystemExit: 2",
  )
  assert_eq(
    program([("__main__", "import sys\nsys.exit()\n")]),
    "!SystemExit: 0",
  )
}

///|
test "math is over floats, and its undefined cases are undefined" {
  assert_eq(
    program([("__main__", "import math\nprint(math.sqrt(4))\n")]),
    "2.0\n",
  )
  assert_eq(
    program([
      ("__main__", "import math\nprint(math.floor(1.7), math.ceil(1.2))\n"),
    ]),
    "1 2\n",
  )
  assert_eq(
    program([("__main__", "import math\nprint(math.pi)\n")]),
    "3.141592653589793\n",
  )
  assert_eq(
    program([("__main__", "import math\nprint(math.sqrt(-1))\n")]),
    "!stuck: the square root of a negative number",
  )
}

// ---------------------------------------------------------------------------
// Modules

///|
test "a module is loaded once, however many times it is imported" {
  // The spec needs no cache, because loading is deterministic; what it prints
  // is not, and CPython prints once.
  assert_eq(
    program([
      ("__main__", "import pkg.sub\nfrom pkg import sub\nprint(sub.x)\n"),
      ("pkg", "print(\"loading pkg\")\n"),
      ("pkg.sub", "print(\"loading sub\")\nx = 1\n"),
    ]),
    "loading pkg\nloading sub\n1\n",
  )
}

///|
test "a dotted import binds the root, and the ancestors load first" {
  assert_eq(
    program([
      ("__main__", "import a.b.c\nprint(a.b.c.x, a.b.y, a.z)\n"),
      ("a", "z = 1\n"),
      ("a.b", "y = 2\n"),
      ("a.b.c", "x = 3\n"),
    ]),
    "3 2 1\n",
  )
}

///|
test "a later import of the same name wins over an earlier one" {
  assert_eq(
    program([
      ("__main__", "from x import y\nimport y.z\nprint(y.z.b)\n"),
      ("x", ""),
      ("x.y", "a = 1\n"),
      ("y", ""),
      ("y.z", "b = 2\n"),
    ]),
    "2\n",
  )
}

///|
test "__name__ is set before the imports, so a from-import can rebind it" {
  assert_eq(run("print(__name__)\n"), "__main__\n")
  assert_eq(
    program([
      ("__main__", "from lib import __name__\nprint(__name__)\n"),
      ("lib", "x = 1\n"),
    ]),
    "lib\n",
  )
}

///|
test "a module that aborts while loading aborts the run" {
  assert_eq(
    program([("__main__", "import lib\nprint(1)\n"), ("lib", "assert False\n")]),
    "!AssertionError",
  )
  // An ancestor that aborts stops the descendant from loading.
  assert_eq(
    program([
      ("__main__", "import pkg.sub\n"),
      ("pkg", "assert False, \"bad ancestor\"\n"),
      ("pkg.sub", "print(\"never\")\n"),
    ]),
    "!AssertionError: bad ancestor",
  )
}

///|
test "sys.argv is the entry path and the arguments after it" {
  assert_eq(
    program([("__main__", "import sys\nprint(sys.argv)\n")]),
    "['main.py']\n",
  )
}
