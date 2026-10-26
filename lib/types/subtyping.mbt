///|
/// Subtyping, joins and meets, and the instances of a generic class: a port of
/// the reference's `subtyping.py`.

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
    (Class(c, taus), Class(d, sigmas)) => {
      if c == d && all_pairs(taus, sigmas, fn(a, b) { equivalent(sigma, a, b) }) {
        return true
      }
      match base_of(sigma, c) {
        Some((b, args)) =>
          subtype(
            sigma,
            substitute(taus[:], type_params_of(sigma, c)[:], Class(b, args)),
            t,
          )
        None => false
      }
    }
    (Tuple(ss), Tuple(ts)) =>
      ss.length() == ts.length() &&
      all_pairs(ss, ts, fn(a, b) { subtype(sigma, a, b) })
    (List(a), List(b)) | (Dict(a), Dict(b)) => equivalent(sigma, a, b)
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
        s is (List(_) | Dict(_) | Tuple(_)) ||
        s == t_str ||
        s == Class(range_class, [])
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

// ---------------------------------------------------------------------------
// Instances of a generic class

///|
/// The instance of a class a type determines: at a class type above it or
/// below it, the class at the arguments that make the two agree.
pub(all) enum Instance {
  Found(String, Array[Type])
  Undetermined
  NoInstance
}

///|
pub fn instance(sigma : ClassTable, c : String, tau : Type) -> Instance {
  match instance_above(sigma, c, tau) {
    NoInstance => instance_below(sigma, c, tau)
    above => above
  }
}

///|
pub fn instance_above(sigma : ClassTable, c : String, tau : Type) -> Instance {
  match tau {
    Class(d, _) if ancestors(sigma, d).contains(c) => {
      let (q, args) = instantiated_ancestor(sigma, tau, c)
      Found(q, args)
    }
    Prim(Never) =>
      if type_params_of(sigma, c).is_empty() {
        Found(c, [])
      } else {
        Undetermined
      }
    _ => NoInstance
  }
}

///|
pub fn instance_below(sigma : ClassTable, c : String, tau : Type) -> Instance {
  let alphas = type_params_of(sigma, c)
  match tau {
    Union(_, _) => abort("instances are taken at the disjuncts of a union")
    Class(d, sigmas) if ancestors(sigma, c).contains(d) => {
      let generic = Class(c, alphas.map(fn(a) { TypeVar(a) }))
      let (_, rhos) = instantiated_ancestor(sigma, generic, d)
      match instantiation_candidates(sigma, rhos, sigmas, alphas) {
        [] => NoInstance
        [taus] => Found(c, taus)
        _ => Undetermined
      }
    }
    Prim(Object) => if alphas.is_empty() { Found(c, []) } else { Undetermined }
    _ => NoInstance
  }
}

///|
/// The instantiation of ancestor `d` of a class type, reached along the base
/// classes.
pub fn instantiated_ancestor(
  sigma : ClassTable,
  tau : Type,
  d : String,
) -> (String, Array[Type]) {
  guard tau is Class(c0, args0) else { abort("a class type") }
  let mut c = c0
  let mut args = args0
  while c != d {
    guard base_of(sigma, c) is Some((b, bargs)) else {
      abort("d is an ancestor")
    }
    match substitute(args[:], type_params_of(sigma, c)[:], Class(b, bargs)) {
      Class(b_, args_) => {
        c = b_
        args = args_
      }
      _ => abort("a class type")
    }
  }
  (c, args)
}

///|
/// The argument sequences for `alphas` that make `rhos` equivalent to
/// `sigmas`: none, one, or two that differ -- which is enough to say there
/// is no single one.
fn instantiation_candidates(
  sigma : ClassTable,
  rhos : Array[Type],
  sigmas : Array[Type],
  alphas : Array[String],
) -> Array[Array[Type]] {
  let atoms : Array[Type] = [t_object]
  for s in sigmas {
    for a in subterms(s) {
      if !atoms.contains(a) {
        atoms.push(a)
      }
    }
  }
  atoms.sort_by(fn(a, b) { @basic.lexical_compare(render(a), render(b)) })
  let choices = product(Array::make(alphas.length(), subsets(atoms))[:])
  let mut first : Array[Type]? = None
  for choice in choices {
    let taus = choice.map(fn(ts) { join_seq(sigma, ts[:]) })
    let solves = all_pairs(rhos, sigmas, fn(rho, s) {
      equivalent(sigma, substitute(taus[:], alphas[:], rho), s)
    })
    if !solves {
      continue
    }
    match first {
      None => first = Some(taus)
      Some(f) =>
        if !all_pairs(taus, f, fn(a, b) { equivalent(sigma, a, b) }) {
          return [f, taus]
        }
    }
  }
  match first {
    None => []
    Some(f) => [f]
  }
}

///|
/// Every sub-sequence of `xs`, in the order `itertools.product((False,
/// True), repeat=n)` enumerates them.
fn[T] subsets(xs : Array[T]) -> Array[Array[T]] {
  let keeps = product(Array::make(xs.length(), [false, true])[:])
  keeps.map(fn(k) {
    let out = []
    for i, x in xs {
      if k[i] {
        out.push(x)
      }
    }
    out
  })
}

///|
/// The types of a type's parts, the type among them.
fn subterms(tau : Type) -> Array[Type] {
  let out : Array[Type] = []
  fn add(t : Type) {
    if !out.contains(t) {
      out.push(t)
    }
  }

  fn go(t : Type) -> Unit {
    match t {
      Union(a, b) => {
        go(a)
        go(b)
      }
      List(s) | Dict(s) => {
        add(t)
        go(s)
      }
      Tuple(ss) | Class(_, ss) => {
        add(t)
        for s in ss {
          go(s)
        }
      }
      Callable(ps, r) => {
        add(t)
        go(r)
        for p in ps {
          go(p)
        }
      }
      _ => add(t)
    }
  }

  go(tau)
  out
}

///|
/// The type arguments a generic `s` takes when a value of type `t` is given
/// for it: a map from type parameter to type.
pub fn type_args(
  sigma : ClassTable,
  s : Type,
  t : Type,
) -> Array[(String, Type)] {
  match (s, t) {
    (TypeVar(a), _) => [(a, base_type(t))]
    (_, Union(t1, t2)) =>
      join_args(sigma, type_args(sigma, s, t1), type_args(sigma, s, t2))
    (List(s1), List(t1)) | (Dict(s1), Dict(t1)) => type_args(sigma, s1, t1)
    (Tuple(ss), Tuple(ts)) => type_args_seq(sigma, ss, ts)
    (Callable(ss, s1), Callable(ts, t1)) =>
      type_args_seq(sigma, [s1, ..ss], [t1, ..ts])
    (Class(c, ss), _) =>
      match instance(sigma, c, t) {
        Found(_, ts) => type_args_seq(sigma, ss, ts)
        _ => []
      }
    (Union(s1, s2), _) =>
      if subtype(sigma, t, s1) || subtype(sigma, t, s2) {
        []
      } else {
        join_args(sigma, type_args(sigma, s1, t), type_args(sigma, s2, t))
      }
    _ => []
  }
}

///|
pub fn type_args_seq(
  sigma : ClassTable,
  ss : Array[Type],
  ts : Array[Type],
) -> Array[(String, Type)] {
  let mut result : Array[(String, Type)] = []
  for
    i in 0..<(if ss.length() < ts.length() { ss.length() } else { ts.length() }) {
    result = join_args(sigma, result, type_args(sigma, ss[i], ts[i]))
  }
  result
}

///|
/// Two maps from type parameter to type, joined where both have one.
fn join_args(
  sigma : ClassTable,
  g : Array[(String, Type)],
  h : Array[(String, Type)],
) -> Array[(String, Type)] {
  let out : Array[(String, Type)] = []
  for p in g {
    match h.search_by(fn(q) { q.0 == p.0 }) {
      Some(i) => out.push((p.0, join(sigma, p.1, h[i].1)))
      None => out.push(p)
    }
  }
  for q in h {
    if !g.iter().any(fn(p) { p.0 == q.0 }) {
      out.push(q)
    }
  }
  out
}

///|
/// The parts of a union, left to right.
pub fn disjuncts(tau : Type) -> Array[Type] {
  match tau {
    Union(a, b) => [..disjuncts(a), ..disjuncts(b)]
    _ => [tau]
  }
}
