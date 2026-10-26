///|
/// The class table Σ: every class declared so far, by qualified name.
///
/// A port of the reference's `classes.py`. Σ is threaded through checking the
/// way the context is, and returned with it, so it is immutable: a class
/// declared while checking one branch of an import must not appear in another.
pub type ClassTable = @sorted_map.SortedMap[String, ClassTableEntry]

///|
pub(all) struct ClassTableEntry {
  own_fields : Array[(String, Type)]
  base : String?
} derive(Eq, Debug)

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
/// The class and every class it inherits from, nearest first.
pub fn ancestors(sigma : ClassTable, c : String) -> Array[String] {
  match entry(sigma, c).base {
    None => [c]
    Some(b) => [c, ..ancestors(sigma, b)]
  }
}

///|
/// Every field, inherited first.
pub fn fields(sigma : ClassTable, c : String) -> Array[String] {
  let e = entry(sigma, c)
  let own = e.own_fields.map(fn(p) { p.0 })
  match e.base {
    None => own
    Some(b) => [..fields(sigma, b), ..own]
  }
}

///|
/// A field's declared type, looked up through the ancestors.
pub fn field_type(sigma : ClassTable, c : String, x : String) -> Type? {
  let e = entry(sigma, c)
  for p in e.own_fields {
    if p.0 == x {
      return Some(p.1)
    }
  }
  match e.base {
    None => None
    Some(b) => field_type(sigma, b, x)
  }
}

///|
pub fn declared_type(sigma : ClassTable, c : String, x : String) -> Type {
  match field_type(sigma, c, x) {
    Some(t) => t
    None => abort("\{c} has no field \{x}")
  }
}

///|
/// Match a constructor's or a pattern's arguments to the class's fields, as
/// pairs in the order the dict the reference builds iterates: the positional
/// ones first, then the keywords as written.
///
/// `None` when the count is wrong, a keyword repeats, or the keywords are not
/// exactly the fields the positional arguments left over.
pub fn[T] field_map(
  sigma : ClassTable,
  c : String,
  positional : Array[T],
  kwd_names : Array[String],
  kwd_values : Array[T],
) -> Array[(String, T)]? {
  let xs = fields(sigma, c)
  let n = positional.length()
  if n + kwd_names.length() != xs.length() {
    return None
  }
  for i, k in kwd_names {
    for j in 0..<i {
      if kwd_names[j] == k {
        return None
      }
    }
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
/// The value `field_map` paired with field `x`.
pub fn[T] lookup(pairs : Array[(String, T)], x : String) -> T {
  for p in pairs {
    if p.0 == x {
      return p.1
    }
  }
  abort("no argument for field \{x}")
}
