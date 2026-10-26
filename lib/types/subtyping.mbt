///|
/// Subtyping, joins and meets: a port of the reference's `subtyping.py`.

///|
pub fn join(sigma : ClassTable, s : Type, t : Type) -> Type {
  if subtype(sigma, s, t) {
    t
  } else if subtype(sigma, t, s) {
    s
  } else {
    Union(s, t)
  }
}

///|
pub fn meet(sigma : ClassTable, s : Type, t : Type) -> Type {
  if subtype(sigma, s, t) {
    return s
  }
  if subtype(sigma, t, s) {
    return t
  }
  match (s, t) {
    (Union(l, r), _) => join(sigma, meet(sigma, l, t), meet(sigma, r, t))
    (_, Union(l, r)) => join(sigma, meet(sigma, s, l), meet(sigma, s, r))
    (Tuple(ss), Tuple(ts)) =>
      if ss.length() == ts.length() {
        Tuple(ss.mapi(fn(i, a) { meet(sigma, a, ts[i]) }))
      } else {
        t_never
      }
    (Callable(ss, s_), Callable(ts, t_)) =>
      if ss.length() == ts.length() {
        Callable(
          ss.mapi(fn(i, a) { join(sigma, a, ts[i]) }),
          meet(sigma, s_, t_),
        )
      } else {
        t_never
      }
    _ => t_never
  }
}

///|
/// The join of a sequence, folded from the right as the reference does:
/// `join(t0, join(t1, ... join(tn, Never)))`.
pub fn join_seq(sigma : ClassTable, ts : ArrayView[Type]) -> Type {
  if ts.length() == 0 {
    return t_never
  }
  join(sigma, ts[0], join_seq(sigma, ts[1:]))
}

///|
pub fn subtype(sigma : ClassTable, s : Type, t : Type) -> Bool {
  if s == t || s == t_never || t == t_object {
    return true
  }
  if s == t_int && t == t_float {
    return true
  }
  match (s, t) {
    (Union(l, r), _) => subtype(sigma, l, t) && subtype(sigma, r, t)
    (_, Union(l, r)) => subtype(sigma, s, l) || subtype(sigma, s, r)
    (Literal(v), _) => subtype(sigma, lit_base(v), t)
    (Class(c), Class(d)) => ancestors(sigma, c).contains(d)
    (Tuple(ss), Tuple(ts)) =>
      ss.length() == ts.length() &&
      all_pairs(ss, ts, fn(a, b) { subtype(sigma, a, b) })
    (List(a), List(b)) => equivalent(sigma, a, b)
    (Dict(a), Dict(b)) => equivalent(sigma, a, b)
    (Callable(ss, s_), Callable(ts, t_)) =>
      ss.length() == ts.length() &&
      all_pairs(ss, ts, fn(a, b) { subtype(sigma, b, a) }) &&
      subtype(sigma, s_, t_)
    // A function with defaults is every arity it can be called at.
    (Defaulted(ss, n, s_), Callable(ts, t_)) =>
      ts.length() >= ss.length() - n &&
      ts.length() <= ss.length() &&
      all_pairs(ss, ts, fn(a, b) { subtype(sigma, b, a) }) &&
      subtype(sigma, s_, t_)
    (Defaulted(ss, n, s_), Defaulted(ts, m, t_)) =>
      ss.length() == ts.length() &&
      n >= m &&
      all_pairs(ss, ts, fn(a, b) { subtype(sigma, b, a) }) &&
      subtype(sigma, s_, t_)
    _ =>
      if t == t_sized {
        s is (List(_) | Dict(_) | Tuple(_)) || s == t_str
      } else {
        false
      }
  }
}

///|
pub fn equivalent(sigma : ClassTable, s : Type, t : Type) -> Bool {
  subtype(sigma, s, t) && subtype(sigma, t, s)
}

///|
pub fn comparable(sigma : ClassTable, s : Type, t : Type) -> Bool {
  subtype(sigma, s, t) || subtype(sigma, t, s)
}

///|
/// Whether `f` holds of every pair `zip(xs, ys)` makes: Python's `zip`, which
/// stops at the shorter.
pub fn[A, B] all_pairs(
  xs : Array[A],
  ys : Array[B],
  f : (A, B) -> Bool,
) -> Bool {
  for
    i in 0..<(if xs.length() < ys.length() { xs.length() } else { ys.length() }) {
    if !f(xs[i], ys[i]) {
      return false
    }
  }
  true
}
