///|
/// The interpreter: Chapter 4's rules, rule by rule.
///
/// Every `///|` block below names the rules it implements, so that the spec
/// and the code can be read side by side.
///
/// The state is small on purpose. A run needs somewhere to put what `print`
/// writes, the program's modules, the argument vector, and one thing the spec
/// does not have: a cache of loaded modules. The spec says loading is
/// deterministic and needs no cache, which is true of the VALUES; it is not
/// true of the output, and a module that prints when it loads would print
/// twice under two imports of it. CPython prints once, and CPython is the
/// oracle for what a run prints, so the cache is here and changes nothing
/// else.
using @value {
  type Value,
  type Env,
  type Outcome,
  type StmtResult,
  type MatchResult,
  type Termination,
}

///|
pub struct Interp {
  tree : @program.SourceTree
  host : Host
  /// Module name to the environment it loaded to, for this run only.
  loaded : Map[String, Env]
  /// Module names being loaded, to name a cycle rather than hang. Program
  /// well-formedness rules cycles out, so this only fires when `run` is
  /// asked for a program nobody checked.
  loading : Array[String]
  /// How deep the call stack is, and how deep it may go.
  ///
  /// The semantics allows a program not to terminate, and an infinite
  /// recursion is one that does not; but an evaluator that recurses on the
  /// machine stack meets a stack overflow rather than running forever. The
  /// limit turns that into an answer -- an operation the semantics does not
  /// cover -- which a person can read.
  mut depth : Int
  max_depth : Int
  /// The module whose source is running right now.
  ///
  /// Not the top of `loading`: that is the IMPORT stack, and during a call
  /// into an imported function it still names the importer. This is set from
  /// the module body being loaded and from the callee's closure, and restored
  /// after, so it always names the module the current expression was written
  /// in.
  mut in_module : String
  /// Where the run's first abort happened, once one has.
  ///
  /// First write wins, and nothing ever clears it. That is sound because
  /// `try`/`except` is not PurePy: an abort is never caught, so the first one
  /// constructed is the one the run ends with. It is read only when the run
  /// ends `Terminated`, which is why a pattern that swallows an abort into
  /// `MatchStuck` can leave a value here that nobody looks at.
  mut abort_at : Site?
}

///|
/// Where an abort happened: the module, and the span within it.
///
/// The specification says an implementation "must agree on which kind a run
/// yields, though how it reports one is not prescribed"
/// (`operational-semantics.tex`). This is reporting, then, and not semantics:
/// a `Site` never changes which `Termination` a run yields, and two runs that
/// abort at different places with the same kind still agree.
pub(all) struct Site {
  in_module : String
  span : @basic.Span
} derive(Eq, Debug)

///|
/// `module:line:col`, the site as a person reads it.
pub fn Site::to_display(self : Site) -> String {
  "\{self.in_module}:\{self.span.start.to_display()}"
}

///|
/// Record where an abort happened, if nothing earlier has.
///
/// First write wins, so the INNERMOST construct to abort claims the site and
/// nothing enclosing it can take the site away: in `a + f(b)`, the call and
/// not the sum. That is the expression a person would point at.
///
/// Callers test for an abort before they compute a span, so a construct that
/// yields a value costs one tag test and nothing else. That matters:
/// `eval_expr` is the hottest path there is.
fn Interp::record(self : Interp, span : @basic.Span) -> Unit {
  if self.abort_at is None && span != @basic.nowhere {
    self.abort_at = Some({ in_module: self.in_module, span, })
  }
}

///|
/// `record`, for an outcome that may or may not have aborted.
///
/// A span is computed only when there is an abort, so an expression that
/// yields a value costs one tag test.
fn Interp::sited(self : Interp, e : @ast.Expr, o : Outcome) -> Outcome {
  if o is Aborts(_) {
    self.record(e.span())
  }
  o
}

///|
pub fn Interp::new(
  tree : @program.SourceTree,
  host? : Host = Host::new(),
  max_depth? : Int = default_max_depth,
) -> Interp {
  {
    tree,
    host,
    loaded: Map([]),
    loading: [],
    depth: 0,
    max_depth,
    in_module: "__main__",
    abort_at: None,
  }
}

///|
fn Interp::write(self : Interp, text : String) -> Unit {
  (self.host.write)(text)
}

// ---------------------------------------------------------------------------
// The predefined modules (Figure 2.7)

///|
/// The environment a predefined module loads to, or `None` if `q` is not one.
///
/// `typing` exposes `Any` alone. Figure 2.7 also lists `Callable`; the
/// reference checker does not, and the signature and the environment have to
/// agree or a from-import would type-check and then fail to run.
pub fn Interp::predefined(self : Interp, q : String) -> Env? {
  let entries : Array[(String, Value)] = [("__name__", Str(q))]
  match q {
    "builtins" => {
      entries.push(("print", Prim(Print)))
      entries.push(("len", Prim(Len)))
      entries.push(("range", Prim(Range)))
    }
    "math" => {
      entries.push(("pi", Float(3.141592653589793)))
      entries.push(("e", Float(2.718281828459045)))
      entries.push(("sqrt", Prim(Sqrt)))
      entries.push(("exp", Prim(Exp)))
      entries.push(("log", Prim(Log)))
      entries.push(("sin", Prim(Sin)))
      entries.push(("cos", Prim(Cos)))
      entries.push(("tan", Prim(Tan)))
      entries.push(("floor", Prim(MathFloor)))
      entries.push(("ceil", Prim(MathCeil)))
    }
    "sys" => {
      entries.push(("argv", List(self.host.argv.map(fn(a) { Value::Str(a) }))))
      entries.push(("exit", Prim(Exit)))
    }
    "typing" => entries.push(("Any", Prim(Opaque("Any"))))
    "dataclasses" => entries.push(("dataclass", Prim(Opaque("dataclass"))))
    _ => return None
  }
  Some(@value.env_of(entries))
}
