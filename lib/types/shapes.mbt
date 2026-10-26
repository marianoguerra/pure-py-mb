///|
/// Shapes: what a `match` has not yet covered. A port of the reference's
/// `shapes.py`.
///
/// The reference keeps heads and keys in frozensets, and a shape is hashed
/// and compared structurally -- `match_shapes` keys a dict by shape, and
/// `shapes` drops a right-hand shape already on the left. So the sets here
/// are kept SORTED and duplicate-free, which makes the derived `Eq` the set
/// equality the reference relies on.

///|
/// A head: a literal, a class, or a length `n` standing for the head `list_n`.
pub(all) enum Head {
  HLit(Lit)
  HClass(String)
  HLen(Int32)
} derive(Eq, Compare, Debug)

///|
pub(all) enum Shape {
  Rest(Type, Array[Head])
  Constr(String, Array[Shape], Array[Head])
  Tuple(Array[Shape])
  List(Type, Array[Shape])
  /// The value type, the keys matched so far with their shapes (sorted by
  /// key), and the keys excluded.
  Dict(Type, Array[(String, Shape)], Array[String])
} derive(Eq, Debug)

///|
/// A set of heads, as a sorted array with no repeats.
pub fn heads_add(hs : Array[Head], h : Head) -> Array[Head] {
  if hs.contains(h) {
    return hs
  }
  let out = [..hs, h]
  out.sort()
  out
}

///|
pub fn keys_add(ks : Array[String], k : String) -> Array[String] {
  if ks.contains(k) {
    return ks
  }
  let out = [..ks, k]
  out.sort()
  out
}

///|
pub fn shape_type(k : Shape) -> Type {
  match k {
    Rest(t, _) => t
    Constr(c, _, _) => Class(c)
    Tuple(ks) => Tuple(ks.map(shape_type))
    List(t, _) => List(t)
    Dict(t, _, _) => Dict(t)
  }
}

///|
/// The shapes of the values of `tau` that no head in `hs` excludes.
pub fn shapes(sigma : ClassTable, tau : Type, hs : Array[Head]) -> Array[Shape] {
  match tau {
    Union(l, r) => {
      let left = shapes(sigma, l, typed_heads(sigma, hs, l))
      let right = shapes(sigma, r, typed_heads(sigma, hs, r))
      let out = [..left]
      for k in right {
        if !left.contains(k) {
          out.push(k)
        }
      }
      return out
    }
    Literal(v) if hs.contains(HLit(v)) => return []
    _ => ()
  }
  if tau == t_bool &&
    hs.contains(HLit(Bool(true))) &&
    hs.contains(HLit(Bool(false))) {
    return []
  }
  if tau == t_none && hs.contains(HLit(NoneLit)) {
    return []
  }
  if tau is Class(c) && below_excluded(sigma, c, hs) {
    return []
  }
  if tau == t_never {
    return []
  }
  if tau is Dict(v) {
    return [Dict(v, [], [])]
  }
  [Rest(tau, hs)]
}

///|
pub fn head_typed(sigma : ClassTable, h : Head, tau : Type) -> Bool {
  match h {
    HClass(c) => subtype(sigma, Class(c), tau)
    HLit(v) => subtype(sigma, Literal(v), tau)
    HLen(_) => tau is List(_)
  }
}

///|
pub fn typed_heads(
  sigma : ClassTable,
  hs : Array[Head],
  tau : Type,
) -> Array[Head] {
  hs.filter(fn(h) { head_typed(sigma, h, tau) })
}

///|
pub fn below_excluded(sigma : ClassTable, c : String, hs : Array[Head]) -> Bool {
  hs
  .iter()
  .any(fn(h) {
    match h {
      HClass(d) => subtype(sigma, Class(c), Class(d))
      _ => false
    }
  })
}

///|
/// Every combination of one shape per type: `itertools.product` of the
/// shapes of each, last component varying fastest.
pub fn shapes_seq(
  sigma : ClassTable,
  taus : Array[Type],
) -> Array[Array[Shape]] {
  product(taus.map(fn(t) { shapes(sigma, t, []) }))
}

///|
/// `itertools.product`: the last list varies fastest.
pub fn[T] product(lists : ArrayView[Array[T]]) -> Array[Array[T]] {
  if lists.length() == 0 {
    return [[]]
  }
  let rest = product(lists[1:])
  let out = []
  for x in lists[0] {
    for r in rest {
      out.push([x, ..r])
    }
  }
  out
}
