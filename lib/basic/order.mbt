///|
/// Python's ordering of strings, which is not MoonBit's.
///
/// Python compares strings by CODE POINT, so `"ab" < "b"`. MoonBit's default
/// `String::compare` compares by length first, so `"b" < "ab"`. The difference
/// is visible wherever the reference reaches for `min` or `sorted` to decide
/// which of several names a message reports -- the captured-then-reassigned
/// name, the clashing inherited field, the shadowed submodule, the list of
/// constructor keywords -- so every such place goes through here.
pub fn lexical_compare(a : String, b : String) -> Int {
  let xs = a.to_array()
  let ys = b.to_array()
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i in 0..<n {
    let x = xs[i].to_int()
    let y = ys[i].to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if xs.length() == ys.length() {
    0
  } else if xs.length() < ys.length() {
    -1
  } else {
    1
  }
}

///|
/// Sort in place, the way Python's `sorted` would.
pub fn sort_names(names : Array[String]) -> Unit {
  names.sort_by(fn(a, b) { lexical_compare(a, b) })
}

///|
/// Python's `min` of a collection of names: the one a message reports when
/// several qualify. `None` for an empty collection, which no caller passes.
pub fn min_name(names : Array[String]) -> String? {
  if names.is_empty() {
    return None
  }
  let mut best = names[0]
  for n in names {
    if lexical_compare(n, best) < 0 {
      best = n
    }
  }
  Some(best)
}
