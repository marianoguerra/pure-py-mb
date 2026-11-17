///|
/// The overloads of the operators: a port of the reference's `operators.py`.
///
/// An overload resolves to the parameter types it was chosen at and its
/// result. The candidates of an operator are tried at the operand types and
/// again at their base types (so `Literal[1] + Literal[2]` finds `int + int`),
/// duplicates are dropped keeping the first, and the least of what is left
/// wins (`minimum`).
pub(all) struct Resolved {
  params : Array[Type]
  result : Type
} derive(Eq, Debug)

///|
fn both(
  sigma : ClassTable,
  s : Type,
  t : Type,
  bound : Type,
  result : Type,
) -> Resolved? {
  if subtype(sigma, s, bound) && subtype(sigma, t, bound) {
    Some({ params: [bound, bound], result, })
  } else {
    None
  }
}

///|
fn equality(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  if !comparable(sigma, s, t) {
    return None
  }
  if !equality_type(sigma, s) || !equality_type(sigma, t) {
    return None
  }
  Some({ params: [s, t], result: t_bool, })
}

///|
/// Whether values of a type can be compared with `==`: comparing them never
/// involves a type variable or a function.
///
/// The mechanisation's `equality_type` (`Operators.thy`), by way of its
/// `needs_eq`, which walks a class's fields generic in its type parameters
/// rather than instantiating them, so that a recursive class terminates.
pub fn equality_type(sigma : ClassTable, t : Type) -> Bool {
  !needs_eq(sigma, [], t, None) &&
  fv(t).iter().all(fn(a) { !needs_eq(sigma, [], t, Some(a)) })
}

///|
/// Whether comparing values of `t` involves a function (`xi` is `None`) or
/// the type variable `xi`. `pending` holds the class and `xi` pairs whose
/// answer is being worked out; asking one again answers `false`, which is the
/// least fixed point the mechanisation's `needs_eq_class` computes.
fn needs_eq(
  sigma : ClassTable,
  pending : Array[(String, String?)],
  t : Type,
  xi : String?,
) -> Bool {
  match t {
    TypeVar(a) => xi == Some(a)
    Callable(_, _) | Defaulted(_, _, _) | Builtin(_) => xi is None
    List(s) | Dict(s) => needs_eq(sigma, pending, s, xi)
    Tuple(ts) => ts.iter().any(fn(s) { needs_eq(sigma, pending, s, xi) })
    Union(a, b) =>
      needs_eq(sigma, pending, a, xi) || needs_eq(sigma, pending, b, xi)
    Class(c, args) => {
      if xi is None && needs_eq_class(sigma, pending, c, None) {
        return true
      }
      let params = type_params_of(sigma, c)
      for i, a in params {
        if i < args.length() &&
          needs_eq_class(sigma, pending, c, Some(a)) &&
          needs_eq(sigma, pending, args[i], xi) {
          return true
        }
      }
      false
    }
    Prim(_) | Literal(_) => false
  }
}

///|
/// Whether comparing values of class `c`, generic in its type parameters,
/// involves a function (`xi` is `None`) or its type parameter `xi`.
fn needs_eq_class(
  sigma : ClassTable,
  pending : Array[(String, String?)],
  c : String,
  xi : String?,
) -> Bool {
  if pending.contains((c, xi)) {
    return false
  }
  let inner = [..pending, (c, xi)]
  fields(sigma, c).fields.iter().any(fn(f) { needs_eq(sigma, inner, f.1, xi) })
}

///|
fn membership_list(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  match t {
    List(e) if comparable(sigma, s, e) =>
      Some({ params: [s, t], result: t_bool, })
    _ => None
  }
}

///|
fn membership_tuple(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  match t {
    Tuple(cs) if comparable(sigma, s, join_seq(sigma, cs)) =>
      Some({ params: [s, t], result: t_bool, })
    _ => None
  }
}

///|
fn membership_str(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  both(sigma, s, t, t_str, t_bool)
}

///|
fn membership_dict(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  match t {
    Dict(_) if subtype(sigma, s, t_str) =>
      Some({ params: [t_str, t], result: t_bool, })
    _ => None
  }
}

///|
fn ordering_number(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  both(sigma, s, t, t_float, t_bool)
}

///|
fn ordering_str(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  both(sigma, s, t, t_str, t_bool)
}

///|
fn arithmetic_int(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  both(sigma, s, t, t_int, t_int)
}

///|
fn arithmetic_float(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  both(sigma, s, t, t_float, t_float)
}

///|
fn concat_str(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  both(sigma, s, t, t_str, t_str)
}

///|
fn concat_list(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  match (s, t) {
    (List(a), List(b)) =>
      Some({ params: [s, t], result: List(join_seq(sigma, [a, b])), })
    _ => None
  }
}

///|
fn concat_tuple(_sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  match (s, t) {
    (Tuple(a), Tuple(b)) => Some({ params: [s, t], result: Tuple([..a, ..b]), })
    _ => None
  }
}

///|
fn repeat_str(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  if subtype(sigma, s, t_str) && subtype(sigma, t, t_int) {
    Some({ params: [t_str, t_int], result: t_str, })
  } else {
    None
  }
}

///|
fn repeat_str_left(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  if subtype(sigma, s, t_int) && subtype(sigma, t, t_str) {
    Some({ params: [t_int, t_str], result: t_str, })
  } else {
    None
  }
}

///|
fn repeat_list(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  if s is List(_) && subtype(sigma, t, t_int) {
    Some({ params: [s, t_int], result: s, })
  } else {
    None
  }
}

///|
fn repeat_list_left(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  if subtype(sigma, s, t_int) && t is List(_) {
    Some({ params: [t_int, t], result: t, })
  } else {
    None
  }
}

///|
/// `n ** k` is an int when the exponent is a literal and not negative, and a
/// float when it is a negative literal. An exponent that is not a literal has
/// no int overload at all, and goes to `float ** float`.
fn power_int(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  match t {
    Literal(Int(k)) if subtype(sigma, s, t_int) =>
      Some({ params: [t_int, t], result: if k < 0N { t_float } else { t_int }, })
    _ => None
  }
}

///|
/// `float ** int`: a float base, an int exponent (`OverloadPowFloat`). A
/// float exponent has no overload since spec v0.24 -- `2.0 ** 0.5` is
/// refused -- so a power is always a repeated product or its reciprocal.
fn power_float(sigma : ClassTable, s : Type, t : Type) -> Resolved? {
  if subtype(sigma, s, t_float) && subtype(sigma, t, t_int) {
    Some({ params: [t_float, t_int], result: t_float, })
  } else {
    None
  }
}

///|
type BinaryOverload = (ClassTable, Type, Type) -> Resolved?

///|
/// The binary operators by the name a message prints.
pub fn binary_overloads(op : String) -> Array[BinaryOverload] {
  match op {
    "==" | "!=" => [equality]
    "|" => []
    "in" | "not in" =>
      [membership_list, membership_tuple, membership_str, membership_dict]
    "<" | "<=" | ">" | ">=" => [ordering_number, ordering_str]
    "+" =>
      [arithmetic_int, arithmetic_float, concat_str, concat_list, concat_tuple]
    "-" | "//" | "%" => [arithmetic_int, arithmetic_float]
    "*" =>
      [
        arithmetic_int, arithmetic_float, repeat_str, repeat_str_left, repeat_list,
        repeat_list_left,
      ]
    "/" => [arithmetic_float]
    "**" => [power_int, power_float]
    _ => abort("no binary operator \{op}")
  }
}

///|
fn negate_bool(sigma : ClassTable, s : Type) -> Resolved? {
  if subtype(sigma, s, t_bool) {
    Some({ params: [t_bool], result: t_bool, })
  } else {
    None
  }
}

///|
fn sign_int(sigma : ClassTable, s : Type) -> Resolved? {
  if subtype(sigma, s, t_int) {
    Some({ params: [t_int], result: t_int, })
  } else {
    None
  }
}

///|
fn sign_float(sigma : ClassTable, s : Type) -> Resolved? {
  if subtype(sigma, s, t_float) {
    Some({ params: [t_float], result: t_float, })
  } else {
    None
  }
}

///|
type UnaryOverload = (ClassTable, Type) -> Resolved?

///|
pub fn unary_overloads(op : String) -> Array[UnaryOverload] {
  match op {
    "not" => [negate_bool]
    "+" | "-" => [sign_int, sign_float]
    _ => abort("no unary operator \{op}")
  }
}

///|
fn dedupe(candidates : Array[Resolved?]) -> Array[Resolved] {
  let out : Array[Resolved] = []
  for c in candidates {
    match c {
      Some(r) => if !out.contains(r) { out.push(r) }
      None => ()
    }
  }
  out
}

///|
pub fn overloads_binary(
  sigma : ClassTable,
  op : String,
  s : Type,
  t : Type,
) -> Array[Resolved] {
  let os = binary_overloads(op)
  dedupe(
    [
      ..os.map(fn(o) { o(sigma, s, t) }),
      ..os.map(fn(o) { o(sigma, base_type(s), base_type(t)) }),
    ],
  )
}

///|
pub fn overloads_unary(
  sigma : ClassTable,
  op : String,
  s : Type,
) -> Array[Resolved] {
  let os = unary_overloads(op)
  dedupe(
    [
      ..os.map(fn(o) { o(sigma, s) }),
      ..os.map(fn(o) { o(sigma, base_type(s)) }),
    ],
  )
}

///|
/// The first candidate whose parameters are below every other candidate's,
/// position by position.
pub fn minimum(sigma : ClassTable, resolved : Array[Resolved]) -> Resolved? {
  for c in resolved {
    if resolved
      .iter()
      .all(fn(o) {
        all_pairs(c.params, o.params, fn(a, b) { subtype(sigma, a, b) })
      }) {
      return Some(c)
    }
  }
  None
}
