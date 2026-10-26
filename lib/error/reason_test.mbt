///|
/// Every reason's message, against the text `reasons.py` produces.
///
/// These strings are the `.error.expected` files of the conformance suite, so
/// this test is where a wording change is caught before the suite catches it.
test "the reason catalogue" {
  let cases : Array[(@err.Reason, String)] = [
    (DuplicateField(x="x", c="P"), "duplicate field 'x' in class 'P'"),
    (
      ClassRebound(c="P"),
      "'P' is bound to a class and cannot be rebound at top level",
    ),
    (UndefinedVariable(x="x"), "'x' is not defined"),
    (UnassignedVariable(x="x"), "'x' is not definitely assigned"),
    (
      CapturedReassignment(x="x"),
      "'x' captured by previous statement, reassigned here",
    ),
    (SelfCaptureAssignment(x="f"), "'f' captured by right-hand side"),
    (
      CapturedGeneratorVariable(x="i"),
      "'i' bound by generator, captured by lambda",
    ),
    (UnreachableStatement, "unreachable statement"),
    (
      ConstructorArityMismatch(c="P", expected=2, got=3),
      "constructor for 'P' expects 2 arguments, got 3",
    ),
    (
      UnknownConstructorKeyword(c="P", xs=["x", "y"]),
      "constructor keywords for 'P' must be x, y",
    ),
    (
      PatternArityMismatch(c="P", expected=2, got=1),
      "pattern for 'P' expects 2 sub-patterns, got 1",
    ),
    (NotPredefinedName(x="int"), "'int' is not bound as a predefined name"),
    (NotClass(q="m.C"), "'m.C' is not a declared class"),
    (
      UnknownFieldInPattern(c="P", xs=["y"]),
      "pattern keywords for 'P' must be y",
    ),
    (DuplicatePatternKeyword(c="P"), "duplicate keyword in pattern for 'P'"),
    (DuplicateDictKey(w="k"), "duplicate key 'k' in dict pattern"),
    (NonlinearPattern(x="x"), "repeated variable 'x' in pattern"),
    (DuplicateMutualName(x="f"), "duplicate name 'f' in mutual region"),
    (
      DuplicateMember(x="sub", q="pkg"),
      "duplicate member of module 'pkg': it defines 'sub' and also has submodule 'pkg.sub'",
    ),
    (SubmoduleNotImported(q="a.b"), "submodule 'a.b' is not imported"),
    (
      UnassignedMember(x="x", q="m"),
      "member 'x' of module 'm' is not definitely assigned",
    ),
    (
      TopLevelReturn,
      "top-level return not allowed (module body must not return)",
    ),
    (UnknownModule(q="nope"), "unknown module 'nope'"),
    (UnknownMember(x="y", q="m"), "module 'm' has no member 'y'"),
    (
      ModuleAsValue(q="math"),
      "'math' refers to a module; modules are not first-class values",
    ),
    (
      ImportOfContainedModule(
        q="pkg.sub",
        q_="pkg",
        from_import="from pkg import sub",
      ),
      "'pkg.sub' is contained in importing module 'pkg'; plain import not allowed, write 'from pkg import sub'",
    ),
    (
      PredefinedNameAsValue(q="int"),
      "'int' is usable only in annotations or as a decorator",
    ),
    (
      ClassAsValue(q="Point"),
      "'Point' refers to a class; classes are not first-class values",
    ),
    (
      NoBinaryOverload(op="+", sigma="int", sigma_="str"),
      "no overload of '+' at operand types int and str",
    ),
    (
      NoUnaryOverload(op="-", sigma="str"),
      "no overload of '-' at operand type str",
    ),
    (NotCallable(tau="int"), "values of type int cannot be called"),
    (
      CallArityMismatch(expected=1, given=2),
      "call expects 1 arguments, given 2",
    ),
    (TypeMismatch(expected="int", actual="str"), "expected type int, given str"),
    (
      LambdaTypeMismatch(expected="int", arity=None),
      "expected type int, given a lambda",
    ),
    (
      LambdaTypeMismatch(expected="Callable[[], int]", arity=Some(1)),
      "expected type Callable[[], int], given a lambda of 1 parameter",
    ),
    (NotSubscriptable(tau="int"), "values of type int cannot be subscripted"),
    (
      TupleIndexOutOfRange(index=5N, length=2),
      "index 5 out of range for tuple of length 2",
    ),
    (UnreachableCase(index=2), "case 2 is unreachable"),
    (
      SequenceKindMismatch(kind="list", tau="tuple[int]"),
      "list pattern requires values of list type, not tuple[int]",
    ),
    (NotIterable(tau="int"), "values of type int cannot be iterated"),
    (UnknownField(c="P", x="z"), "class 'P' has no field 'z'"),
    (
      NotSynthesised,
      "cannot infer type of this expression; annotate the assignment",
    ),
    (NoAttributes(tau="int"), "values of type int have no attributes"),
    (
      MissingReturn(x="f", tau="int"),
      "'f' declares result type int but does not always return",
    ),
    (
      UnknownMethod(tau="list[int]", x="append"),
      "values of type list[int] have no method 'append'",
    ),
  ]
  assert_eq(cases.length(), 45)
  for c in cases {
    assert_eq(c.0.message(), c.1)
  }
}

///|
test "a rejection's exit code and short form" {
  let d = @err.Diagnostic::new(IllFormed(UnassignedVariable(x="x")), span={
    start: { line: 3, col: 4, offset: 20, },
    end: { line: 3, col: 5, offset: 21, },
  })
  assert_eq(d.exit_code(), 3)
  assert_eq(d.short("a.py"), "a.py:3:4: 'x' is not definitely assigned")
  // With no position the reference prints the path and the message only.
  let e = @err.Diagnostic::new(Prohibited(msg="del prohibited"))
  assert_eq(e.short("a.py"), "a.py: del prohibited")
  assert_eq(e.exit_code(), 1)
  assert_eq(
    @err.Reason::UnassignedVariable(x="x").code(),
    "purepy::unassigned-variable",
  )
}
