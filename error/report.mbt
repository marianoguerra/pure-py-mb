///|
/// The ONE place this module names `error-report`.
///
/// Everything below `error` produces a `Diagnostic`, which is this module's
/// own type and carries no rendering. This function is the whole bridge, so
/// that swapping the renderer is a one-function change and so that
/// `tools/boundary-check.sh` can assert that nothing else links it.
///
/// The rendering adds what the reference does not have and a person wants:
/// a second span for the statement that a message refers to but does not
/// point at, a help line where the fix is not obvious from the message, and
/// a stable code to search for.
pub fn Diagnostic::to_report(
  self : Diagnostic,
  source : @report.SourceId,
) -> @report.Report {
  let mut r = @report.Report::error(self.message())
  match self.code() {
    Some(c) => r = r.with_code(c)
    None => ()
  }
  match self.span {
    Some(s) =>
      r = r.with_label(
        @report.Label::primary(source, span_of(s), message?=self.anchor_note()),
      )
    None => ()
  }
  for extra in self.related {
    r = r.with_label(
      @report.Label::secondary(source, span_of(extra.0), message=extra.1),
    )
  }
  match self.help() {
    Some(h) => r = r.with_help(h)
    None => ()
  }
  r
}

///|
/// A `Span` of this module is two positions; `error-report`'s is an offset
/// and a length, both in UTF-16 code units.
fn span_of(s : @basic.Span) -> @report.Span {
  @report.Span::of_range(s.start.offset, s.end.offset)
}

///|
/// A short, stable code to search for.
pub fn Diagnostic::code(self : Diagnostic) -> String? {
  match self.kind {
    IllFormed(r) => Some(r.code())
    Prohibited(_) => Some("purepy::prohibited")
    NotYetSupported(..) => Some("purepy::not-yet-supported")
    PythonSyntax(_) => Some("purepy::syntax")
    Program(_) => Some("purepy::program")
  }
}

///|
/// What to write against the primary span, when the message alone does not
/// say what is wrong with THAT position.
fn Diagnostic::anchor_note(self : Diagnostic) -> String? {
  match self.kind {
    IllFormed(CapturedReassignment(..)) => Some("reassigned here")
    IllFormed(UnreachableStatement) => Some("never reached")
    IllFormed(UnreachableCase(..)) => Some("never reached")
    IllFormed(SubmoduleNameClash(..)) => Some("bound here")
    IllFormed(ImportAfterStatement) => Some("this import comes too late")
    IllFormed(NonTopLevelImport) => Some("an import inside a body")
    _ => None
  }
}

///|
/// What a person is likely to want to do about it.
///
/// Only where the message does not already say. A rule that is surprising --
/// the capture rules, and the two "not a first-class value" ones -- earns a
/// line; "duplicate field name 'x'" does not.
pub fn Diagnostic::help(self : Diagnostic) -> String? {
  match self.kind {
    IllFormed(UnassignedVariable(..)) =>
      Some("assign it in every branch, or before the if")
    IllFormed(UnassignedMember(..)) =>
      Some(
        "the module assigns it in some branches only; assign it in every branch",
      )
    IllFormed(CapturedReassignment(..)) =>
      Some(
        "a closure captured this name, and PurePy has no cell for it to see a later value; bind a new name instead",
      )
    IllFormed(SelfCaptureAssignment(..)) =>
      Some(
        "the right-hand side closes over the name being bound; give one of them another name",
      )
    IllFormed(CapturedGeneratorVariable(..)) =>
      Some(
        "the generator rebinds the variable on each step, so every lambda would see its last value; pass it as a parameter",
      )
    IllFormed(ModuleAsValue(..)) =>
      Some("name a member of it instead, or import the member directly")
    IllFormed(ClassAsValue(..)) =>
      Some("call it to construct one, or match on it in a pattern")
    IllFormed(SubmoduleNotImported(q~)) =>
      Some("add `import " + q + "` or `from ... import ...` for it")
    IllFormed(TopLevelReturn) =>
      Some("a module body runs to the end; there is nothing to return to")
    IllFormed(OwnDescendantImport(q~, ..)) =>
      Some("use `from " + parent_of(q) + " import " + last_of(q) + "`")
    NotYetSupported(issue~, ..) =>
      Some("tracked upstream as issue #" + issue.to_string())
    _ => None
  }
}

///|
fn parent_of(q : String) -> String {
  match q.rev_split_once(".") {
    Some((head, _)) => head.to_owned()
    None => q
  }
}

///|
fn last_of(q : String) -> String {
  match q.rev_split_once(".") {
    Some((_, tail)) => tail.to_owned()
    None => q
  }
}

///|
/// A diagnostic with a second place to look.
pub fn Diagnostic::with_related(
  self : Diagnostic,
  span : @basic.Span,
  message : String,
) -> Diagnostic {
  let related = self.related.copy()
  related.push((span, message))
  { ..self, related, }
}
