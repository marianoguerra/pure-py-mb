///|
/// Expression evaluation: Figures 4.5 to 4.10.
///
/// Every rule that needs a condition -- `if`, `and`, `or`, a conditional
/// expression, `assert` -- requires an actual `True` or `False`. Python's
/// truthiness is not PurePy's, so `if 5:` has no rule and the run is
/// undefined. That is one of the conformance suite's dynamically excluded
/// tests, and it is the reason `Stuck` is threaded everywhere.
///
/// Where an abort happened is recorded by `sited`, at each of the six places
/// an expression can produce one. Not by wrapping this function: it recurses
/// and it is `async`, so a step after the recursive call is a continuation
/// allocated per expression rather than a tail call, and that measured 21%
/// on a program that does nothing but call.
pub async fn Interp::eval_expr(
  self : Interp,
  e : @ast.Expr,
  env : Env,
) -> Outcome noraise {
  self.machine(Ev(e, env))
}

///|
/// The values of a parameter list's default arguments (#56).
///
/// Only a literal can be a default -- the sieve refuses anything else under
/// the profile that opens them, and the profile is what lets one through at
/// all -- and a literal has no effect and reads no name. So evaluating it here
/// rather than once when the `def` ran is not observable, which is the whole
/// reason the restriction is worth having: Python evaluates a default once and
/// this evaluator has nowhere to put a once, so the feature is drawn where the
/// difference cannot be seen.
///
/// Anything unexpected answers with no defaults, which makes the call an arity
/// error rather than a wrong answer.
fn literal_defaults(args : @ast.Arguments) -> Array[Value] {
  let out : Array[Value] = []
  for d in args.defaults {
    match d {
      Constant(value=Int(n), ..) => out.push(Int(n))
      Constant(value=Float(x), ..) => out.push(Float(x))
      Constant(value=Str(t), ..) => out.push(Str(t))
      Constant(value=Bool(b), ..) => out.push(Bool(b))
      Constant(value=None, ..) => out.push(Value::None)
      _ => return []
    }
  }
  out
}

///|
/// The arguments a call really binds: what it passed, then defaults for the
/// parameters it left out.
///
/// Defaults cover the LAST parameters, as Python's do. `None` is an arity the
/// function has no shape for, which the caller turns into the `TypeError`
/// Python raises.
fn fill_defaults(
  arity : Int,
  defaults : Array[Value],
  actual : Array[Value],
) -> Array[Value]? {
  if actual.length() == arity {
    return Some(actual)
  }
  let required = arity - defaults.length()
  if actual.length() < required || actual.length() > arity {
    return None
  }
  let out = actual.copy()
  for i in (actual.length() - required)..<defaults.length() {
    out.push(defaults[i])
  }
  Some(out)
}

///|
/// The attribute rule, on a receiver that has already been evaluated.
///
/// A function so that a method call can consult it without evaluating the
/// receiver a second time: `eval_call` has the value in hand by the time it
/// knows the receiver is a module or an object.
///
/// The last case is the one that matters. The attributes of a builtin value
/// are undefined -- `xs.append` has no rule -- and that is what makes list
/// mutation unreachable. A profile that adds methods does NOT change it: it
/// adds a rule for `xs.append()`, the call, and leaves `xs.append` the bare
/// attribute exactly as undefined as it was.
fn Interp::attribute_of(
  self : Interp,
  v : Value,
  attr : String,
  at : @ast.Expr,
) -> Outcome {
  match v {
    Mod(q, members) =>
      match members.get(attr) {
        Some(w) => Val(w)
        None => Stuck("module '" + q + "' has no member '" + attr + "'")
      }
    Obj(_, fields_env) =>
      match fields_env.get(attr) {
        Some(w) => Val(w)
        None => self.sited(at, Aborts(AttributeError))
      }
    _ => Stuck("an attribute of " + v.kind_name())
  }
}

///|
/// A method call on a builtin value (`Feature::BuiltinMethods`).
///
/// The tables live in `lib/value` because they are rules about values; the
/// dispatch is here because only the evaluator knows a call happened. A name
/// no table has is the message an unknown attribute already produces, so a
/// typo under this profile reads the way it reads without one.
fn call_method(recv : Value, name : String, args : Array[Value]) -> Outcome {
  let answer = match recv {
    Str(s) => @value.str_method(s, name, args)
    List(xs) | Tuple(xs) => @value.seq_method(xs, name, args)
    Dict(entries) => @value.dict_method(entries, name, args)
    _ => None
  }
  match answer {
    Some(o) => o
    None => Stuck("an attribute of " + recv.kind_name())
  }
}

// ---------------------------------------------------------------------------
// Calls

///|
/// eval-call-lambda, eval-call-def, eval-call-prim and their arity rules.
///
/// An entry into the machine, so that an embedder calling a guest function
/// gets the same unbounded recursion a guest call inside the machine gets.
/// The depth this call takes is counted there, by the call boundary it pushes.
pub async fn Interp::apply(
  self : Interp,
  callee : Value,
  actual : Array[Value],
) -> Outcome noraise {
  self.machine_apply(callee, actual)
}

///|
fn bind(env : Env, params : Array[String], actual : Array[Value]) -> Env {
  let entries : Array[(String, Value)] = []
  for i, p in params {
    entries.push((p, actual[i]))
  }
  @value.override_env(env, @value.env_of(entries))
}

///|
/// `{f⃗: v⃗}`: every definition of a region, as closures over the same
/// environment.
///
/// `in_module` is the module the region was written in, which the closures
/// carry so that an abort inside one is reported against the right file.
pub fn region_bindings(
  env : Env,
  region : Array[@ast.Stmt],
  in_module : String,
) -> Env {
  let entries : Array[(String, Value)] = []
  for i, d in region {
    match d {
      FunctionDef(name~, ..) =>
        entries.push((name, Value::Def({ env, region, index: i, in_module, })))
      _ => ()
    }
  }
  @value.override_env(env, @value.env_of(entries))
}
