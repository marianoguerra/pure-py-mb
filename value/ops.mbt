///|
/// The functions on values of Annex A.3: equality, membership, elements,
/// iteration, subscripting and the dictionary builders.
///
/// Equality is PARTIAL, and the order in which elements are compared is
/// therefore observable: `eq` short-circuits at the first pair that decides
/// the answer, so an undefined comparison later in a sequence does not make
/// the whole comparison undefined. `[1, "a"] == [1, 3]` is stuck and
/// `[1, "a"] == [2, 3]` is False, and the difference is deliberate.
///
/// Every function that can be undefined returns a `Bool?` or an `Outcome`;
/// `None` and `Stuck` mean "no rule", not "false".
pub fn eq(a : Value, b : Value) -> Bool? {
  match (a, b) {
    // `None` compares with anything.
    (None, None) => Some(true)
    (None, _) | (_, None) => Some(false)
    (Bool(x), Bool(y)) => Some(x == y)
    (Int(x), Int(y)) => Some(x == y)
    (Float(x), Float(y)) =>
      // `nan` against `nan` has no rule; the `==` OPERATOR has one, which is
      // why `nan == nan` is False and `[nan] == [nan]` is stuck.
      if x.is_nan() && y.is_nan() {
        Option::None
      } else {
        Some(x == y)
      }
    // An integer and a float compare numerically and exactly, as they do in
    // Python and as the pattern checker's subsumption already assumes.
    (Int(x), Float(y)) => int_float_eq(x, y)
    (Float(x), Int(y)) => int_float_eq(y, x)
    (Str(x), Str(y)) => Some(x == y)
    (List(xs), List(ys)) | (Tuple(xs), Tuple(ys)) => eq_elems(xs, ys)
    (Dict(x), Dict(y)) => {
      if x.length() != y.length() {
        return Some(false)
      }
      // Compared in the entry order of the LEFT operand.
      let left : Array[Value] = []
      let right : Array[Value] = []
      for e in x {
        match lookup(y, e.0) {
          Option::None => return Some(false)
          Some(v) => {
            left.push(e.1)
            right.push(v)
          }
        }
      }
      eq_elems(left, right)
    }
    (Obj(ca, ra), Obj(cb, rb)) => {
      if ca.name != cb.name {
        return Some(false)
      }
      let left : Array[Value] = []
      let right : Array[Value] = []
      for x in ca.fields() {
        match (ra.get(x), rb.get(x)) {
          (Some(u), Some(v)) => {
            left.push(u)
            right.push(v)
          }
          _ => return Option::None
        }
      }
      eq_elems(left, right)
    }
    _ => Option::None
  }
}

///|
fn int_float_eq(n : BigInt, d : Double) -> Bool? {
  if d.is_nan() {
    // A number against `nan`: different values, so False. Only `nan` against
    // `nan` has no rule.
    return Some(false)
  }
  match exact_integer(d) {
    Some(m) => Some(m == n)
    Option::None => Some(false)
  }
}

///|
/// The integer a double exactly equals, or `None` when it is not one.
///
/// Read off the bit pattern rather than through decimal text, so it is exact
/// at every magnitude: a double is `mantissa * 2^exponent`, and when it is
/// integral the shift below loses nothing.
pub fn exact_integer(d : Double) -> BigInt? {
  if d.is_nan() || d.is_inf() || d != d.floor() {
    return Option::None
  }
  let bits = d.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent = ((bits >> 52) & 0x7FFUL).to_int()
  let fraction = bits & 0xFFFFFFFFFFFFFUL
  let (mantissa, shift) = if exponent == 0 {
    (fraction, -1074)
  } else {
    (fraction | (1UL << 52), exponent - 1075)
  }
  let mut n = BigInt::from_uint64(mantissa)
  if shift > 0 {
    n = n << shift
  } else if shift < 0 {
    n = n >> -shift
  }
  Some(if negative { -n } else { n })
}

///|
fn lookup(entries : Array[(String, Value)], key : String) -> Value? {
  for e in entries {
    if e.0 == key {
      return Some(e.1)
    }
  }
  Option::None
}

///|
/// Elementwise equality, stopping at the first pair that decides it.
pub fn eq_elems(xs : Array[Value], ys : Array[Value]) -> Bool? {
  if xs.length() != ys.length() {
    return Some(false)
  }
  for i in 0..<xs.length() {
    match eq(xs[i], ys[i]) {
      Some(false) => return Some(false)
      Some(true) => ()
      Option::None => return Option::None
    }
  }
  Some(true)
}

///|
/// Whether `needle` is in `haystack`: an element of a list or tuple, a key of
/// a dictionary, a substring of a string.
pub fn contains(haystack : Value, needle : Value) -> Bool? {
  match haystack {
    List(xs) | Tuple(xs) => contains_elems(xs, needle)
    Dict(entries) =>
      match needle {
        Str(w) => Some(lookup(entries, w) is Some(_))
        _ => Option::None
      }
    Str(w) =>
      match needle {
        Str(sub) => Some(w.contains(sub))
        _ => Option::None
      }
    _ => Option::None
  }
}

///|
pub fn contains_elems(xs : Array[Value], needle : Value) -> Bool? {
  for x in xs {
    match eq(needle, x) {
      Some(true) => return Some(true)
      Some(false) => ()
      Option::None => return Option::None
    }
  }
  Some(false)
}

///|
/// The elements of a list, a tuple or a string. A string's elements are its
/// CODE POINTS, which is what Python iterates.
pub fn elems(v : Value) -> Array[Value]? {
  match v {
    List(xs) | Tuple(xs) => Some(xs)
    Str(s) => Some(s.to_array().map(fn(c) { Value::Str(c.to_string()) }))
    _ => Option::None
  }
}

///|
/// What a generator draws from a value: the KEYS of a dictionary, and
/// otherwise its elements.
pub fn iter(v : Value) -> Array[Value]? {
  match v {
    Dict(entries) => Some(entries.map(fn(e) { Value::Str(e.0) }))
    other => elems(other)
  }
}

///|
/// Subscripting: a dictionary by a string key, a sequence by an integer index
/// counting from the end when negative.
pub fn getitem(v : Value, key : Value) -> Outcome {
  match v {
    Dict(entries) =>
      match key {
        Str(w) =>
          match lookup(entries, w) {
            Some(found) => Val(found)
            Option::None => Aborts(KeyError)
          }
        // A dictionary subscripted by anything but a string is undefined --
        // not a KeyError.
        _ => Stuck("subscripting a dict with " + key.kind_name())
      }
    _ =>
      match elems(v) {
        Option::None => Aborts(TypeError)
        Some(xs) =>
          match key {
            Int(n) => {
              let len = BigInt::from_int(xs.length())
              let i = if n < 0N { n + len } else { n }
              if i < 0N || i >= len {
                Aborts(IndexError)
              } else {
                Val(xs[i.to_int()])
              }
            }
            _ => Aborts(TypeError)
          }
      }
  }
}

///|
/// `update(δ, w, v)`: the entries with `w` bound to `v`, in place if it was
/// already there and appended otherwise.
pub fn update(
  entries : Array[(String, Value)],
  key : String,
  v : Value,
) -> Array[(String, Value)] {
  let out : Array[(String, Value)] = []
  let mut replaced = false
  for e in entries {
    if e.0 == key {
      out.push((key, v))
      replaced = true
    } else {
      out.push(e)
    }
  }
  if !replaced {
    out.push((key, v))
  }
  out
}

///|
/// `entries(δ, δ')`: the left entries extended by the right ones in order.
pub fn entries(
  base : Array[(String, Value)],
  more : Array[(String, Value)],
) -> Array[(String, Value)] {
  let mut out = base
  for e in more {
    out = update(out, e.0, e.1)
  }
  out
}
