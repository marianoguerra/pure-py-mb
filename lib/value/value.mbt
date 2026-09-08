///|
/// Runtime values, environments and evaluation results: Figure 4.1.
///
/// Two things about this type are the whole shape of the language:
///
///   * **Nothing is mutable.** A list, a tuple, a dictionary and an object are
///     built once and never changed, so an environment can be shared by every
///     closure that captures it and nothing has to be copied defensively.
///   * **`Stuck` is a result, not a crash.** The semantics leaves some
///     operations undefined, and Chapter 1 allows an implementation either to
///     abort or to produce Python's answer. This one aborts, with the
///     operation named, so that the conformance suite's dynamically excluded
///     bucket is CHECKED rather than merely tolerated.
pub(all) enum Value {
  None
  Bool(Bool)
  Int(BigInt)
  Float(Double)
  Str(String)
  List(Array[Value])
  Tuple(Array[Value])
  /// Insertion order, later entries replacing earlier ones under the same key.
  /// Keys are strings: a dictionary with any other key is undefined.
  Dict(Array[(String, Value)])
  /// `LamΓ(ρ, x⃗, e)`.
  Lam(LamClosure)
  /// `DefΓ(ρ, d⃗, i)`: the environment, the whole mutual region, and which of
  /// its definitions this value is. Calling one rebinds the WHOLE region, and
  /// that is what makes `even` and `odd` see each other.
  Def(DefClosure)
  /// `ObjΓ(C, ρ)`: the class entry, and every field, inherited first.
  Obj(@context.ClassEntry, Env)
  /// `Mod(q)`: a module named and not loaded.
  ModStub(String)
  /// `Mod(q, ρ)`.
  Mod(String, Env)
  /// `ClsΓ(q.c, x⃗, c')`.
  Class(@context.ClassEntry)
  /// `Prim(f)`.
  Prim(Primitive)
} derive(Debug)

///|
/// `in_module` is not part of `LamΓ`: the spec's closures carry an
/// environment and a body, and nothing about where they were written. It is
/// here because a position without a file is a lie the moment a program has
/// two modules -- a `helper.py` function that aborts on its line 4 would be
/// read as line 4 of `__main__`. The evaluator's import stack cannot supply
/// it, because during a call it names the module that IMPORTED the callee,
/// not the one that defined it. Only the closure knows.
pub(all) struct LamClosure {
  env : Env
  params : Array[String]
  /// The values of the trailing parameters' defaults (#56), empty without the
  /// profile that opens them. They are literals, so evaluating them when the
  /// closure was made and evaluating them at the call are the same thing --
  /// which is why they can be values here rather than expressions.
  defaults : Array[Value]
  body : @ast.Expr
  /// The module whose source `body` was read from.
  in_module : String
} derive(Debug)

///|
pub(all) struct DefClosure {
  env : Env
  region : Array[@ast.Stmt]
  index : Int
  /// The module whose source `region` was read from.
  in_module : String
} derive(Debug)

///|
/// An environment: `ρ`. Immutable, because a closure captures one by value.
pub type Env = @hashmap.HashMap[String, Value]

///|
pub fn empty_env() -> Env {
  @hashmap.HashMap::new()
}

///|
pub fn env_of(entries : Array[(String, Value)]) -> Env {
  @hashmap.HashMap(entries[:])
}

///|
/// `ρ ⊗ ρ'`: the right-hand side wins outright.
pub fn override_env(a : Env, b : Env) -> Env {
  let mut out = a
  b.each(fn(k, v) { out = out.add(k, v) })
  out
}

///|
/// `ρ ⊲ ρ'`: extension, which differs from override only on modules -- a
/// loaded module is preferred to a stub of the same module, and two loadings
/// of one module merge member by member.
pub fn extend_env(a : Env, b : Env) -> Env {
  let mut out = a
  b.each(fn(k, v) {
    out = out.add(
      k,
      match a.get(k) {
        Some(old) => extend_value(old, v)
        None => v
      },
    )
  })
  out
}

///|
pub fn extend_value(a : Value, b : Value) -> Value {
  match (a, b) {
    (Mod(qa, ma), Mod(qb, mb)) if qa == qb => Mod(qa, extend_env(ma, mb))
    (Mod(qa, _), ModStub(qb)) if qa == qb => a
    _ => b
  }
}

///|
/// The predefined functions of Figure 2.7.
///
/// `Opaque` is for the three members that are values only so that importing
/// them binds something: `typing.Any`, `typing.Callable` and
/// `dataclasses.dataclass` are never called.
pub(all) enum Primitive {
  Print
  Len
  Range
  Exit
  Sqrt
  Exp
  Log
  Sin
  Cos
  Tan
  MathFloor
  MathCeil
  /// The builtins a profile adds (`Feature::ExtraBuiltins`), which the
  /// specification does not have.
  ///
  /// Arms are appended, never inserted. They are in the enum unconditionally
  /// because a `Primitive` is data: what makes one reachable is being bound in
  /// an environment, and only a profile that asked puts these there.
  Abs
  All
  Any
  DivMod
  Enumerate
  ToFloat
  ToInt
  ToList
  Max
  Min
  Repr
  Reversed
  Round
  Sorted
  ToStr
  Sum
  ToTuple
  Zip
  Opaque(String)
  /// A function the HOST supplies, named rather than carried.
  ///
  /// The name is data, not a closure, so a `Value` stays comparable,
  /// printable and free of the host's types; the host dispatches on it when
  /// the guest calls. That is what lets a `Value` cross the boundary at all.
  Foreign(String)
} derive(Eq, Debug)

///|
/// How a run ends. Every kind but `SystemExit` is named after the exception
/// the same program raises under Python.
pub(all) enum Termination {
  TypeError
  IndexError
  KeyError
  ZeroDivisionError
  AttributeError
  AssertionError(String?)
  SystemExit(BigInt)
} derive(Eq, Debug)

///|
/// The name Python prints for a termination, and the message after it.
pub fn Termination::name(self : Termination) -> String {
  match self {
    TypeError => "TypeError"
    IndexError => "IndexError"
    KeyError => "KeyError"
    ZeroDivisionError => "ZeroDivisionError"
    AttributeError => "AttributeError"
    AssertionError(_) => "AssertionError"
    SystemExit(_) => "SystemExit"
  }
}

///|
/// `AssertionError: message` when there is one, the bare name otherwise --
/// the last line of the traceback Python prints.
pub fn Termination::to_text(self : Termination) -> String {
  match self {
    AssertionError(Some(m)) => "AssertionError: " + m
    SystemExit(n) => "SystemExit: " + n.to_string()
    other => other.name()
  }
}

///|
/// The outcome of evaluating an expression: a value, an abort, or an
/// operation the semantics leaves undefined.
pub(all) enum Outcome {
  Val(Value)
  Aborts(Termination)
  Stuck(String)
} derive(Debug)

///|
/// The result of evaluating a statement.
pub(all) enum StmtResult {
  Assigns(Env)
  Returns(Value)
  ResultAborts(Termination)
  ResultStuck(String)
} derive(Debug)

///|
/// Whether a pattern matched, and what it bound.
pub(all) enum MatchResult {
  Match(Env)
  NoMatch
  MatchStuck(String)
} derive(Debug)

///|
/// `outcome(r)`: a statement's result read as the outcome of calling it.
pub fn StmtResult::outcome(self : StmtResult) -> Outcome {
  match self {
    Returns(v) => Val(v)
    Assigns(_) => Val(None)
    ResultAborts(k) => Aborts(k)
    ResultStuck(op) => Stuck(op)
  }
}

///|
/// Sequential composition of results: `assigns ρ ⊗ r`.
pub fn StmtResult::then(self : StmtResult, other : StmtResult) -> StmtResult {
  match self {
    Assigns(a) =>
      match other {
        Assigns(b) => Assigns(override_env(a, b))
        _ => other
      }
    _ => self
  }
}

///|
/// `m ⊗ m'`: a match result composes by union of bindings, and no-match is
/// absorbing.
pub fn MatchResult::then(
  self : MatchResult,
  other : MatchResult,
) -> MatchResult {
  match (self, other) {
    (MatchStuck(op), _) => MatchStuck(op)
    (_, MatchStuck(op)) => MatchStuck(op)
    (NoMatch, _) | (_, NoMatch) => NoMatch
    (Match(a), Match(b)) => Match(override_env(a, b))
  }
}

///|
/// What kind of value this is, for a message naming an undefined operation.
pub fn Value::kind_name(self : Value) -> String {
  match self {
    None => "None"
    Bool(_) => "bool"
    Int(_) => "int"
    Float(_) => "float"
    Str(_) => "str"
    List(_) => "list"
    Tuple(_) => "tuple"
    Dict(_) => "dict"
    Lam(_) | Def(_) => "function"
    Obj(c, _) => c.short_name()
    ModStub(_) | Mod(_, _) => "module"
    Class(_) => "class"
    Prim(_) => "builtin"
  }
}

///|
/// What to call a primitive, for an embedder that has to render one.
///
/// A `Prim` has no printable form -- `Value::str` and `Value::repr` answer
/// `None` for one, because Python prints an address no implementation can
/// reproduce -- so a host that wants to show something in its place has to name
/// it. Without this it spells all thirty out, which is a fourth table agreeing
/// with the three this library already keeps in line, and the only one of the
/// four that upstream cannot test.
///
/// **The answer comes from two different places, and the difference is worth
/// knowing before you render it.**
///
///   * A primitive the SPECIFICATION defines answers with the name it is bound
///     under. `MathFloor` is `floor` and not `math.floor`: the name is the
///     member's, and which module it came from is the environment's business.
///     `lib/eval/predefined_wbtest.mbt` asserts exactly that, for every
///     predefined module under every profile -- so this is not a fourth table,
///     it is the same table read back, and a builtin some later profile adds
///     fails that test rather than quietly leaving a consumer's list short.
///
///   * A primitive the HOST defines answers with the name the host registered,
///     which is `@value.host_fn`'s argument and NOT necessarily the name it is
///     bound under. A host is free to bind `record` to `host_fn("host.record")`
///     -- `docs/embedding.mbt.md` does -- and then this answers `host.record`.
///     That is the useful answer rather than an accident of it: a qualified
///     name is the spelling a reader would have to type, and the host is the
///     only party that knows what qualification means to it.
///
/// So a host that wants its own functions rendered a particular way chooses
/// that when it registers them, not when it renders them.
pub fn Primitive::name(self : Primitive) -> String {
  match self {
    Print => "print"
    Len => "len"
    Range => "range"
    Exit => "exit"
    Sqrt => "sqrt"
    Exp => "exp"
    Log => "log"
    Sin => "sin"
    Cos => "cos"
    Tan => "tan"
    MathFloor => "floor"
    MathCeil => "ceil"
    Abs => "abs"
    All => "all"
    Any => "any"
    DivMod => "divmod"
    Enumerate => "enumerate"
    ToFloat => "float"
    ToInt => "int"
    ToList => "list"
    Max => "max"
    Min => "min"
    Repr => "repr"
    Reversed => "reversed"
    Round => "round"
    Sorted => "sorted"
    ToStr => "str"
    Sum => "sum"
    ToTuple => "tuple"
    Zip => "zip"
    Opaque(name) => name
    Foreign(name) => name
  }
}

///|
/// A function the host supplies, as a value the guest can call.
///
/// The host puts one of these in a module (`@eval.HostModule`) and answers
/// calls to it by name.
pub fn host_fn(name : String) -> Value {
  Prim(Foreign(name))
}
