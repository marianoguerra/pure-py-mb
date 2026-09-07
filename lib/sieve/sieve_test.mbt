///|
/// One small source per message the sieve can produce, checked against the
/// message and the exit code the reference prints for it.
///
/// The messages are `syntax.py`'s, verbatim: the conformance suite compares
/// them as the `.error.expected` of its `excluded/syntactic` bucket, so a
/// change of wording here is a conformance failure and not a matter of taste.
fn verdict(source : String) -> String {
  let m = try @parser.parse_string(source) catch {
    @err.PurePyError(d) => return "syntax: " + d.message()
    e => return "syntax: \{e}"
  } noraise {
    m => m
  }
  match @sieve.result(m) {
    None => "ok"
    Some(d) => "\{d.exit_code()}: \{d.message()}"
  }
}

///|
test "prohibited forms" {
  let cases = [
    ("x = y = 1\n", "1: multiple assignment targets"),
    ("a[0] = 1\n", "1: item assignment prohibited"),
    ("a.b = 1\n", "1: attribute assignment prohibited"),
    ("def f() -> int:\n    return 1\n", "1: return type annotations prohibited"),
    ("x += 1\n", "1: augmented assignment (+=, etc.) prohibited"),
    ("x: int = 1\n", "1: annotated assignment prohibited"),
    ("del x\n", "1: del prohibited"),
    ("for x in y:\n    pass\n", "1: for loops prohibited"),
    ("while x:\n    pass\n", "1: while loops prohibited"),
    ("with a:\n    pass\n", "1: with statements prohibited"),
    ("async def f():\n    pass\n", "1: async prohibited"),
    ("def f():\n    async for x in y:\n        pass\n", "1: async prohibited"),
    ("def f():\n    async with a:\n        pass\n", "1: async prohibited"),
    ("raise ValueError\n", "1: raise prohibited"),
    ("try:\n    pass\nexcept:\n    pass\n", "1: try/except prohibited"),
    ("def f():\n    global x\n", "1: global prohibited"),
    ("def f():\n    nonlocal x\n", "1: nonlocal prohibited"),
    (
      "def f():\n    class C:\n        pass\n", "1: class declaration only at module top level",
    ),
    ("def f():\n    break\n", "1: break prohibited"),
    ("def f():\n    continue\n", "1: continue prohibited"),
    (
      "try:\n    pass\nexcept* ValueError:\n    pass\n", "1: unknown statement type: TryStar",
    ),
    (
      "class C:\n    pass\n", "1: class must have exactly the @dataclass decorator",
    ),
    (
      "@other\nclass C:\n    pass\n", "1: only the @dataclass decorator is supported on classes",
    ),
    (
      "@dataclass\nclass C(A, B):\n    pass\n", "1: multiple inheritance prohibited",
    ),
    (
      "@dataclass\nclass C(a.b):\n    pass\n", "1: base class must be a simple name",
    ),
    (
      "@dataclass\nclass C(metaclass=type):\n    pass\n", "1: class keyword arguments prohibited",
    ),
    (
      "@dataclass\nclass C:\n    def m():\n        pass\n", "1: dataclass body may contain only field declarations",
    ),
    (
      "@dataclass\nclass C:\n    a.b: Any\n", "1: field target must be a simple name",
    ),
    (
      "@dataclass\nclass C:\n    x: Any = 1\n", "1: field default values prohibited",
    ),
    (
      "@dataclass\nclass C:\n    x: int\n", "1: field type annotation must be Any",
    ),
    (
      "match v:\n    case {1: a}:\n        pass\n", "1: dict pattern keys must be string literals",
    ),
    ("x = b\"b\"\n", "1: bytes literals prohibited"),
    ("x = 1j\n", "1: complex literals prohibited"),
    ("x = ...\n", "1: prohibited literal type: ellipsis"),
    ("x = a | b\n", "1: binary operator '|' prohibited"),
    ("x = a & b\n", "1: binary operator '&' prohibited"),
    ("x = a ^ b\n", "1: binary operator '^' prohibited"),
    ("x = a << b\n", "1: binary operator '<<' prohibited"),
    ("x = a >> b\n", "1: binary operator '>>' prohibited"),
    ("x = a @ b\n", "1: binary operator '@' prohibited"),
    ("x = ~a\n", "1: unary operator '~' prohibited"),
    ("x = (i for i in y)\n", "1: generator expressions prohibited"),
    ("x = [(y := 1)]\n", "1: walrus operator (:=) prohibited"),
    ("x = [*y]\n", "1: starred expressions prohibited"),
    ("def f():\n    yield 1\n", "1: yield prohibited"),
    ("def f():\n    yield from y\n", "1: yield prohibited"),
    ("x = [i async for i in y]\n", "1: async comprehensions prohibited"),
    ("def f(*, x):\n    pass\n", "1: keyword-only arguments prohibited"),
    ("def f(x, /):\n    pass\n", "1: positional-only arguments prohibited"),
  ]
  for c in cases {
    assert_eq(verdict(c.0), c.1, msg=c.0)
  }
}

///|
/// One message of `syntax.py` has no source that reaches it: "class pattern
/// head must be a qualified name". Python's own grammar is
/// `class_pattern: name_or_attr '(' ...`, so a head that is not a name or a
/// dotted name is a syntax error before the sieve sees anything. The check is
/// kept because the reference keeps it, and it is recorded here as unreachable
/// rather than left looking untested.
test "forms that are planned and not yet supported" {
  let cases = [
    ("x, y = 1, 2\n", "2: destructuring assignment not yet supported (#54)"),
    ("@deco\ndef f():\n    pass\n", "2: decorators not yet supported (#58)"),
    (
      "import a, b\n", "2: multi-target import (import a, b) not yet supported (#53)",
    ),
    ("import a as b\n", "2: import-as not yet supported (#53)"),
    ("from . import a\n", "2: relative imports not yet supported (#53)"),
    ("from . import a\n", "2: relative imports not yet supported (#53)"),
    ("from m import *\n", "2: from M import * not yet supported (#53)"),
    ("from m import a as b\n", "2: from-import-as not yet supported (#53)"),
    (
      "match v:\n    case a if a:\n        pass\n", "2: case guards not yet supported (#83)",
    ),
    (
      "@dataclass\nclass C(Enum):\n    pass\n", "2: enum classes not yet supported (#86)",
    ),
    (
      "match v:\n    case a.b:\n        pass\n", "2: attribute value patterns not yet supported (#86)",
    ),
    (
      "match v:\n    case 1 + 2j:\n        pass\n", "2: complex value patterns not yet supported (#83)",
    ),
    (
      "match v:\n    case [*rest]:\n        pass\n", "2: star patterns not yet supported (#84)",
    ),
    (
      "match v:\n    case {**rest}:\n        pass\n", "2: rest capture in dict patterns not yet supported (#84)",
    ),
    (
      "match v:\n    case 1 | 2:\n        pass\n", "2: or-patterns not yet supported (#85)",
    ),
    (
      "x = a and b and c\n", "2: chained boolean operator not yet supported (#82)",
    ),
    ("x = a < b < c\n", "2: chained comparison not yet supported (#82)"),
    ("x = a is b\n", "2: identity operator (is/is not) not yet supported (#81)"),
    (
      "x = a is not b\n", "2: identity operator (is/is not) not yet supported (#81)",
    ),
    ("x = {1, 2}\n", "2: set literals not yet supported (#147)"),
    ("x = {i for i in y}\n", "2: set comprehensions not yet supported (#147)"),
    ("x = a[1:2]\n", "2: slicing not yet supported (#59)"),
    ("x = f\"{y}\"\n", "2: f-strings not yet supported (#55)"),
    (
      "x = [a for a, b in y]\n", "2: destructuring in comprehensions not yet supported (#54)",
    ),
    ("def f(*args):\n    pass\n", "2: *args not yet supported (#57)"),
    ("def f(**kw):\n    pass\n", "2: **kwargs not yet supported (#57)"),
    ("def f(x=1):\n    pass\n", "2: default arguments not yet supported (#56)"),
    ("f = lambda x=1: x\n", "2: default arguments not yet supported (#56)"),
  ]
  for c in cases {
    assert_eq(verdict(c.0), c.1, msg=c.0)
  }
}

///|
test "what PurePy accepts" {
  let cases = [
    "pass\n", "x = 1\n", "x = a + b * c\n", "x = not a\n", "x = -a\n", "x = a < b\n",
    "x = f(1, k=2)\n", "x = a if b else c\n", "x = lambda p: p\n", "x = [1, 2]\n",
    "x = (1, 2)\n", "x = {\"a\": 1}\n", "x = a.b\n", "x = a[0]\n", "x = [i for i in y if i]\n",
    "x = {k: v for k in y}\n", "def f(a, b):\n    return a\n", "if a:\n    x = 1\nelse:\n    x = 2\n",
    "assert a, \"m\"\n", "import sys\n", "from math import pi\n", "@dataclass\nclass C:\n    x: Any\n",
    "@dataclass\nclass C:\n    pass\n", "@dataclass\nclass D(C):\n    y: Any\n",
    "match v:\n    case 1:\n        pass\n    case _:\n        pass\n", "match v:\n    case [a]:\n        pass\n",
    "match v:\n    case (a, b):\n        pass\n", "match v:\n    case {\"k\": a}:\n        pass\n",
    "match v:\n    case C(a, y=b):\n        pass\n", "match v:\n    case -1:\n        pass\n",
    "match v:\n    case None:\n        pass\n", "match v:\n    case a as b:\n        pass\n",
  ]
  for c in cases {
    assert_eq(verdict(c), "ok", msg=c)
  }
}
