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
fn program_verdict(modules : Array[(String, String)]) -> String {
  let parsed : Map[String, @ast.Module] = Map([])
  for m in modules {
    parsed[m.0] = @parser.parse_string(m.1) catch {
      e => return "syntax in \{m.0}: \{e}"
    }
  }
  match @check.check_program(@program.SourceTree::of(parsed)) {
    None => "ok"
    Some(d) => d.message()
  }
}

// ---------------------------------------------------------------------------
// Declarations and definite assignment

///|
test "a variable is declared once, with its type, and assigned once" {
  assert_eq(verdict("x: int = 1\nprint(x)\n"), "ok")
  assert_eq(verdict("x: int\nx = 1\nprint(x)\n"), "ok")
  assert_eq(verdict("x = 1\n"), "'x' is assigned but never declared")
  assert_eq(verdict("x: int = 1\nx = 2\n"), "'x' is already assigned")
  assert_eq(verdict("x: int = 1\nx: int = 2\n"), "'x' is already declared")
  assert_eq(
    verdict("x = 1\nx: int\n"),
    "'x' is assigned before its declaration",
  )
  assert_eq(
    verdict("x: int\nprint(x)\n"),
    "'x' is declared but not yet assigned",
  )
  assert_eq(verdict("print(x)\nx: int = 1\n"), "'x' is unbound")
  assert_eq(verdict("print(x)\n"), "'x' is not defined")
  // A declaration is checked against what it is assigned.
  assert_eq(
    verdict("x: int\nx = 'a'\n"),
    "expected type int, given Literal['a']",
  )
}

///|
test "a variable assigned on some paths is not definitely assigned" {
  let c = "def c() -> bool:\n    return True\n"
  assert_eq(
    verdict(c + "x: int\nif c():\n    x = 1\nprint(x)\n"),
    "'x' is not definitely assigned",
  )
  assert_eq(
    verdict(c + "x: int\nif c():\n    x = 1\nx = 2\n"),
    "'x' may already be assigned",
  )
  // Assigned in both branches.
  assert_eq(
    verdict(c + "x: int\nif c():\n    x = 1\nelse:\n    x = 2\nprint(x)\n"),
    "ok",
  )
  // A branch that returns does not have to assign.
  assert_eq(
    verdict(
      "def f(c: bool) -> int:\n    x: int\n    if c:\n        x = 1\n    else:\n        return 0\n    return x\n",
    ),
    "ok",
  )
}

///|
test "a pattern variable is bound once" {
  let m = "def f(x: int) -> int:\n    match x:\n        case y:\n            return y\n"
  assert_eq(verdict(m), "ok")
  assert_eq(
    verdict(
      "def f(y: int) -> int:\n    match y:\n        case y:\n            return y\n",
    ),
    "'y' is already declared",
  )
}

///|
test "a comprehension variable may not be captured by a lambda in it" {
  assert_eq(
    verdict(
      "from typing import Callable\nfs: list[Callable[[], int]] = [lambda: i for i in [1, 2]]\n",
    ),
    "'i' bound by generator, captured by lambda",
  )
}

// ---------------------------------------------------------------------------
// Types

///|
test "an annotation must name types in scope" {
  assert_eq(verdict("x: int = 1\n"), "ok")
  assert_eq(verdict("x: Q = 1\n"), "'Q' is not a declared class")
  // `Callable` and `Literal` are typing's, and have to be imported.
  assert_eq(
    verdict("x: Literal[1] = 1\n"),
    "'Literal' is not bound as a predefined name",
  )
  assert_eq(verdict("from typing import Literal\nx: Literal[1] = 1\n"), "ok")
  // A predefined name is not a value.
  assert_eq(
    verdict("x: int = int\n"),
    "'int' is usable only in annotations or as a decorator",
  )
}

///|
test "operators resolve to an overload or are refused" {
  assert_eq(verdict("x: float = 1 + 2.5\n"), "ok")
  assert_eq(verdict("x: str = 'a' * 3\n"), "ok")
  assert_eq(
    verdict("print(1 + 'a')\n"),
    "no overload of '+' at operand types Literal[1] and Literal['a']",
  )
  // A bool is not a number in PurePy.
  assert_eq(
    verdict("print(True + 1)\n"),
    "no overload of '+' at operand types Literal[True] and Literal[1]",
  )
  assert_eq(
    verdict("print(not 1)\n"),
    "no overload of 'not' at operand type Literal[1]",
  )
  // `int ** int` is an int only for a non-negative literal exponent.
  assert_eq(verdict("x: int = 2 ** 3\n"), "ok")
  assert_eq(verdict("x: int = 2 ** -1\n"), "expected type int, given float")
}

///|
test "a call is checked against the callee's type" {
  let f = "def f(x: int) -> str:\n    return 'a'\n"
  assert_eq(verdict(f + "y: str = f(1)\n"), "ok")
  assert_eq(verdict(f + "f('a')\n"), "expected type int, given Literal['a']")
  assert_eq(verdict(f + "f(1, 2)\n"), "call expects 1 arguments, given 2")
  assert_eq(
    verdict("x: int = 1\nx(2)\n"),
    "values of type int cannot be called",
  )
  // A function that may fall off its end must allow None.
  assert_eq(
    verdict("def g(c: bool) -> int:\n    if c:\n        return 1\n"),
    "'g' declares result type int but does not always return",
  )
}

///|
test "an expression with no type of its own needs one to be checked against" {
  assert_eq(
    verdict("print(len([lambda x: x]))\n"),
    "cannot infer type of this expression",
  )
  assert_eq(verdict("print(len([]))\n"), "cannot infer type of this expression")
  // Checked against a type, a lambda takes it -- or says why it cannot.
  assert_eq(
    verdict("print(lambda x: x)\n"),
    "expected type object, given a lambda",
  )
  assert_eq(verdict("xs: list[int] = []\n"), "ok")
  assert_eq(
    verdict(
      "from typing import Callable\nf: Callable[[int], int] = lambda x, y: x\n",
    ),
    "expected type Callable[[int], int], given a lambda of 2 parameters",
  )
}

///|
test "subscripts by container type" {
  assert_eq(verdict("t: tuple[int, str] = (1, 'a')\nx: str = t[1]\n"), "ok")
  assert_eq(
    verdict("t: tuple[int, str] = (1, 'a')\nprint(t[2])\n"),
    "index 2 out of range for tuple of length 2",
  )
  assert_eq(verdict("d: dict[str, int] = {'k': 1}\nx: int = d['k']\n"), "ok")
  assert_eq(
    verdict("x: int = 1\nprint(x[0])\n"),
    "values of type int cannot be subscripted",
  )
}

// ---------------------------------------------------------------------------
// Classes and patterns

///|
let point : String = "from dataclasses import dataclass\n@dataclass\nclass P:\n    x: int\n    y: int\n"

///|
test "a constructor is checked against the fields" {
  assert_eq(verdict(point + "p: P = P(1, y=2)\nz: int = p.x\n"), "ok")
  assert_eq(
    verdict(point + "print(P(1))\n"),
    "constructor for 'P' expects 2 arguments, got 1",
  )
  assert_eq(
    verdict(point + "print(P(1, 'a'))\n"),
    "expected type int, given Literal['a']",
  )
  assert_eq(
    verdict(point + "p: P = P(1, 2)\nprint(p.w)\n"),
    "class 'P' has no field 'w'",
  )
  // A class is a declaration, and a name is declared once.
  assert_eq(verdict(point + "P = 1\n"), "'P' is already declared")
}

///|
test "a case no value can reach is refused" {
  let m = "def f(x: int | str) -> int:\n    match x:\n"
  assert_eq(
    verdict(
      m +
      "        case int():\n            return 1\n        case str():\n            return 2\n",
    ),
    "'int' is not a declared class",
  )
  assert_eq(
    verdict(
      m +
      "        case 1:\n            return 1\n        case _:\n            return 2\n        case 2:\n            return 3\n",
    ),
    "case 2 is unreachable",
  )
  // Exhaustive over the classes of a union: the function always returns.
  assert_eq(
    verdict(
      point +
      "@dataclass\nclass Q:\n    z: int\n" +
      "def g(v: P | Q) -> int:\n    match v:\n        case P(a, b):\n            return a\n        case Q(c):\n            return c\n",
    ),
    "ok",
  )
  // A list pattern against a tuple type is a kind error.
  assert_eq(
    verdict(
      "t: tuple[int, int] = (1, 2)\nmatch t:\n    case [a, b]:\n        pass\n",
    ),
    "list pattern at tuple[int, int], which has tuple values",
  )
}

// ---------------------------------------------------------------------------
// Programs

///|
test "a program's modules are typed across imports" {
  assert_eq(
    program_verdict([
      ("lib", point + "def mk(n: int) -> P:\n    return P(n, n)\n"),
      ("__main__", "from lib import mk, P\np: P = mk(1)\nx: int = p.y\n"),
    ]),
    "ok",
  )
  assert_eq(
    program_verdict([
      ("lib", "x: int = 1\n"),
      ("__main__", "import lib\ny: str = lib.x\n"),
    ]),
    "__main__: expected type str, given int",
  )
  // A member declared and never assigned is not one an import can use.
  assert_eq(
    program_verdict([("lib", "x: int\n"), ("__main__", "from lib import x\n")]),
    "__main__: member 'x' of module 'lib' is not definitely assigned",
  )
  assert_eq(
    program_verdict([("__main__", "import nope\n")]),
    "__main__: unknown module 'nope'",
  )
  assert_eq(
    program_verdict([
      ("a", "import b\n"),
      ("b", "import a\n"),
      ("__main__", "import a\n"),
    ]),
    "import cycle: a -> b -> a",
  )
}

///|
test "a mutual type region: aliases see every definition, classes the earlier ones" {
  let dc = "from dataclasses import dataclass\n"
  let tree = dc +
    "type Tree = Leaf | Node\n@dataclass\nclass Leaf:\n    pass\n@dataclass\nclass Node:\n    kids: list[Tree]\n"
  assert_eq(verdict(tree + "t: Tree = Node([Leaf()])\n"), "ok")
  // A class's annotations are evaluated when it is defined.
  assert_eq(
    verdict(dc + "@dataclass\nclass Node:\n    next: Node | None\n"),
    "'Node' is unbound",
  )
  assert_eq(verdict("type A = list[A]\n"), "type alias 'A' is cyclic")
  assert_eq(verdict("type A = B\ntype B = A\n"), "type alias 'B' is cyclic")
}
