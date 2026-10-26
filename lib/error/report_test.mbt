///|
/// The human rendering, snapshotted with no colour so that the output is
/// stable. What is being checked is that the second span reaches the report
/// and that the help line says something a person can act on.
fn render(source : String, path : String, d : @err.Diagnostic) -> String {
  let sources = @report.Sources::new()
  let id = sources.add(path, source)
  let config = { ..@render.default_config, format: Rich, color: Never, }
  @render.render_string(d.to_report(id), sources, config, is_tty=false)
}

///|
fn span(from : Int32, to : Int32, line : Int32, col : Int32) -> @basic.Span {
  {
    start: { line, col, offset: from, },
    end: { line, col: col + (to - from), offset: to, },
  }
}

///|
test "a rejection with a second place to look" {
  let source = "x: int = 5\ny = 1\nx = 6\n"
  let d = @err.Diagnostic::new(
    IllFormed(Reassignment(x="x")),
    span=span(17, 22, 3, 0),
  ).with_related(span(0, 10, 1, 0), "'x' assigned here")
  inspect(
    render(source, "a.py", d),
    content=(
      #|error[purepy::reassignment]: 'x' is already assigned
      #|  ╭─[ a.py:3:1 ]
      #|  │
      #|1 │ x: int = 5
      #|  │ ────┬─────
      #|  │     ╰─ 'x' assigned here
      #|2 │ y = 1
      #|3 │ x = 6
      #|  │ ──┬──
      #|  │   ╰─ assigned again here
      #|  │
      #|  ├─ help: a PurePy variable is assigned once; bind a new name instead
      #|  ╰─
      #|
    ),
  )
}

///|
test "a rejection with no position renders as a message alone" {
  let d = @err.Diagnostic::new(Prohibited(msg="del prohibited"))
  inspect(
    render("del x\n", "a.py", d),
    content=(
      #|error[purepy::prohibited]: del prohibited
      #|
    ),
  )
}

///|
test "every reason that earns a help line has one" {
  let with_help : Array[@err.Reason] = [
    UnassignedVariable(x="x"),
    PossiblyUnassigned(x="x", declared_in_branch=false),
    UndeclaredAssignment(x="x"),
    Reassignment(x="x"),
    UnassignedMember(x="x", q="lib"),
    CapturedGeneratorVariable(x="i"),
    ModuleAsValue(q="sys"),
    ClassAsValue(q="P"),
    SubmoduleNotImported(q="pkg.sub"),
    TopLevelReturn,
  ]
  for r in with_help {
    let d = @err.Diagnostic::new(IllFormed(r))
    assert_true(d.help() is Some(_), msg=r.message())
    assert_true(d.code() is Some(_), msg=r.message())
  }
  // A message that already says what to do gets no help line.
  assert_true(
    @err.Diagnostic::new(IllFormed(DuplicateField(x="x", c="P"))).help() is None,
  )
  // A not-yet-supported form points at its issue.
  assert_eq(
    @err.Diagnostic::new(NotYetSupported(feature="slicing", issue=59)).help(),
    Some("tracked upstream as issue #59"),
  )
}
