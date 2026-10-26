///|
/// The predefined modules of Figure 2.7 and the type of each member: the
/// reference's `PREDEFINED_MEMBERS`.
///
/// `None` for a member usable only in an annotation or as a decorator --
/// `int`, `list`, `Callable`, `dataclass` -- which the checker binds as a
/// name that is not a value. The table lives here, below both the checker and
/// the evaluator, because both have to agree on it: a name the checker
/// accepts and the evaluator has no value for would type-check and then fail
/// to run.
pub fn predefined_members(q : String) -> Array[(String, Type?)]? {
  let float_to_float = Callable([t_float], t_float)
  let float_to_int = Callable([t_float], t_int)
  match q {
    "builtins" =>
      Some([
        ("print", Some(Callable([t_object], t_none))),
        ("len", Some(Callable([t_sized], t_int))),
        ("None", None),
        ("object", None),
        ("bool", None),
        ("int", None),
        ("float", None),
        ("str", None),
        ("list", None),
        ("dict", None),
        ("tuple", None),
      ])
    "math" =>
      Some([
        ("pi", Some(t_float)),
        ("e", Some(t_float)),
        ("sqrt", Some(float_to_float)),
        ("exp", Some(float_to_float)),
        ("log", Some(float_to_float)),
        ("sin", Some(float_to_float)),
        ("cos", Some(float_to_float)),
        ("tan", Some(float_to_float)),
        ("floor", Some(float_to_int)),
        ("ceil", Some(float_to_int)),
      ])
    "sys" =>
      Some([
        ("argv", Some(List(t_str))),
        ("exit", Some(Callable([t_int], t_never))),
      ])
    "typing" =>
      Some([
        ("Callable", None),
        ("Literal", None),
        ("Never", None),
        ("Sized", None),
      ])
    "dataclasses" => Some([("dataclass", None)])
    _ => None
  }
}

///|
/// The modules the specification predefines.
pub let predefined_modules : Array[String] = [
  "builtins", "dataclasses", "math", "sys", "typing",
]
