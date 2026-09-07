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
fn span(from : Int, to : Int, line : Int, col : Int) -> @basic.Span {
  {
    start: { line, col, offset: from, },
    end: { line, col: col + (to - from), offset: to, },
  }
}

///|
test "a rejection with a second place to look" {
  let source = "x = 5\nf = lambda: x\nx = 6\n"
  let d = @err.Diagnostic::new(
    IllFormed(CapturedReassignment(name="x")),
    span=span(20, 25, 3, 0),
  ).with_related(span(6, 19, 2, 0), "'x' captured here")
  inspect(
    render(source, "a.py", d),
    content=(
      #|error[purepy::captured-reassignment]: 'x' captured by previous statement, reassigned here
      #|  ╭─[ a.py:3:1 ]
      #|  │
      #|1 │ x = 5
      #|2 │ f = lambda: x
      #|  │ ──────┬──────
      #|  │       ╰─ 'x' captured here
      #|3 │ x = 6
      #|  │ ──┬──
      #|  │   ╰─ reassigned here
      #|  │
      #|  ├─ help: a closure captured this name, and PurePy has no cell for it to see a later value; bind a new name instead
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
    UnassignedVariable(name="x"),
    UnassignedMember(x="x", q="lib"),
    CapturedReassignment(name="x"),
    SelfCaptureAssignment(name="f"),
    CapturedGeneratorVariable(name="i"),
    ModuleAsValue(name="sys"),
    ClassAsValue(name="P"),
    SubmoduleNotImported(q="pkg.sub"),
    TopLevelReturn,
    OwnDescendantImport(q="pkg.sub", q0="pkg"),
  ]
  for r in with_help {
    let d = @err.Diagnostic::new(IllFormed(r))
    assert_true(d.help() is Some(_), msg=r.message())
    assert_true(d.code() is Some(_), msg=r.message())
  }
  // A message that already says what to do gets no help line.
  assert_true(
    @err.Diagnostic::new(IllFormed(DuplicateFieldName(name="x", cls="P"))).help()
    is None,
  )
  // The `from-import` advice names the parent and the member.
  assert_eq(
    @err.Diagnostic::new(IllFormed(OwnDescendantImport(q="pkg.sub", q0="pkg"))).help(),
    Some("use `from pkg import sub`"),
  )
  // A not-yet-supported form points at its issue.
  assert_eq(
    @err.Diagnostic::new(NotYetSupported(feature="slicing", issue=59)).help(),
    Some("tracked upstream as issue #59"),
  )
}
