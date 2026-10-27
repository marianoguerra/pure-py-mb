///|
/// The static semantics a profile adds, on sources. What a profile ACCEPTS
/// is `test/profile/`, run against CPython; what it still refuses is here.
fn verdict_under(source : String, profile : @profile.Profile) -> String {
  let m = @parser.parse_string(source) catch { e => return "syntax: \{e}" }
  match @check.check_single(m, profile~) {
    None => "ok"
    Some(d) => d.message()
  }
}

///|
fn pending_verdict(source : String) -> String {
  verdict_under(source, @profile.pending())
}

// ---------------------------------------------------------------------------
// Slicing a tuple

///|
/// A tuple's slice is the tuple of the components it takes, as mypy types it.
test "a tuple's slice is a tuple of the components it takes" {
  let t = "t: tuple[int, str, bool] = (1, \"a\", True)\n"
  let cases = [
    ("a: tuple[str, bool] = t[1:]\n", "ok"),
    ("a: tuple[bool, str, int] = t[::-1]\n", "ok"),
    ("a: tuple[int, str] = t[-10:2]\n", "ok"),
    ("a: tuple[bool, str] = t[2:0:-1]\n", "ok"),
    ("a: tuple[int, bool] = t[::2]\n", "ok"),
    // Not a list, which is what Python does not make it.
    (
      "a: list[int | str | bool] = t[1:]\n", "expected type list[int | str | bool], given tuple[str, bool]",
    ),
    // A bound mypy cannot read gives `tuple[T, ...]`, which PurePy has no
    // annotation for.
    (
      "n: int = 1\na: object = t[n:]\n", "a slice of a value of type tuple[int, str, bool] needs integer literal bounds",
    ),
    ("a: object = t[::0]\n", "slice step cannot be zero"),
  ]
  for c in cases {
    assert_eq(pending_verdict(t + c.0), c.1, msg=c.0)
  }
}

// ---------------------------------------------------------------------------
// Narrowing by `is None`

///|
/// `x is None` narrows where it decides, as mypy's does.
test "is None narrows the variable it tests" {
  let cases = [
    "def f(x: int | None) -> int:\n    if x is None:\n        return 0\n    return x + 1\n",
    "def f(x: int | None) -> int:\n    if x is not None:\n        return x\n    return 0\n",
    "def f(x: int | None) -> bool:\n    return x is not None and x > 1\n", "def f(x: int | None) -> bool:\n    return x is None or x > 1\n",
    "def f(x: int | None) -> int:\n    return 0 if x is None else x\n", "def f(x: int | None) -> int:\n    assert x is not None\n    return x\n",
    "def f(x: int | None) -> int:\n    if not (x is None):\n        return x\n    return 0\n",
    "def f(x: int | None) -> int:\n    if None is x:\n        return 0\n    return x\n",
    "def f(x: int | None, y: int | None) -> int:\n    if x is None or y is None:\n        return 0\n    return x + y\n",
    "def f(x: int | None, y: int | None) -> int:\n    if x is None:\n        return 0\n    elif y is None:\n        return 1\n    return x + y\n",
    "def f(ys: list[int | None]) -> list[int]:\n    return [y for y in ys if y is not None]\n",
  ]
  for c in cases {
    assert_eq(pending_verdict(c), "ok", msg=c)
  }
}

///|
/// And nowhere else: each of these is refused by mypy too.
test "is None narrows nothing it does not decide" {
  let cases = [
    // Both branches fall through, so neither narrowing survives the `if`.
    (
      "def f(x: int | None) -> int:\n    y: int\n    if x is None:\n        y = 1\n    else:\n        y = 2\n    return x + y\n",
      "no overload of '+' at operand types int | None and int",
    ),
    (
      "def f(x: int | None) -> int:\n    if x is not None:\n        return x\n    else:\n        return x + 1\n",
      "no overload of '+' at operand types None and Literal[1]",
    ),
    (
      "def f(x: int | None) -> bool:\n    return x is None and x > 1\n", "no overload of '>' at operand types None and Literal[1]",
    ),
    (
      "def f(ys: list[int | None]) -> list[int]:\n    return [y for y in ys if y is None]\n",
      "expected type int, given None",
    ),
    // `==` is PurePy's, and a profile does not change what it decides.
    (
      "def f(x: int | None) -> int:\n    if x == None:\n        return 0\n    return x + 1\n",
      "no overload of '+' at operand types int | None and Literal[1]",
    ),
    // A module body does not carry a narrowing forward, so none reaches the
    // module's members.
    (
      "x: int | None = 3\nassert x is not None\nprint(x + 1)\n", "no overload of '+' at operand types int | None and Literal[1]",
    ),
  ]
  for c in cases {
    assert_eq(pending_verdict(c.0), c.1, msg=c.0)
  }
}

///|
/// A narrowing inside one branch of an enclosing `if` is not an assignment,
/// so the merge does not make the variable possibly unassigned.
test "a narrowing in one branch leaves the variable assigned" {
  let src =
    #|def f(c: bool, x: int | None) -> int:
    #|    y: int
    #|    if c:
    #|        if x is None:
    #|            return 0
    #|        y = x
    #|    else:
    #|        y = 5
    #|    return y + x if x is not None else y
  assert_eq(pending_verdict(src), "ok")
}
