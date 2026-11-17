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
      // The mechanisation's `instance_below` (spec v0.25): match the
      // ancestor's arguments one way against the type's, read the class's
      // arguments off the match, and take them only if they reproduce the
      // type exactly. A union in the ancestor's arguments binds nothing, so
      // `Leaf[T](Tree[T | int])` below `Tree[float]` is undetermined.
      match match_args_seq(rhos, sigmas) {
        ArgIncomparable => NoInstance
        ArgUndefined => Undetermined
        Matched(gamma) => {
          let taus = []
          for a in alphas {
            match gamma.get(a) {
              Some(t) => taus.push(t)
              None => return Undetermined
            }
          }
          let (_, back) = instantiated_ancestor(sigma, Class(c, taus), d)
          if back.length() == sigmas.length() &&
            all_pairs(back, sigmas, fn(r, s) { equivalent(sigma, r, s) }) {
            Found(c, taus)
          } else {
            Undetermined
          }
        }
      }
    }
    Prim(Object) => if alphas.is_empty() { Found(c, []) } else { Undetermined }
    _ => NoInstance
  }
}

///|
/// One-way matching of a type over a class's type parameters against a
/// type: the mechanisation's `arg_match`. `ArgUndefined` where the type has a
/// variable or a union the pattern side does not, `ArgIncomparable` where two
/// types with structure differ.
priv enum ArgMatch {
  Matched(Map[String, Type])
  ArgUndefined
  ArgIncomparable
}

///|
fn merge_match(a : ArgMatch, b : ArgMatch) -> ArgMatch {
  match (a, b) {
    (ArgIncomparable, _) | (_, ArgIncomparable) => ArgIncomparable
    (ArgUndefined, _) | (_, ArgUndefined) => ArgUndefined
    (Matched(g), Matched(h)) => {
      let out = Map([])
      for k, v in g {
        out[k] = v
      }
      for k, v in h {
        out[k] = v
      }
      Matched(out)
    }
  }
}

///|
fn match_args(rho : Type, s : Type) -> ArgMatch {
  match (rho, s) {
    (TypeVar(a), _) => Matched(Map::from_array([(a, s)]))
    (Union(_, _), _) => Matched(Map([]))
    (_, TypeVar(_)) | (_, Union(_, _)) => ArgUndefined
    (List(r), List(t)) | (Dict(r), Dict(t)) => match_args(r, t)
    (Tuple(rs), Tuple(ts)) => match_args_seq(rs, ts)
    (Callable(rs, r), Callable(ts, t)) => match_args_seq([r, ..rs], [t, ..ts])
    (Class(c, rs), Class(d, ts)) =>
      if c == d {
        match_args_seq(rs, ts)
      } else {
        ArgIncomparable
      }
    _ => if rho == s { Matched(Map([])) } else { ArgIncomparable }
  }
}

///|
fn match_args_seq(rhos : Array[Type], ss : Array[Type]) -> ArgMatch {
  if rhos.length() != ss.length() {
    return ArgIncomparable
  }
  let mut acc = Matched(Map([]))
  for i, r in rhos {
    acc = merge_match(acc, match_args(r, ss[i]))
  }
  acc
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
/// The type arguments for `alphas` a generic `s` takes when a value of type
/// `t` is given for it: a map from type parameter to type. A type variable
/// not among `alphas` is a type, not a parameter to solve for.
pub fn type_args(
  sigma : ClassTable,
  alphas : Array[String],
  s : Type,
  t : Type,
) -> Array[(String, Type)] {
  match (s, t) {
    (TypeVar(a), _) if alphas.contains(a) => [(a, base_type(t))]
    (_, Union(t1, t2)) =>
      join_args(
        sigma,
        type_args(sigma, alphas, s, t1),
        type_args(sigma, alphas, s, t2),
      )
    (List(s1), List(t1)) | (Dict(s1), Dict(t1)) =>
      type_args(sigma, alphas, s1, t1)
    (Tuple(ss), Tuple(ts)) => type_args_seq(sigma, alphas, ss, ts)
    (Callable(ss, s1), Callable(ts, t1)) =>
      type_args_seq(sigma, alphas, [s1, ..ss], [t1, ..ts])
    (Class(c, ss), _) =>
      match instance(sigma, c, t) {
        Found(_, ts) => type_args_seq(sigma, alphas, ss, ts)
        _ => []
      }
    (Union(s1, s2), _) =>
      if [s1, s2]
        .iter()
        .any(fn(d) {
          !fv(d).iter().any(fn(a) { alphas.contains(a) }) &&
          subtype(sigma, t, d)
        }) {
        []
      } else {
        join_args(
          sigma,
          type_args(sigma, alphas, s1, t),
          type_args(sigma, alphas, s2, t),
        )
      }
    _ => []
  }
}

///|
pub fn type_args_seq(
  sigma : ClassTable,
  alphas : Array[String],
  ss : Array[Type],
  ts : Array[Type],
) -> Array[(String, Type)] {
  let mut result : Array[(String, Type)] = []
  for
    i in 0..<(if ss.length() < ts.length() { ss.length() } else { ts.length() }) {
    result = join_args(sigma, result, type_args(sigma, alphas, ss[i], ts[i]))
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
