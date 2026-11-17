///|
/// The uses of excluded Python features the checker finds, classified as the
/// reference's `messages.excluded_feature` classifies them (v0.24).
///
/// The reference asks the Python it runs on whether a name it refuses is a
/// built-in, a standard module, a member of a predefined module or a method
/// of a built-in type; `python_names.mbt` is that Python's answers, as
/// tables (`tools/gen_python_names.py`). A name Python has is the use of a
/// feature PurePy excludes, and says so; one Python does not have is an
/// ordinary mistake, and the reason stays as it was.

///|
/// Built-ins, module members and type attributes excluded by design, by
/// qualified name: `messages.EXCLUDED_BY_DESIGN`. Everything else Python has
/// is excluded from this version.
let excluded_by_design_names : Array[String] = [
  "setattr", "delattr", "id", "iter", "next", "eval", "exec", "getattr", "globals",
  "locals", "vars", "__import__", "typing.Any", "typing.cast", "list.append", "list.extend",
  "list.insert", "list.remove", "list.pop", "list.clear", "list.sort", "list.reverse",
  "dict.update", "dict.pop", "dict.popitem", "dict.clear", "dict.setdefault",
]

///|
fn excluded_name(name : String) -> @err.Reason {
  Excluded(
    feature="'\{name}'",
    by_design=excluded_by_design_names.contains(name),
  )
}

///|
fn excluded_for_now(feature : String) -> @err.Reason {
  Excluded(feature~, by_design=false)
}

///|
/// A reason, as the use of an excluded feature when it is one. What `ill`
/// raises, so every refusal of a name passes through here.
fn classified(r : @err.Reason) -> @err.Reason {
  match r {
    UndefinedVariable(x~) if python_builtins.contains(x) => excluded_name(x)
    UnknownModule(q~) => {
      let root = match q.split_once(".") {
        Some((r, _)) => r.to_owned()
        None => q
      }
      if python_stdlib_modules.contains(root) {
        excluded_for_now("module '\{q}'")
      } else {
        r
      }
    }
    UnknownMember(x~, q~) =>
      match python_module_members(q) {
        Some(members) if members.contains(x) => excluded_name("\{q}.\{x}")
        _ => r
      }
    MypyCompatibility(inner) =>
      match classified(inner) {
        Excluded(..) as e => e
        _ => r
      }
    _ => r
  }
}

///|
/// The Python class of a built-in type's values, for `hasattr(t, x)`; `None`
/// for a class, a function, a union and the rest.
fn python_class_of(t : @types.Type) -> String? {
  match t {
    List(_) => Some("list")
    Dict(_) => Some("dict")
    Tuple(_) => Some("tuple")
    Prim(Bool) | Literal(Bool(_)) => Some("bool")
    Prim(Int) | Literal(Int(_)) => Some("int")
    Prim(Float) => Some("float")
    Prim(Str) | Literal(Str(_)) => Some("str")
    _ => None
  }
}

///|
/// `x.attr` on a value of a type with no attributes: a method of a built-in
/// type when Python's type has one by that name.
fn no_attributes(obj : @types.Type, attr : String, tau : String) -> @err.Reason {
  match python_class_of(obj) {
    Some(c) =>
      match python_type_attrs(c) {
        Some(attrs) if attrs.contains(attr) => excluded_name("\{c}.\{attr}")
        _ => NoAttributes(tau~)
      }
    None => NoAttributes(tau~)
  }
}

///|
/// The callee as a dotted name, `None` for any other expression:
/// `messages.callee_name`.
fn callee_name(e : @ast.Expr) -> String? {
  match e {
    Name(id~, ..) => Some(id)
    Attribute(value~, attr~, ..) =>
      match callee_name(value) {
        Some(q) => Some("\{q}.\{attr}")
        None => None
      }
    _ => None
  }
}

///|
/// A call of the wrong arity, or one of the two call forms the reference
/// excludes from this version by arity: `round(x, n)` and `sys.exit()`.
fn arity_mismatch(
  func : @ast.Expr,
  expected : Int32,
  given : Int32,
) -> @err.Reason {
  match (callee_name(func), expected, given) {
    (Some("round"), 1, 2) => excluded_for_now("round with second argument")
    (Some("sys.exit" | "exit"), 1, 0) =>
      excluded_for_now("sys.exit with no arguments")
    _ => CallArityMismatch(expected~, given~)
  }
}
