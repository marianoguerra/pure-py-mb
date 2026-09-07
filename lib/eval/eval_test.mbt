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
    Terminated(k, _) => output + "!" + k.to_text()
    Undefined(op) => output + "!stuck: " + op
    Suspended => output + "!suspended"
  }
}

///|
/// Where a program aborted, as `module:line:col`, or why it did not abort.
fn site(modules : Array[(String, String)]) -> String {
  let parsed : Map[String, @ast.Module] = Map([])
  for m in modules {
    parsed[m.0] = @parser.parse_string(m.1, name=m.0) catch {
      e => return "syntax in \{m.0}: \{e}"
    }
  }
  let tree = @program.SourceTree::of(parsed)
  match @eval.run_program(tree).1 {
    Terminated(_, Some(s)) => s.to_display()
    Terminated(_, None) => "terminated nowhere"
    Finished => "did not terminate: finished"
    Undefined(op) => "did not terminate: stuck: " + op
    Suspended => "did not terminate: suspended"
  }
}

///|
/// The same, for a single-module program.
fn site1(source : String) -> String {
  site([("__main__", source)])
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
/// `+` and `*` over sequences, through the whole interpreter.
///
/// The table in `value/arith_table_test.mbt` is the differential against
/// CPython; these are the same operations reached from source, which is the
/// path `pure-py run` takes and the one that was broken. A recursion over a
/// list, rebuilding the spine rather than mutating it, is the shape every
/// program in the subset has to use, so it is the case worth running whole.
test "sequences concatenate and repeat" {
  assert_eq(run("print(\"a\" + \"b\")\n"), "ab\n")
  assert_eq(run("print(\"a\" + \"b\" + \"c\")\n"), "abc\n")
  assert_eq(run("print(\"\" + \"a\")\n"), "a\n")
  assert_eq(run("print([1] + [2])\n"), "[1, 2]\n")
  assert_eq(run("print([] + [1])\n"), "[1]\n")
  assert_eq(run("print((1,) + (2,))\n"), "(1, 2)\n")
  assert_eq(run("print(\"ab\" * 3)\n"), "ababab\n")
  assert_eq(run("print(3 * \"ab\")\n"), "ababab\n")
  assert_eq(run("print([1, 2] * 2)\n"), "[1, 2, 1, 2]\n")
  assert_eq(run("print((1,) * 2)\n"), "(1, 1)\n")
  // A non-positive count is the empty sequence, not an error.
  assert_eq(run("print(\"a\" * 0, [1] * 0, [1] * -1)\n"), " [] []\n")
  // Concatenation does not mutate: the operands survive it.
  assert_eq(run("xs = [1]\nys = xs + [2]\nprint(xs, ys)\n"), "[1] [1, 2]\n")
}

///|
/// The rows the fix must NOT swallow. `1 + "a"` is the conformance suite's own
/// `binop_non_number.py`, and it stays a TypeError; so does every pair Python
/// refuses. `True` stays undefined, because a bool is not a number here.
test "concatenation does not widen what TypeError covers" {
  assert_eq(run("print(1 + \"a\")\n"), "!TypeError")
  assert_eq(run("print(\"a\" + 1)\n"), "!TypeError")
  assert_eq(run("print(\"a\" - \"b\")\n"), "!TypeError")
  assert_eq(run("print([1] - [2])\n"), "!TypeError")
  // A list and a tuple do not concatenate in Python either.
  assert_eq(run("print([1] + (2,))\n"), "!TypeError")
  assert_eq(run("print((1,) + [2])\n"), "!TypeError")
  assert_eq(run("print(1 + [2])\n"), "!TypeError")
  assert_eq(run("print({\"a\": 1} + {\"b\": 2})\n"), "!TypeError")
  // Neither operand of `*` is a count.
  assert_eq(run("print(\"a\" * \"b\")\n"), "!TypeError")
  assert_eq(run("print(\"a\" * 1.5)\n"), "!TypeError")
  // A bool is not a number, and not a count -- and that is UNDEFINED rather
  // than an abort, because Python raises nothing there.
  assert_eq(
    run("print(True + 1)\n"),
    "!stuck: '+' on a bool: PurePy does not make a bool a number",
  )
  assert_eq(
    run("print(\"a\" * True)\n"),
    "!stuck: '*' on a bool: PurePy does not make a bool a number",
  )
}

///|
/// A bool in an operator is undefined, not a `TypeError`.
///
/// A termination kind names the exception Python raises in the same
/// circumstances, and Python raises none of these -- `True + 1` is 2 and
/// `-False` is 0. So the answer is that this subset has no rule, which is
/// what `True == 1` and `True < 2` already said.
test "a bool never reaches arithmetic" {
  let no_rule = "!stuck: '+' on a bool: PurePy does not make a bool a number"
  assert_eq(run("print(True + 1)\n"), no_rule)
  assert_eq(run("print(1 + True)\n"), no_rule)
  assert_eq(run("print(+True)\n"), no_rule)
  assert_eq(
    run("print(-False)\n"),
    "!stuck: '-' on a bool: PurePy does not make a bool a number",
  )
  // The bool can arrive from a comparison; it is the value that decides.
  assert_eq(
    run("print(-(1 == 1))\n"),
    "!stuck: '-' on a bool: PurePy does not make a bool a number",
  )
  assert_eq(
    run("print(63 % False)\n"),
    "!stuck: '%' on a bool: PurePy does not make a bool a number",
  )
  // A bool against a non-number is a TypeError under Python too, so it keeps
  // being one here.
  assert_eq(run("print(True + None)\n"), "!TypeError")
  // `not` is the one operator a bool belongs to.
  assert_eq(run("print(not True, True and False)\n"), "False False\n")
}

///|
/// Every ordering against a nan is False, and a zero remainder takes the sign
/// of its divisor. Neither is reachable from a literal: PurePy has no `float`
/// builtin, so a nan and an infinity are built out of an overflow, the way a
/// program in the subset has to build them.
test "nan orders as False, and a zero remainder is signed" {
  let nan = "nan = 1e308 * 10.0 - 1e308 * 10.0\n"
  assert_eq(run(nan + "print(nan < 1.0, nan > 1.0)\n"), "False False\n")
  assert_eq(run(nan + "print(nan <= 1.0, nan >= 1.0)\n"), "False False\n")
  assert_eq(run(nan + "print(1.0 < nan, nan < nan)\n"), "False False\n")
  // `==` and `!=` had their own rule already, and it still holds.
  assert_eq(run(nan + "print(nan == nan, nan != nan)\n"), "False True\n")
  // An unordered pair of KINDS stays undefined, nan or not.
  assert_eq(
    run(nan + "print(nan < \"a\")\n"),
    "!stuck: '<' between float and str",
  )
  assert_eq(run("print(1.5 % -0.5, 4.0 % -2.0)\n"), "-0.0 -0.0\n")
  assert_eq(run("print(-1.5 % 0.5, -4.0 % 2.0)\n"), "0.0 0.0\n")
  assert_eq(run("print(7.5 % -2.0, -7.5 % 2.0)\n"), "-0.5 0.5\n")
}

///|
/// The recursion the subset forces on anything that builds a sequence: no
/// mutation, so every step concatenates. This is what `pure-py run` could not
/// evaluate at all.
test "a spine rebuilt by concatenation, as the subset requires" {
  let source =
    #|def rest_from(xs, i):
    #|    if i >= len(xs):
    #|        return []
    #|    return [xs[i]] + rest_from(xs, i + 1)
    #|
    #|
    #|def joined(xs, sep, i):
    #|    if i >= len(xs):
    #|        return ""
    #|    if i == len(xs) - 1:
    #|        return xs[i]
    #|    return xs[i] + sep + joined(xs, sep, i + 1)
    #|
    #|
    #|print(rest_from([1, 2, 3], 1))
    #|print(joined(["a", "b", "c"], "/", 0))
    #|
  assert_eq(run(source), "[2, 3]\na/b/c\n")
}

///|
/// `%` on a string is Python's printf formatting. PurePy models none, so the
/// answer is "no rule" rather than TypeError -- Python does not raise one.
test "string formatting is undefined, not an error" {
  assert_eq(
    run("print(\"%d\" % 3)\n"),
    "!stuck: '%' on a string: PurePy has no string formatting",
  )
  assert_eq(
    run("print(\"a\" % [])\n"),
    "!stuck: '%' on a string: PurePy has no string formatting",
  )
  // A string on the RIGHT is arithmetic on a non-number, and Python does
  // raise there.
  assert_eq(run("print(1 % \"a\")\n"), "!TypeError")
}

///|
/// Branches the unit tests never reached, found by `moon coverage analyze`
/// and answered against CPython. Equality between an object and a value of
/// another kind, and equality reached through a float on the left, are the
/// two the conformance suite happens not to contain.
test "equality over objects, floats and mixed kinds" {
  let p =
    #|from dataclasses import dataclass
    #|from typing import Any
    #|
    #|
    #|@dataclass
    #|class P:
    #|    x: Any
    #|    y: Any
    #|
    #|
  assert_eq(
    run(p + "print(P(1, 2) == P(1, 2), P(1, 2) == P(1, 3))\n"),
    "True False\n",
  )
  // Nested, so equality recurses through the fields.
  assert_eq(run(p + "print(P(1, [2]) == P(1, [2]))\n"), "True\n")
  // An object against another kind has no rule, as any unrelated pair does.
  assert_eq(run(p + "print(P(1, 2) == 1)\n"), "!stuck: == between P and int")
  // A float on the left of `==` with an int on the right: the comparison is
  // exact, so a large integer is not made equal to the double nearest it.
  assert_eq(run("print(1.0 == 1, 2.0 == 3)\n"), "True False\n")
  assert_eq(run("print(1e23 == 100000000000000000000000)\n"), "False\n")
}

///|
/// Subscripting, and the three ways it can fail. `getitem`'s error arms were
/// uncovered; each is a different answer and Python agrees with all three.
test "subscripting fails three different ways" {
  assert_eq(run("print([1, 2][1], (3, 4)[0], \"xy\"[1])\n"), "2 3 y\n")
  assert_eq(run("print([1, 2][-1])\n"), "2\n")
  assert_eq(run("print([1, 2][2])\n"), "!IndexError")
  assert_eq(run("print({\"a\": 1}[\"b\"])\n"), "!KeyError")
  // A subscript of something with no elements, and a key of the wrong kind.
  assert_eq(run("print(1[0])\n"), "!TypeError")
  assert_eq(run("print([1, 2][\"a\"])\n"), "!TypeError")
  // A dict subscripted by a non-string is undefined, not a KeyError: PurePy
  // dictionaries are keyed by strings.
  assert_eq(
    run("print({\"a\": 1}[1])\n"),
    "!stuck: subscripting a dict with int",
  )
}

///|
/// `math`'s domain errors, and the arities the primitives reject. Python
/// raises ValueError for a log of a non-positive, which is not a termination
/// kind, so PurePy has no rule rather than an abort.
test "the primitives reject what they cannot answer" {
  assert_eq(
    program([("__main__", "import math\nprint(math.log(1.0))\n")]),
    "0.0\n",
  )
  assert_eq(
    program([("__main__", "import math\nprint(math.exp(0.0))\n")]),
    "1.0\n",
  )
  assert_eq(
    program([("__main__", "import math\nprint(math.log(0.0))\n")]),
    "!stuck: the logarithm of a number that is not positive",
  )
  assert_eq(run("print(range(1, 3))\n"), "!stuck: range with 2 arguments")
  assert_eq(run("print(range(\"a\"))\n"), "!stuck: range of str")
  assert_eq(run("print(len(1))\n"), "!TypeError")
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

// ---------------------------------------------------------------------------
// Where a run aborted
//
// The specification fixes which kind a run yields and leaves reporting open,
// so none of this changes a `Termination` -- but a position that points at
// the wrong expression, or at the right line of the wrong file, is worse than
// no position, and that is what these pin down.

///|
test "the site is the innermost expression that aborted" {
  // The subscript, not the sum that contains it.
  assert_eq(site1("d = {}\nprint(1 + d[\"k\"])\n"), "__main__:2:10")
  // The division, not the call that wraps it.
  assert_eq(site1("n = 0\nprint(len([1]) + 1 // n)\n"), "__main__:2:17")
  // A binary operator on operands the semantics has no rule for.
  assert_eq(site1("print(1 + None)\n"), "__main__:1:6")
}

///|
test "the site is a column, and it counts code points" {
  // The identifier before the subscript is three characters and five bytes.
  // A column that counted bytes would say 11.
  assert_eq(site1("héé = {}\nprint(héé[\"k\"])\n"), "__main__:2:6")
}

///|
test "a statement's own abort is sited at the statement" {
  assert_eq(site1("assert False\n"), "__main__:1:0")
  assert_eq(site1("x = 1\nassert x == 2, \"nope\"\n"), "__main__:2:0")
}

///|
test "the site names the module the code was WRITTEN in" {
  // `pick` is called from `__main__` and fails in `helper`. The import stack
  // says `__main__` at that moment; the closure says `helper`, and the
  // closure is right.
  assert_eq(
    site([
      ("helper", "def pick(d):\n    return d[\"missing\"]\n"),
      ("__main__", "from helper import pick\nprint(pick({}))\n"),
    ]),
    "helper:2:11",
  )
  // A lambda carries its module too, and calling it from another one does
  // not move the blame.
  assert_eq(
    site([
      ("helper", "def make():\n    return lambda d: d[\"missing\"]\n"),
      ("__main__", "from helper import make\nf = make()\nprint(f({}))\n"),
    ]),
    "helper:2:21",
  )
  // And control comes back: after the call returns, an abort in `__main__`
  // is `__main__`'s again.
  assert_eq(
    site([
      ("helper", "def ok(d):\n    return 1\n"),
      ("__main__", "from helper import ok\nx = ok({})\nprint({}[\"k\"])\n"),
    ]),
    "__main__:3:6",
  )
}

///|
test "a module that aborts while loading is sited in itself" {
  assert_eq(
    site([
      ("helper", "boom = {}[\"k\"]\n"),
      ("__main__", "import helper\nprint(1)\n"),
    ]),
    "helper:1:7",
  )
}

///|
test "an exit is a termination like any other, and it has a position" {
  assert_eq(site1("import sys\nsys.exit(2)\n"), "__main__:2:0")
}

///|
test "a tree nobody read has nowhere to point at" {
  // What a code generator builds: real statements, `nowhere` spans. A site
  // made of those would be `1:0` for everything, which reads like a position
  // and is not one, so there is none.
  let built : @ast.Module = {
    body: [
      @ast.Stmt::expr_stmt(
        @ast.Expr::subscript(@ast.Expr::dict([]), @ast.Expr::str("k")),
      ),
    ],
    span: @basic.nowhere,
  }
  let tree = @program.SourceTree::of(Map([("__main__", built)]))
  match @eval.run_program(tree).1 {
    Terminated(k, site) => {
      assert_eq(k.to_text(), "KeyError")
      assert_true(site is None)
    }
    _ => fail("the missing key is a KeyError wherever the tree came from")
  }
}
