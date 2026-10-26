///|
/// The class table Σ: every class declared so far, by qualified name.
///
/// A port of the reference's `classes.py`. A class has type parameters, and
/// its base is a class type applied to arguments in terms of them.
pub type ClassTable = @sorted_map.SortedMap[String, ClassTableEntry]

///|
pub(all) struct ClassTableEntry {
  type_params : Array[String]
  own_fields : Array[(String, Type)]
  /// The base class, as a class name and its type arguments.
  base : (String, Array[Type])?
} derive(Eq, Debug)

///|
/// `builtins.range`, the one class the specification predefines.
pub let range_class : String = "builtins.range"

///|
/// The class table every program starts with: `range`, with its `start` and
/// its `stop`.
pub fn predefined_classes() -> ClassTable {
  @sorted_map.SortedMap::new().add(range_class, {
    type_params: [],
    own_fields: [("start", t_int), ("stop", t_int)],
    base: None,
  })
}

///|
pub fn empty_class_table() -> ClassTable {
  @sorted_map.SortedMap::new()
}

///|
/// The last segment of a class's qualified name: what a message prints.
pub fn short_name(c : String) -> String {
  match c.rev_split_once(".") {
    Some((_, last)) => last.to_owned()
    None => c
  }
}

///|
fn entry(sigma : ClassTable, c : String) -> ClassTableEntry {
  match sigma.get(c) {
    Some(e) => e
    None => abort("class \{c} is not in the class table")
  }
}

///|
pub fn type_params_of(sigma : ClassTable, c : String) -> Array[String] {
  entry(sigma, c).type_params
}

///|
pub fn base_of(sigma : ClassTable, c : String) -> (String, Array[Type])? {
  entry(sigma, c).base
}

///|
/// The class and every class it inherits from, nearest first.
pub fn ancestors(sigma : ClassTable, c : String) -> Array[String] {
  match entry(sigma, c).base {
    None => [c]
    Some((b, _)) => [c, ..ancestors(sigma, b)]
  }
}

///|
/// Every field, inherited first, generic in the class's type parameters.
pub fn fields(sigma : ClassTable, c : String) -> FieldScheme {
  let e = entry(sigma, c)
  match e.base {
    None => { type_params: e.type_params, fields: e.own_fields, }
    Some((b, args)) => {
      let inherited = instantiate(fields(sigma, b), args)
      { type_params: e.type_params, fields: [..inherited, ..e.own_fields], }
    }
  }
}

///|
pub fn field_names(sigma : ClassTable, c : String) -> Array[String] {
  fields(sigma, c).fields.map(fn(f) { f.0 })
}

///|
/// A field's type at a class type's arguments.
pub fn field_type(
  sigma : ClassTable,
  c : String,
  args : Array[Type],
  x : String,
) -> Type? {
  for f in instantiate(fields(sigma, c), args) {
    if f.0 == x {
      return Some(f.1)
    }
  }
  None
}

///|
pub fn declared_type(
  sigma : ClassTable,
  c : String,
  args : Array[Type],
  x : String,
) -> Type {
  match field_type(sigma, c, args, x) {
    Some(t) => t
    None => abort("\{c} has no field \{x}")
  }
}

///|
/// Match a constructor's or a pattern's arguments to the class's fields, as
/// pairs in the order the dict the reference builds iterates: the positional
/// ones first, then the keywords as written.
///
/// `None` when the count is wrong, or the keywords are not
/// exactly the fields the positional arguments left over.
pub fn[T] field_map(
  sigma : ClassTable,
  c : String,
  positional : Array[T],
  kwd_names : Array[String],
  kwd_values : Array[T],
) -> Array[(String, T)]? {
  let xs = field_names(sigma, c)
  let n = positional.length()
  if n + kwd_names.length() != xs.length() {
    return None
  }
  for k in kwd_names {
    if !xs[n:].contains(k) {
      return None
    }
  }
  let out : Array[(String, T)] = []
  for i in 0..<n {
    out.push((xs[i], positional[i]))
  }
  for i, k in kwd_names {
    out.push((k, kwd_values[i]))
  }
  Some(out)
}

///|
/// Why `field_map` is undefined.
pub(all) enum FieldMapFailure {
  ArityMismatch(expected~ : Int32, given~ : Int32)
  UnknownKeywordArgs(Array[String])
}

///|
pub fn no_field_map(
  sigma : ClassTable,
  c : String,
  n : Int32,
  kwd_names : Array[String],
) -> FieldMapFailure {
  let xs = field_names(sigma, c)
  if n + kwd_names.length() != xs.length() {
    return ArityMismatch(expected=xs.length(), given=n + kwd_names.length())
  }
  let rest : Array[String] = []
  for x in xs[n:] {
    if !rest.contains(x) {
      rest.push(x)
    }
  }
  @basic.sort_names(rest)
  UnknownKeywordArgs(rest)
}

///|
/// The value `field_map` paired with field `x`.
pub fn[T] lookup(pairs : Array[(String, T)], x : String) -> T {
  for p in pairs {
    if p.0 == x {
      return p.1
    }
  }
  abort("no argument for field \{x}")
}
