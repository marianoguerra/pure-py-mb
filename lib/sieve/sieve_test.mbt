///|
/// One small source per message the sieve can produce, checked against the
/// message and the exit code the reference prints for it.
///
/// The messages are `syntax.py`'s, verbatim: the conformance suite compares
/// them as the `.error.expected` of its `parser` buckets, so a
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
    ("x = y = 1\n", "1: multiple assignment targets not allowed in PurePy"),
    (
      "f(**d)\n", "1: dictionary unpacking in argument list not allowed in PurePy",
    ),
    (
      "def f() -> None:\n    type X = int\n", "1: type statement outside the module top level not allowed in PurePy",
    ),
    (
      "def f[T, T](x: T) -> T:\n    return x\n", "1: duplicate type parameter T not allowed in PurePy",
    ),
    (
      "def f[T: int](x: T) -> T:\n    return x\n", "1: bound on type parameter T not allowed in PurePy",
    ),
    (
      "def f[T: (int, str)](x: T) -> T:\n    return x\n", "1: constraints on type parameter T not allowed in PurePy",
    ),
    (
      "def f[**P](x: int) -> int:\n    return x\n", "1: ParamSpec type parameter **P not allowed in PurePy",
    ),
    (
      "def f[*Ts](x: int) -> int:\n    return x\n", "1: TypeVarTuple type parameter *Ts not allowed in PurePy",
    ),
    (
      "@dataclass\n@dataclass\nclass C:\n    pass\n", "1: multiple class decorators not allowed in PurePy",
    ),
    ("a[0] = 1\n", "1: item assignment not allowed in PurePy"),
    ("a.b = 1\n", "1: attribute assignment not allowed in PurePy"),
    (
      "def f(x):\n    return 1\n", "1: unannotated parameter not allowed in PurePy",
    ),
    (
      "def f(x: int):\n    return 1\n", "1: unannotated return type not allowed in PurePy",
    ),
    (
      "def f(x: 1) -> int:\n    return 1\n", "1: annotation that is not a type expression not allowed in PurePy",
    ),
    (
      "def f() -> list[int, int]:\n    return 1\n", "1: annotation that is not a type expression not allowed in PurePy",
    ),
    ("x += 1\n", "1: augmented assignment (+=, etc.) not allowed in PurePy"),
    (
      "a.b: int = 1\n", "1: assignment target other than a simple name not allowed in PurePy",
    ),
    (
      "x: dict[int, int] = {}\n", "1: annotation that is not a type expression not allowed in PurePy",
    ),
    ("x = {**a}\n", "1: dictionary unpacking not allowed in PurePy"),
    (
      "import a\nx = 1\nimport b\n", "1: import after another statement not allowed in PurePy",
    ),
    (
      "def f() -> None:\n    import a\n", "1: import outside the module top level not allowed in PurePy",
    ),
    (
      "match v:\n    case 1 + 2j:\n        pass\n", "1: complex and bytes literal patterns not allowed in PurePy",
    ),
    ("del x\n", "1: del not allowed in PurePy"),
    ("for x in y:\n    pass\n", "1: for loops not allowed in PurePy"),
    ("while x:\n    pass\n", "1: while loops not allowed in PurePy"),
    ("with a:\n    pass\n", "1: with statements not allowed in PurePy"),
    ("async def f():\n    pass\n", "1: async not allowed in PurePy"),
    (
      "def f() -> None:\n    async for x in y:\n        pass\n", "1: async not allowed in PurePy",
    ),
    (
      "def f() -> None:\n    async with a:\n        pass\n", "1: async not allowed in PurePy",
    ),
    ("raise ValueError\n", "1: raise not allowed in PurePy"),
    (
      "try:\n    pass\nexcept:\n    pass\n", "1: try/except not allowed in PurePy",
    ),
    ("def f() -> None:\n    global x\n", "1: global not allowed in PurePy"),
    ("def f() -> None:\n    nonlocal x\n", "1: nonlocal not allowed in PurePy"),
    (
      "def f() -> None:\n    class C:\n        pass\n", "1: class definition outside the module top level not allowed in PurePy",
    ),
    ("def f() -> None:\n    break\n", "1: break not allowed in PurePy"),
    ("def f() -> None:\n    continue\n", "1: continue not allowed in PurePy"),
    (
      "try:\n    pass\nexcept* ValueError:\n    pass\n", "1: try/except not allowed in PurePy",
    ),
    ("class C:\n    pass\n", "1: undecorated class not allowed in PurePy"),
    (
      "@other\nclass C:\n    pass\n", "1: class decorator other than @dataclass not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C(A, B):\n    pass\n", "1: multiple inheritance not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C(f()):\n    pass\n", "1: base class other than a name, optionally applied to type arguments not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C(metaclass=type):\n    pass\n", "1: class keyword arguments not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C:\n    def m():\n        pass\n", "1: dataclass member other than a field declaration not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C:\n    a.b: Any\n", "1: field target other than a simple name not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C:\n    x: Any = 1\n", "1: field default values not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C:\n    x: 1\n", "1: annotation that is not a type expression not allowed in PurePy",
    ),
    (
      "match v:\n    case {1: a}:\n        pass\n", "1: dictionary pattern key other than a string literal not allowed in PurePy",
    ),
    ("x = b\"b\"\n", "1: bytes literal not allowed in PurePy"),
    ("x = 1j\n", "1: complex literal not allowed in PurePy"),
    ("x = ...\n", "1: ellipsis literal not allowed in PurePy"),
    ("x = a & b\n", "1: binary operator '&' not allowed in PurePy"),
    ("x = a ^ b\n", "1: binary operator '^' not allowed in PurePy"),
    ("x = a << b\n", "1: binary operator '<<' not allowed in PurePy"),
    ("x = a >> b\n", "1: binary operator '>>' not allowed in PurePy"),
    ("x = a @ b\n", "1: binary operator '@' not allowed in PurePy"),
    ("x = ~a\n", "1: unary operator '~' not allowed in PurePy"),
    ("x = (i for i in y)\n", "1: generator expressions not allowed in PurePy"),
    ("x = [(y := 1)]\n", "1: walrus operator (:=) not allowed in PurePy"),
    ("x = [*y]\n", "1: starred expressions not allowed in PurePy"),
    ("def f() -> None:\n    yield 1\n", "1: yield not allowed in PurePy"),
    ("def f() -> None:\n    yield from y\n", "1: yield not allowed in PurePy"),
    (
      "x = [i async for i in y]\n", "1: async comprehensions not allowed in PurePy",
    ),
    (
      "def f(*, x):\n    pass\n", "1: keyword-only arguments not allowed in PurePy",
    ),
    (
      "def f(x, /):\n    pass\n", "1: positional-only arguments not allowed in PurePy",
    ),
  ]
  for c in cases {
    assert_eq(verdict(c.0), c.1, msg=c.0)
  }
}

///|
test "forms that are planned and not yet supported" {
  let cases = [
    ("x, y = 1, 2\n", "1: unpacking assignment not allowed in PurePy"),
    ("@deco\ndef f():\n    pass\n", "1: decorators not allowed in PurePy"),
    (
      "import a, b\n", "1: multi-target import (import a, b) not allowed in PurePy",
    ),
    ("import a as b\n", "1: import-as not allowed in PurePy"),
    ("from . import a\n", "1: relative imports not allowed in PurePy"),
    ("from .m import a\n", "1: relative imports not allowed in PurePy"),
    ("from m import *\n", "1: from M import * not allowed in PurePy"),
    ("from m import a as b\n", "1: from-import-as not allowed in PurePy"),
    (
      "match v:\n    case a if a:\n        pass\n", "1: case guards not allowed in PurePy",
    ),
    (
      "@dataclass\nclass C(Enum):\n    pass\n", "1: enum classes not allowed in PurePy",
    ),
    (
      "match v:\n    case a.b:\n        pass\n", "1: attribute value patterns not allowed in PurePy",
    ),
    (
      "match v:\n    case [*rest]:\n        pass\n", "1: star patterns not allowed in PurePy",
    ),
    (
      "match v:\n    case {**rest}:\n        pass\n", "1: rest capture in dictionary patterns not allowed in PurePy",
    ),
    (
      "match v:\n    case 1 | 2:\n        pass\n", "1: or-patterns not allowed in PurePy",
    ),
    ("x = a and b and c\n", "1: chained boolean operator not allowed in PurePy"),
    ("x = a < b < c\n", "1: chained comparison not allowed in PurePy"),
    ("x = a is b\n", "1: identity operator (is/is not) not allowed in PurePy"),
    (
      "x = a is not b\n", "1: identity operator (is/is not) not allowed in PurePy",
    ),
    ("x = {1, 2}\n", "1: set literals not allowed in PurePy"),
    ("x = {i for i in y}\n", "1: set comprehensions not allowed in PurePy"),
    ("x = a[1:2]\n", "1: slicing not allowed in PurePy"),
    ("x = f\"{y}\"\n", "1: f-strings not allowed in PurePy"),
    (
      "x = [a for a, b in y]\n", "1: unpacking in comprehensions not allowed in PurePy",
    ),
    ("def f(*args):\n    pass\n", "1: *args not allowed in PurePy"),
    ("def f(**kw):\n    pass\n", "1: **kwargs not allowed in PurePy"),
    ("def f(x=1):\n    pass\n", "1: default arguments not allowed in PurePy"),
    ("f = lambda x=1: x\n", "1: default arguments not allowed in PurePy"),
    ("x = f\"{a}\"\n", "1: f-strings not allowed in PurePy"),
    ("x = f\"plain\"\n", "1: f-strings not allowed in PurePy"),
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
    "x = (1, 2)\n", "x = {\"a\": 1}\n", "type X = int\n", "type P[T] = tuple[T, T]\n",
    "def f[T](x: T) -> T:\n    return x\n", "@dataclass\nclass B[T](A[T]):\n    x: T\n",
    "x = Box[int](1)\n", "@dataclass\nclass C(m.A):\n    pass\n", "x = a.b\n", "x = a[0]\n",
    "x = [i for i in y if i]\n", "x = {k: v for k in y}\n", "def f(a: int, b: str) -> int:\n    return a\n",
    "x: int = 1\n", "x: list[int | str] = []\n", "x: Callable[[int], dict[str, int]] = f\n",
    "x: Literal[-1] = -1\n", "x: tuple[int, str] | None = None\n", "if a:\n    x = 1\nelse:\n    x = 2\n",
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

// ---------------------------------------------------------------------------
// Profiles

///|
/// `verdict`, under a profile the caller opted in to.
fn verdict_under(source : String, profile : @profile.Profile) -> String {
  let m = try @parser.parse_string(source) catch {
    @err.PurePyError(d) => return "syntax: " + d.message()
    e => return "syntax: \{e}"
  } noraise {
    m => m
  }
  match @sieve.result(m, profile~) {
    None => "ok"
    Some(d) => "\{d.exit_code()}: \{d.message()}"
  }
}

///|
/// The pair that is the whole claim: refused under `core` with the message the
/// reference prints, accepted under the profile that opens the gate.
///
/// The `core` half is the one that matters. `test/golden/` and the conformance
/// ratchet say the same thing over 392 files, but they say it about the
/// default argument; this says it about `@profile.core` written out, which is
/// what the default is.
test "chained boolean operators are gated, not removed" {
  let cases = [
    "a = b and c and d\n", "a = b or c or d\n", "a = b and c and d and e\n",
  ]
  for source in cases {
    assert_eq(
      verdict(source),
      "1: chained boolean operator not allowed in PurePy",
    )
    assert_eq(verdict_under(source, @profile.core), verdict(source))
    assert_eq(verdict_under(source, @profile.pending()), "ok")
  }
}

///|
/// Two operands is PurePy, under every profile.
test "an unchained boolean operator is untouched" {
  assert_eq(verdict("a = b and c\n"), "ok")
  assert_eq(verdict_under("a = b and c\n", @profile.pending()), "ok")
}

///|
/// Opening a gate must not make the walk skip what is past it.
///
/// The sieve raises on the FIRST violation it reaches and the conformance
/// suite has files that depend on which -- so a profile that forgives the
/// first must go on to find the second, and must not have been implemented by
/// forgiving the raise after the fact.
test "a profile keeps walking past the gate it opened" {
  // The second violation has to be one `pending` does NOT open, or the test
  // stops asking anything. `*args` is the durable choice now that f-strings
  // have landed: it needs an arity model this evaluator does not have.
  let source = "a = b and c and d\ndef f(*g):\n    return 1\n"
  assert_eq(
    verdict(source),
    "1: chained boolean operator not allowed in PurePy",
  )
  assert_eq(
    verdict_under(source, @profile.pending()),
    "1: *args not allowed in PurePy",
  )
}

///|
/// Every feature `pending` holds, as the pair: refused under `core` with the
/// message and issue number the reference prints, accepted under the profile.
///
/// A row here is the sieve half of a feature. The other two halves -- the
/// checker having a case for the node, and the run agreeing with CPython --
/// are `test/profile/`, driven by `tools/profile-conform.py`.
test "every pending feature is gated, not removed" {
  let cases = [
    ("a = b and c and d\n", "1: chained boolean operator not allowed in PurePy"),
    ("a = 1 < b < 3\n", "1: chained comparison not allowed in PurePy"),
    (
      "a = b is None\n", "1: identity operator (is/is not) not allowed in PurePy",
    ),
    (
      "a = b is not None\n", "1: identity operator (is/is not) not allowed in PurePy",
    ),
    ("a = xs[1:2]\n", "1: slicing not allowed in PurePy"),
    ("a = xs[::-1]\n", "1: slicing not allowed in PurePy"),
    ("a, b = (1, 2)\n", "1: unpacking assignment not allowed in PurePy"),
    (
      "a, (b, c) = (1, (2, 3))\n", "1: unpacking assignment not allowed in PurePy",
    ),
    (
      "def f(x: int = 1) -> int:\n    return x\n", "1: default arguments not allowed in PurePy",
    ),
    ("f = lambda x=1: x\n", "1: default arguments not allowed in PurePy"),
  ]
  for c in cases {
    assert_eq(verdict(c.0), c.1, msg=c.0)
    assert_eq(verdict_under(c.0, @profile.core), c.1, msg=c.0)
    assert_eq(verdict_under(c.0, @profile.pending()), "ok", msg=c.0)
  }
}

///|
/// A destructuring target is a nest of NAMES. The messages inside one are the
/// ones a bare target gets, because the rule is the same rule: `a.b, c = ...`
/// is attribute assignment however it is spelled.
test "a destructuring target may not assign an item or an attribute" {
  let p = @profile.pending()
  assert_eq(
    verdict_under("a.b, c = 1, 2\n", p),
    "1: attribute assignment not allowed in PurePy",
  )
  assert_eq(
    verdict_under("xs[0], c = 1, 2\n", p),
    "1: item assignment not allowed in PurePy",
  )
  // A starred target never reaches the shape test: it is prohibited outright,
  // which is what keeps a destructuring target exact in its arity.
  assert_eq(
    verdict_under("a, *rest = [1, 2, 3]\n", p),
    "1: starred expressions not allowed in PurePy",
  )
}

///|
/// The features `pending` does NOT hold yet, each still refused under it with
/// the message it has under `core`.
///
/// This is the list that shrinks as the profile grows, and it is worth
/// asserting rather than describing: a feature that quietly half-landed would
/// show up here as a changed message rather than as a silence.
test "the rest of the pending table is still closed" {
  let cases = [
    ("def f(*a):\n    return 1\n", "1: *args not allowed in PurePy"),
    ("def f(**a):\n    return 1\n", "1: **kwargs not allowed in PurePy"),
    ("@deco\ndef f():\n    pass\n", "1: decorators not allowed in PurePy"),
    ("s = {1, 2}\n", "1: set literals not allowed in PurePy"),
    ("s = {x for x in y}\n", "1: set comprehensions not allowed in PurePy"),
    ("import a as b\n", "1: import-as not allowed in PurePy"),
    (
      "xs = [a for a, b in items]\n", "1: unpacking in comprehensions not allowed in PurePy",
    ),
  ]
  for c in cases {
    assert_eq(verdict_under(c.0, @profile.pending()), c.1, msg=c.0)
  }
}

///|
/// What an f-string takes, and the three shapes of it that are still #55.
///
/// The holes are walked like any other expression, so a form the sieve refuses
/// inside one is refused with its own message rather than with the f-string's.
test "an f-string takes expressions and not a format language" {
  let p = @profile.pending()
  for
    source in [
      "x = f\"plain\"\n", "x = f\"{a}\"\n", "x = f\"{a} and {b}\"\n", "x = f\"{{braces}} {a}\"\n",
      "x = f\"{a!r} {a!s}\"\n", "x = f\"{a[0]}\"\n", "x = f\"{f'{a}'}\"\n", "x = f\"\"\n",
      "x = f\"a\" \"b\" f\"{c}\"\n",
    ] {
    assert_eq(verdict_under(source, p), "ok", msg=source)
  }
  // A format spec is a language of its own; the debug form keeps the source
  // of the expression; `!a` is `ascii()`, which PurePy does not have. Each is
  // named rather than lumped in with "f-strings", so the message says which
  // half was missing.
  assert_eq(
    verdict_under("x = f\"{a:>10}\"\n", p),
    "1: an f-string format spec not allowed in PurePy",
  )
  assert_eq(
    verdict_under("x = f\"{a=}\"\n", p),
    "1: the f-string debug form (f\"{x=}\") not allowed in PurePy",
  )
  assert_eq(
    verdict_under("x = f\"{a!a}\"\n", p),
    "1: an f-string conversion not allowed in PurePy",
  )
  // A hole is walked, so what is prohibited in an expression is prohibited in
  // one -- with the message it has anywhere else.
  assert_eq(
    verdict_under("x = f\"{a & b}\"\n", p),
    "1: binary operator '&' not allowed in PurePy",
  )
  assert_eq(
    verdict_under("x = f\"{1 is 1}\"\n", p),
    "1: identity against a literal: PurePy values have no identity apart from None",
  )
}

///|
/// A default argument must be a LITERAL, and anything else is still #56.
///
/// The restriction is the feature. Python evaluates a default once, when the
/// `def` runs, and that is observable for anything with an effect or a free
/// name; this evaluator has nowhere to put a once, because calling one member
/// of a mutual region rebuilds the whole region. A literal has neither, so
/// when it is evaluated cannot be seen -- and the feature is drawn exactly
/// where the difference disappears, rather than answered wrongly outside it.
test "a default argument must be a literal" {
  let p = @profile.pending()
  for
    source in [
      "def f(x: int = 1) -> int:\n    return x\n", "def f(x: float = 1.5) -> float:\n    return x\n",
      "def f(x: str = 'a') -> str:\n    return x\n", "def f(x: bool = True) -> bool:\n    return x\n",
      "def f(x: None = None) -> None:\n    return x\n", "def f(a: int, b: int = 1, c: str = 'x') -> int:\n    return a\n",
      "f = lambda x=None: x\n",
    ] {
    assert_eq(verdict_under(source, p), "ok", msg=source)
  }
  for
    source in [
      // A name: which one, and when, is the question this avoids.
      "y = 1\ndef f(x=y):\n    return x\n",
      // An effect: Python prints once, at the `def`.
       "def f(x=print(1)):\n    return x\n",
      // A container is harmless here, since nothing is mutable -- but the
      // line is drawn at literals, not at safety, so that it is one line.
       "def f(x=[]):\n    return x\n", "def f(x=(1, 2)):\n    return x\n",
      // `-1` is a unary minus applied to a literal, not a literal.
       "def f(x=-1):\n    return x\n",
    ] {
    assert_eq(
      verdict_under(source, p),
      "1: a default argument that is not a literal not allowed in PurePy",
      msg=source,
    )
  }
}

///|
/// `is` against a literal that is not `None` is refused outright, under every
/// profile -- including the one that opens `is` in the first place.
///
/// `prohibited` and not `not_yet`, because nothing is pending: a PurePy value
/// has no identity and `None` is the whole of the exception, so there is no
/// version of `1 is 1` that gets an answer later. It is worth catching here
/// rather than at run time for the reason PurePy catches anything here --
/// stopping before the program starts beats stopping in the middle of it --
/// and it costs no types, only a look at the token.
test "identity against a literal is refused, not deferred" {
  // Under `core` the operator itself is refused first, and that message is
  // the reference's, unchanged.
  assert_eq(
    verdict("x = 1 is 1\n"),
    "1: identity operator (is/is not) not allowed in PurePy",
  )
  for name in @profile.names {
    let p = @profile.by_name(name).unwrap()
    if !p.has(Identity) {
      continue
    }
    for source in ["x = 1 is 1\n", "x = y is 'a'\n", "x = 2.0 is not y\n"] {
      assert_eq(
        verdict_under(source, p),
        "1: identity against a literal: PurePy values have no identity apart from None",
        msg=source,
      )
    }
    // `None` on either side is the case the operator exists for.
    for
      source in [
        "x = y is None\n", "x = None is y\n", "x = None is None\n", "x = y is not None\n",
      ] {
      assert_eq(verdict_under(source, p), "ok", msg=source)
    }
  }
}

///|
/// A gate is not a licence: `for` is prohibited under every profile there is.
test "no profile lifts a prohibition" {
  for name in @profile.names {
    let p = @profile.by_name(name).unwrap()
    assert_eq(
      verdict_under("for x in y:\n    pass\n", p),
      "1: for loops not allowed in PurePy",
    )
    assert_eq(
      verdict_under("xs[0] = 1\n", p),
      "1: item assignment not allowed in PurePy",
    )
    assert_eq(verdict_under("del x\n", p), "1: del not allowed in PurePy")
  }
}

///|
/// What the checker once refused and the parser refuses since v0.23: a name
/// or key twice where Python's compiler would refuse it, and a return outside
/// a function.
test "duplicates and a return outside a function" {
  let cases = [
    (
      "match v:\n    case [x, x]:\n        pass\n", "1: duplicate variable x in pattern not allowed in PurePy",
    ),
    (
      "match v:\n    case P(a=x, a=y):\n        pass\n", "1: duplicate keyword a in constructor pattern not allowed in PurePy",
    ),
    (
      "match v:\n    case {\"k\": x, \"k\": y}:\n        pass\n", "1: duplicate key 'k' in dictionary pattern not allowed in PurePy",
    ),
    (
      "def f(x: int, x: int) -> int:\n    return x\n", "1: duplicate parameter x not allowed in PurePy",
    ),
    ("return 1\n", "1: return outside a function not allowed in PurePy"),
    (
      "if True:\n    return 1\n", "1: return outside a function not allowed in PurePy",
    ),
  ]
  for c in cases {
    assert_eq(verdict(c.0), c.1, msg=c.0)
  }
}
