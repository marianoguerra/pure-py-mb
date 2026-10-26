///|
/// What a predefined member is to the checker.
pub(all) enum Member {
  /// A value of a type.
  Typed(Type)
  /// A name usable only in an annotation or as a decorator: `int`, `list`,
  /// `Callable`, `dataclass`.
  AnnotationOnly
  /// A class, by its qualified name in the class table: `range`.
  ClassOf(String)
} derive(Eq, Debug)

///|
/// The predefined modules of Figure 2.7 and what each member is: the
/// reference's `PREDEFINED_MEMBERS`. The table lives here, below both the checker and
/// the evaluator, because both have to agree on it: a name the checker
/// accepts and the evaluator has no value for would type-check and then fail
/// to run.
pub fn predefined_members(q : String) -> Array[(String, Member)]? {
  match q {
    "builtins" =>
      Some([
        ("print", Typed(Callable([t_object], t_none))),
        ("len", Typed(Callable([t_sized], t_int))),
        ("range", ClassOf(range_class)),
        ("round", Typed(Callable([t_float], t_int))),
        ("None", AnnotationOnly),
        ("object", AnnotationOnly),
        ("bool", AnnotationOnly),
        ("int", AnnotationOnly),
        ("float", AnnotationOnly),
        ("str", AnnotationOnly),
        ("list", AnnotationOnly),
        ("dict", AnnotationOnly),
        ("tuple", AnnotationOnly),
      ])
    "sys" =>
      Some([
        ("argv", Typed(List(t_str))),
        ("exit", Typed(Callable([t_int], t_never))),
      ])
    "typing" =>
      Some([
        ("Callable", AnnotationOnly),
        ("Literal", AnnotationOnly),
        ("Never", AnnotationOnly),
        ("Sized", AnnotationOnly),
      ])
    "dataclasses" => Some([("dataclass", AnnotationOnly)])
    _ => None
  }
}

///|
/// The modules the specification predefines.
pub let predefined_modules : Array[String] = [
  "builtins", "dataclasses", "sys", "typing",
]
