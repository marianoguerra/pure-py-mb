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
}

///|
/// How deep a PurePy call stack may go by default.
///
/// Twice Python's own limit of a thousand, and a third of where this
/// evaluator's stack gives out on a native thread's default 8 MB. A PurePy
/// program is pure and recursion is how it loops, so the default is generous.
///
/// It is a parameter and not a constant because the ceiling is the HOST's,
/// not this evaluator's: a JavaScript engine's stack holds far fewer frames
/// than a native thread's, and a caller running there wants a smaller number.
pub let default_max_depth : Int = 2000

///|
pub fn Interp::new(
  tree : @program.SourceTree,
  host? : Host = Host::new(),
  max_depth? : Int = default_max_depth,
) -> Interp {
  { tree, host, loaded: Map([]), loading: [], depth: 0, max_depth, }
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
