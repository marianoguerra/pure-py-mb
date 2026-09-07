///|
/// Every reason's message, against the text `reasons.py` produces.
///
/// These strings are the `.error.expected` files of the conformance suite, so
/// this test is where a wording change is caught before the suite catches it.
test "the reason catalogue" {
  let cases : Array[(@err.Reason, String)] = [
    (
      DuplicateFieldName(name="x", cls="P"),
      "duplicate field name 'x' in class 'P'",
    ),
    (
      UnknownBaseClass(base="B"),
      "base class 'B' is not declared in this module",
    ),
    (
      InheritedFieldClash(field="x", base="B"),
      "field 'x' clashes with inherited field from 'B'",
    ),
    (
      DuplicateClassName(name="P", in_module="__main__"),
      "duplicate class name 'P' in module '__main__'",
    ),
    (UnassignedVariable(name="x"), "'x' is not definitely assigned"),
    (
      CapturedReassignment(name="g"),
      "'g' captured by previous statement, reassigned here",
    ),
    (SelfCaptureAssignment(name="f"), "'f' captured by right-hand side"),
    (
      CapturedGeneratorVariable(name="i"),
      "'i' bound by a generator, captured by a lambda",
    ),
    (UnreachableStatement, "unreachable statement"),
    (
      ConstructorArityMismatch(cls="P", expected=2, got=3),
      "constructor for 'P' expects 2 arguments, got 3",
    ),
    (
      UnknownConstructorKeyword(cls="P", expected_fields=["x", "y"]),
      "constructor keywords for 'P' must be x, y",
    ),
    (
      PatternArityMismatch(cls="P", expected=2, got=1),
      "pattern for 'P' expects 2 sub-patterns, got 1",
    ),
    (UnknownClassInPattern(cls="Q"), "'Q' is not a declared class"),
    (
      UnknownFieldInPattern(cls="P", expected_fields=["y"]),
      "pattern keywords for 'P' must be y",
    ),
    (DuplicatePatternKeyword(cls="P"), "duplicate keyword in pattern for 'P'"),
    (DuplicateDictKey(key="k"), "duplicate key 'k' in dict pattern"),
    (NonlinearPattern(index=2), "repeated variable in pattern 2"),
    (
      UnreachableCase(index=3, subsumed_by=1),
      "case 3 unreachable: subsumed by case 1",
    ),
    (DuplicateMutualName(name="f"), "duplicate name 'f' in mutual region"),
    (NonTopLevelImport, "import only allowed at module top level"),
    (ImportAfterStatement, "imports must precede all other statements"),
    (
      SubmoduleNameClash(name="sub", submodule="pkg.sub"),
      "binding 'sub' clashes with submodule 'pkg.sub'",
    ),
    (SubmoduleNotImported(q="pkg.sub"), "submodule 'pkg.sub' is not imported"),
    (
      UnassignedMember(x="x", q="lib"),
      "member 'x' of module 'lib' is not definitely assigned",
    ),
    (
      TopLevelReturn,
      "top-level return not allowed (module body must not return)",
    ),
    (EmptyFromImport, "empty name list"),
    (UnknownModule(q="helper"), "unknown module 'helper'"),
    (UnknownMember(x="y", q="m"), "module 'm' has no member 'y'"),
    (
      ModuleAsValue(name="sys"),
      "'sys' refers to a module; modules are not first-class values",
    ),
    (
      OwnDescendantImport(q="pkg.sub", q0="pkg"),
      "'pkg.sub' is a descendant of the importing module 'pkg'; import it with a from-import",
    ),
    (
      ClassAsValue(name="Point"),
      "'Point' refers to a class; classes are not first-class values",
    ),
  ]
  assert_eq(cases.length(), 31)
  for c in cases {
    assert_eq(c.0.message(), c.1)
  }
}

///|
test "a rejection's exit code and short form" {
  let d = @err.Diagnostic::new(IllFormed(UnassignedVariable(name="x")), span={
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
    @err.Reason::UnassignedVariable(name="x").code(),
    "purepy::unassigned-variable",
  )
}
