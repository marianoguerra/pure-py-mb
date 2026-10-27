///|
/// Every reason's message, against the text `reasons.py` produces.
///
/// These strings are the `.error.expected` files of the conformance suite, so
/// this test is where a wording change is caught before the suite catches it.
test "the reason catalogue" {
  let cases : Array[(@err.Reason, String)] = [
    (DuplicateField(x="x", c="P"), "duplicate field 'x' in class 'P'"),
    (
      InheritedField(x="x", c="Q", d="P"),
      "field 'x' of class 'Q' is also a field of base class 'P'",
    ),
    (UndefinedVariable(x="x"), "'x' is not defined"),
    (UnassignedVariable(x="x"), "'x' is declared but not yet assigned"),
    (
      PossiblyUnassigned(x="x", declared_in_branch=false),
      "'x' is not definitely assigned",
    ),
    (
      PossiblyUnassigned(x="x", declared_in_branch=true),
      "'x' is not definitely assigned: declared in a branch",
    ),
    (RangePattern, "'range' not permitted in a constructor pattern"),
    (CyclicTypeAlias(x="T"), "type alias 'T' is cyclic"),
    (
      ClassArityMismatch(q="Box", expected=1, given=2),
      "class 'Box' expects 1 type arguments, given 2",
    ),
    (
      TypeAliasArityMismatch(q="Pair", expected=2, given=1),
      "type alias 'Pair' expects 2 type arguments, given 1",
    ),
    (DuplicateImportedName(x="a"), "name 'a' imported twice"),
    (
      TypeParameterAsValue(x="T"),
      "'T' is a type parameter, usable only in annotations",
    ),
    (TypeSchemeAsValue(q="f"), "type arguments of 'f' cannot be inferred"),
    (NoTypeArgument(alpha="T"), "type parameter 'T' has no type argument"),
    (
      TypeAliasAsValue(q="Pair"),
      "'Pair' is a type alias, usable only in annotations",
    ),
    (
      KeywordArgumentsNotConstructor,
      "keyword arguments in a call other than a constructor call",
    ),
    (
      PatternClassUndetermined(c="Box", tau="object"),
      "type arguments of 'Box' in pattern not determined by type object",
    ),
    (NoneResult, "call returning None used as an expression"),
    (BareReturn(tau="int"), "bare return in function with result type int"),
    (
      MissingReturnMatchPartial(remaining="str"),
      "cases leave remaining type str, so the function does not always return",
    ),
    (
      MypyCompatibility(NoneResult),
      "call returning None used as an expression (mypy compatibility)",
    ),
    (UnboundName(x="x"), "'x' is unbound"),
    (Redeclaration(x="x"), "'x' is already declared"),
    (UndeclaredAssignment(x="x"), "'x' is assigned but never declared"),
    (
      AssignmentBeforeDeclaration(x="x"),
      "'x' is assigned before its declaration",
    ),
    (Reassignment(x="x"), "'x' is already assigned"),
    (MaybeAssigned(x="x"), "'x' may already be assigned"),
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
    (
      DuplicateMember(x="sub", q="pkg"),
      "duplicate member of module 'pkg': it defines 'sub' and also has submodule 'pkg.sub'",
    ),
    (SubmoduleNotImported(q="a.b"), "submodule 'a.b' is not imported"),
    (
      UnassignedMember(x="x", q="m"),
      "member 'x' of module 'm' is not definitely assigned",
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
    (UnreachableCase(pattern="[a, b]"), "case [a, b] is unreachable"),
    (
      SequenceKindMismatch(kind="list", tau="tuple[int]", other="tuple"),
      "list pattern at tuple[int], which has tuple values",
    ),
    (NotIterable(tau="int"), "values of type int cannot be iterated"),
    (UnknownField(c="P", x="z"), "class 'P' has no field 'z'"),
    (NotSynthesised, "cannot infer type of this expression"),
    (NoAttributes(tau="int"), "values of type int have no attributes"),
    (
      MissingReturn(x="f", tau="int"),
      "'f' declares result type int but does not always return",
    ),
    (
      UnknownMethod(tau="list[int]", x="append"),
      "values of type list[int] have no method 'append'",
    ),
    (
      TupleSliceBounds(tau="tuple[int, str]"),
      "a slice of a value of type tuple[int, str] needs integer literal bounds",
    ),
    (TupleSliceStepZero, "slice step cannot be zero"),
  ]
  assert_eq(cases.length(), 63)
  for c in cases {
    assert_eq(c.0.message(), c.1)
  }
}

///|
test "a rejection's exit code and short form" {
  let d = @err.Diagnostic::new(
    IllFormed(PossiblyUnassigned(x="x", declared_in_branch=false)),
    span={
      start: { line: 3, col: 4, offset: 20, },
      end: { line: 3, col: 5, offset: 21, },
    },
  )
  assert_eq(d.exit_code(), 3)
  assert_eq(d.short("a.py"), "a.py:3:4: 'x' is not definitely assigned")
  // With no position the reference prints the path and the message only.
  let e = @err.Diagnostic::new(Prohibited(msg="del not allowed in PurePy"))
  assert_eq(e.short("a.py"), "a.py: del not allowed in PurePy")
  assert_eq(e.exit_code(), 1)
  assert_eq(
    @err.Reason::PossiblyUnassigned(x="x", declared_in_branch=false).code(),
    "purepy::possibly-unassigned",
  )
}
