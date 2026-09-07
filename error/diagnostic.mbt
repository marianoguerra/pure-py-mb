///|
/// Where a rejection came from, which is the same thing as which exit code it
/// carries. The reference has one script per stage; this port has one type.
pub(all) enum Stage {
  /// CPython would not parse it either.
  Syntax
  /// `syntax.py`: a form PurePy excludes on sight.
  Prohibited
  /// `syntax.py`: a form PurePy plans to accept and does not yet.
  NotYetSupported
  /// `check_module.py`: the module is not well formed.
  IllFormedModule
  /// `check_program.py`: the program is not well formed.
  IllFormedProgram
  /// The run ended in one of the semantics' terminations.
  Abort
  /// The run reached an operation the semantics leaves undefined.
  Stuck
} derive(Eq, Debug)

///|
/// What went wrong, in enough detail to reproduce the reference's message
/// exactly. Every arm's `message` is compared against the reference's, so a
/// wording change here is a conformance failure and not a matter of taste.
pub(all) enum Kind {
  /// Exit 1. A module the reference loads reports this as `parse error: <msg>`.
  PythonSyntax(msg~ : String)
  /// Exit 1. `syntax.py`'s text, verbatim.
  Prohibited(msg~ : String)
  /// Exit 2, printed as `<feature> not yet supported (#<issue>)`.
  NotYetSupported(feature~ : String, issue~ : Int)
  /// Exit 4.
  Program(msg~ : String)
} derive(Eq, Debug)

///|
/// A rejection: what, where, in which module, and what else the reader should
/// look at.
///
/// `related` is this port's addition. The reference records one position; a
/// person reading `'g' captured by previous statement, reassigned here` wants
/// to see the statement that captured it too. `short` never prints it, so the
/// comparison with the reference is unaffected.
pub(all) struct Diagnostic {
  kind : Kind
  span : @basic.Span?
  in_module : String?
  related : Array[(@basic.Span, String)]
} derive(Eq, Debug)

///|
pub fn Diagnostic::new(
  kind : Kind,
  span? : @basic.Span,
  in_module? : String,
  related? : Array[(@basic.Span, String)] = [],
) -> Diagnostic {
  { kind, span, in_module, related, }
}

///|
/// The exit code this rejection carries, as `implementation-plan.md` §2.1 and
/// the reference's scripts fix them.
pub fn Diagnostic::exit_code(self : Diagnostic) -> Int {
  match self.kind {
    PythonSyntax(..) | Prohibited(..) => 1
    NotYetSupported(..) => 2
    Program(..) => 4
  }
}

///|
pub fn Diagnostic::stage(self : Diagnostic) -> Stage {
  match self.kind {
    PythonSyntax(..) => Syntax
    Prohibited(..) => Prohibited
    NotYetSupported(..) => NotYetSupported
    Program(..) => IllFormedProgram
  }
}

///|
/// The message, exactly as the reference prints it.
pub fn Diagnostic::message(self : Diagnostic) -> String {
  match self.kind {
    PythonSyntax(msg~) => msg
    Prohibited(msg~) => msg
    NotYetSupported(feature~, issue~) =>
      "\{feature} not yet supported (#\{issue})"
    Program(msg~) => msg
  }
}

///|
/// `path:line:col: message`, or `path: message` when there is no position --
/// the format `syntax.py` and `check_module.py` print.
///
/// The column is in UTF-8 bytes when a source is given, because that is what
/// CPython's `col_offset` counts and what the reference therefore prints.
/// Without a source the stored code-point column is used, which differs only
/// on a line with a non-ASCII character before the error.
pub fn Diagnostic::short(
  self : Diagnostic,
  path : String,
  source? : @basic.Source,
) -> String {
  match self.span {
    None => "\{path}: \{self.message()}"
    Some(span) => {
      let col = match source {
        Some(src) => src.byte_col(span.start)
        None => span.start.col
      }
      "\{path}:\{span.start.line}:\{col}: \{self.message()}"
    }
  }
}

///|
/// The one error this module raises. Everything that can reject carries a
/// `Diagnostic`, so a caller never has to match on several error types to
/// decide an exit code.
pub suberror PurePyError {
  PurePyError(Diagnostic)
} derive(Eq, Debug)

///|
/// Raise a Python syntax error at `span`.
pub fn syntax_error(msg : String, span : @basic.Span) -> PurePyError {
  PurePyError(Diagnostic::new(PythonSyntax(msg~), span~))
}
