///|
/// Patterns against shapes and types: a port of the reference's `match.py`.
///
/// Two questions per case. REACHABILITY: a case is checked against the shapes
/// the earlier cases left uncovered, matching some of them and leaving a
/// residual for the next case, or none and being unreachable. TYPING: the
/// pattern's variables are bound at the types the remaining type gives them
/// (`check_pattern`), and the type the case leaves is `remaining`. The order
/// of every step is the reference's: which error a pattern raises first
/// depends on it.
priv struct MatchResult {
  matched : Array[@types.Shape]
  residual : Array[@types.Shape]
}

///|
fn shape_match(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  let result = match p {
    MatchAs(pattern=None, ..) => return Some({ matched: [k], residual: [], })
    MatchAs(pattern=Some(q), ..) => return shape_match(k, q, ctx)
    MatchValue(..) if literal_of(p) is Float(_) =>
      return match_literal_float(ctx.sigma(), k, literal_of(p))
    MatchValue(..) | MatchSingleton(..) => match_literal(k, literal_of(p))
    MatchSequence(kind=Tuple, ..) => match_tuple(k, p, ctx)
    MatchSequence(kind=List, ..) => match_list(k, p, ctx)
    MatchMapping(..) => match_dict(k, p, ctx)
    MatchClass(..) => match_constr(k, p, ctx)
    _ => abort("rejected by the sieve")
  }
  match result {
    Some(_) => result
    None => match_split(k, p, ctx)
  }
}

///|
fn match_split(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  match split(k, p, ctx) {
    None => None
    Some((ks, residual)) =>
      match match_shapes(ks, p, ctx) {
        None => None
        Some((matched, residual_)) =>
          Some({ matched, residual: [..residual, ..residual_], })
      }
  }
}

///|
/// A float pattern matches at a type `float` is below, and never covers a
/// shape: its head is recorded so that a repeat of it is unreachable.
fn match_literal_float(
  sigma : @types.ClassTable,
  k : @types.Shape,
  n : @types.Lit,
) -> MatchResult? {
  match k {
    Rest(tau, hs) if !hs.contains(HLit(n)) &&
      @types.subtype(sigma, @types.t_float, tau) =>
      Some({
        matched: [k],
        residual: [Rest(tau, @types.heads_add(hs, HLit(n)))],
      })
    _ => None
  }
}

///|
fn match_literal(k : @types.Shape, ell : @types.Lit) -> MatchResult? {
  match k {
    Rest(Literal(v), _) if v == ell => Some({ matched: [k], residual: [], })
    _ => None
  }
}

///|
fn match_tuple(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  guard p is MatchSequence(patterns~, ..) else { abort("a sequence pattern") }
  match k {
    Tuple(ks) if ks.length() == patterns.length() =>
      map_seq_match(fn(ks_) { Tuple(ks_) }, match_seq(ks, patterns, ctx))
    _ => None
  }
}

///|
fn match_list(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  guard p is MatchSequence(patterns~, ..) else { abort("a sequence pattern") }
  match k {
    List(tau, ks) if ks.length() == patterns.length() =>
      map_seq_match(fn(ks_) { List(tau, ks_) }, match_seq(ks, patterns, ctx))
    _ => None
  }
}

///|
fn match_dict(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  guard p is MatchMapping(patterns~, ..) else { abort("a dict pattern") }
  guard k is Dict(_, beta, _) else { return None }
  let keys = key_patterns(p).map(fn(w) { w.0 })
  let ks : Array[@types.Shape] = []
  for w in keys {
    match lookup_key(beta, w) {
      Some(s) => ks.push(s)
      None => return None
    }
  }
  map_seq_match(
    fn(ks_) { with_keys(k, keys, ks_) },
    match_seq(ks, patterns, ctx),
  )
}

///|
fn lookup_key(
  beta : Array[(String, @types.Shape)],
  w : String,
) -> @types.Shape? {
  for b in beta {
    if b.0 == w {
      return Some(b.1)
    }
  }
  None
}

///|
fn match_constr(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  let c = class_of_pattern(p, ctx)
  let ps = pattern_seq(ctx.sigma(), c, p)
  match k {
    Constr(Class(d, _) as tau, ks, hs) =>
      if @types.ancestors(ctx.sigma(), d).contains(c) {
        map_seq_match(
          fn(ks_) { Constr(tau, ks_, hs) },
          match_seq(ks, padded(ps, ks.length()), ctx),
        )
      } else {
        None
      }
    _ => None
  }
}

///|
fn split(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> (Array[@types.Shape], Array[@types.Shape])? raise {
  let sigma = ctx.sigma()
  match p {
    MatchValue(..) | MatchSingleton(..) =>
      split_literal(sigma, k, literal_of(p))
    MatchSequence(kind=Tuple, patterns~, ..) =>
      split_tuple(sigma, k, patterns.length())
    MatchSequence(kind=List, patterns~, ..) =>
      split_list(sigma, k, patterns.length())
    MatchMapping(..) => split_dict(sigma, k, key_patterns(p))
    MatchClass(..) => {
      let c = class_of_pattern(p, ctx)
      match k {
        Rest(_, _) => split_class(sigma, k, c)
        Constr(_, _, _) => split_subclass(sigma, k, c)
        _ => None
      }
    }
    _ => abort("rejected by the sieve")
  }
}

///|
fn split_literal(
  sigma : @types.ClassTable,
  k : @types.Shape,
  ell : @types.Lit,
) -> (Array[@types.Shape], Array[@types.Shape])? {
  match k {
    Rest(tau, hs) =>
      if !hs.contains(HLit(ell)) &&
        @types.subtype(sigma, Literal(ell), tau) &&
        !(tau is Literal(_)) {
        Some(
          (
            [Rest(Literal(ell), [])],
            @types.shapes(sigma, tau, @types.heads_add(hs, HLit(ell))),
          ),
        )
      } else {
        None
      }
    _ => None
  }
}

///|
fn split_tuple(
  sigma : @types.ClassTable,
  k : @types.Shape,
  n : Int32,
) -> (Array[@types.Shape], Array[@types.Shape])? {
  match k {
    Rest(Tuple(taus), _) =>
      if taus.length() != n {
        None
      } else {
        Some((@types.shapes_seq(sigma, taus).map(fn(ks) { Tuple(ks) }), []))
      }
    _ => None
  }
}

///|
fn split_list(
  sigma : @types.ClassTable,
  k : @types.Shape,
  n : Int32,
) -> (Array[@types.Shape], Array[@types.Shape])? {
  match k {
    Rest(List(tau) as ty, hs) =>
      if hs.contains(HLen(n)) {
        None
      } else {
        Some(
          (
            @types.shapes_seq(sigma, Array::make(n, tau)).map(fn(ks) {
              List(tau, ks)
            }),
            @types.shapes(sigma, ty, @types.heads_add(hs, HLen(n))),
          ),
        )
      }
    _ => None
  }
}

///|
fn split_dict(
  sigma : @types.ClassTable,
  k : @types.Shape,
  ws : Array[(String, @ast.Pattern)],
) -> (Array[@types.Shape], Array[@types.Shape])? {
  guard k is Dict(value, beta, hs) else { return None }
  let mut w : String? = None
  for p in ws {
    if lookup_key(beta, p.0) is None {
      w = Some(p.0)
      break
    }
  }
  guard w is Some(key) && !hs.contains(key) else { return None }
  Some(
    (
      @types.shapes(sigma, value, []).map(fn(m) { with_keys(k, [key], [m]) }),
      [Dict(value, beta, @types.keys_add(hs, key))],
    ),
  )
}

///|
fn field_types(
  sigma : @types.ClassTable,
  c : String,
  args : Array[@types.Type],
) -> Array[@types.Type] {
  @types.instantiate(@types.fields(sigma, c), args).map(fn(f) { f.1 })
}

///|
fn split_class(
  sigma : @types.ClassTable,
  k : @types.Shape,
  c : String,
) -> (Array[@types.Shape], Array[@types.Shape])? {
  guard k is Rest(ty, hs) else { return None }
  if @types.below_excluded(sigma, c, hs) {
    return None
  }
  guard pattern_instance(sigma, c, ty) is Some(inst) else { return None }
  let tau = @types.meet(sigma, ty, inst)
  guard tau is Class(d, args) else { abort("a class type") }
  let hs_ = @types.typed_heads(sigma, hs, tau)
  Some(
    (
      @types.shapes_seq(sigma, field_types(sigma, d, args)).map(fn(ks) {
        Constr(tau, ks, hs_)
      }),
      @types.shapes(sigma, ty, @types.heads_add(hs, HClass(c))),
    ),
  )
}

///|
fn split_subclass(
  sigma : @types.ClassTable,
  k : @types.Shape,
  c : String,
) -> (Array[@types.Shape], Array[@types.Shape])? {
  guard k is Constr(Class(kc, _) as kty, args, hs) else { return None }
  guard pattern_instance(sigma, c, kty) is Some(inst) else { return None }
  if c == kc || !@types.subtype(sigma, inst, kty) {
    return None
  }
  if @types.below_excluded(sigma, c, hs) {
    return None
  }
  guard inst is Class(_, cargs) else { abort("a class type") }
  let sigmas = field_types(sigma, c, cargs)[args.length():].to_owned()
  let hs_ = @types.typed_heads(sigma, hs, inst)
  Some(
    (
      @types.shapes_seq(sigma, sigmas).map(fn(ks) {
        Constr(inst, [..args, ..ks], hs_)
      }),
      [Constr(kty, args, @types.heads_add(hs, HClass(c)))],
    ),
  )
}

///|
/// The instance of a pattern's class at a type, which a pattern checked
/// against the scrutinee's type always determines.
fn pattern_instance(
  sigma : @types.ClassTable,
  c : String,
  tau : @types.Type,
) -> @types.Type? {
  match @types.instance(sigma, c, tau) {
    Found(d, args) => Some(Class(d, args))
    NoInstance => None
    Undetermined => abort("a pattern checks against the scrutinee's type")
  }
}

///|
fn class_of_pattern(p : @ast.Pattern, ctx : ModCtx) -> String raise {
  guard p is MatchClass(cls~, span~, ..) else { abort("a class pattern") }
  match class_of_name(cls, ctx) {
    Some(c) =>
      if c == @types.range_class {
        raise ill(RangePattern, span)
      } else {
        c
      }
    None => raise ill(NotClass(q=@analysis.qualified_name(cls)), span)
  }
}

///|
/// A class pattern's sub-patterns, one per field in field order.
fn pattern_seq(
  sigma : @types.ClassTable,
  c : String,
  p : @ast.Pattern,
) -> Array[@ast.Pattern] raise {
  guard p is MatchClass(patterns~, kwd_attrs~, kwd_patterns~, span~, ..) else {
    abort("a class pattern")
  }
  match @types.field_map(sigma, c, patterns, kwd_attrs, kwd_patterns) {
    Some(pairs) =>
      @types.field_names(sigma, c).map(fn(x) { @types.lookup(pairs, x) })
    None => {
      let name = @types.short_name(c)
      match @types.no_field_map(sigma, c, patterns.length(), kwd_attrs) {
        ArityMismatch(expected~, given~) =>
          raise ill(PatternArityMismatch(c=name, expected~, got=given), span)
        UnknownKeywordArgs(xs) =>
          raise ill(UnknownFieldInPattern(c=name, xs~), span)
      }
    }
  }
}

///|
fn match_seq(
  ks : Array[@types.Shape],
  ps : Array[@ast.Pattern],
  ctx : ModCtx,
) -> (Array[Array[@types.Shape]], Array[Array[@types.Shape]])? raise {
  let results : Array[MatchResult?] = []
  for i, k in ks {
    if i < ps.length() {
      results.push(shape_match(k, ps[i], ctx))
    }
  }
  let matches : Array[MatchResult] = []
  for r in results {
    match r {
      Some(m) => matches.push(m)
      None => return None
    }
  }
  let matched_sets = matches.map(fn(m) { m.matched })
  let matched = @types.product(matched_sets[:])
  let residual : Array[Array[@types.Shape]] = []
  for i, m in matches {
    for prefix in @types.product(matched_sets[:i]) {
      for k in m.residual {
        residual.push([..prefix, k, ..ks[i + 1:]])
      }
    }
  }
  Some((matched, residual))
}

///|
fn match_shapes(
  residual : Array[@types.Shape],
  p : @ast.Pattern,
  ctx : ModCtx,
) -> (Array[@types.Shape], Array[@types.Shape])? raise {
  // The reference keys a dict by shape: a shape that recurs is matched once,
  // in the place it first appears.
  let keys : Array[@types.Shape] = []
  let results : Array[MatchResult?] = []
  for k in residual {
    let r = shape_match(k, p, ctx)
    if !keys.contains(k) {
      keys.push(k)
      results.push(r)
    }
  }
  let matched : Array[@types.Shape] = []
  let residual_ : Array[@types.Shape] = []
  let matched_keys : Array[@types.Shape] = []
  for i, k in keys {
    match results[i] {
      Some(m) => {
        matched_keys.push(k)
        matched.append(m.matched)
        residual_.append(m.residual)
      }
      None => ()
    }
  }
  if matched_keys.is_empty() {
    return None
  }
  for k in residual {
    if !matched_keys.contains(k) {
      residual_.push(k)
    }
  }
  Some((matched, residual_))
}

// ---------------------------------------------------------------------------
// Typing patterns

///|
/// The bindings a pattern makes at a type.
fn check_pattern(
  p : @ast.Pattern,
  tau : @types.Type,
  ctx : ModCtx,
) -> Context raise {
  let sigma = ctx.sigma()
  match p {
    MatchAs(pattern=None, name=None, ..) => empty_context()
    MatchAs(pattern=None, name=Some(x), ..) => {
      check_unbound(x, p, ctx)
      context_of([(x, Var(tau))])
    }
    MatchAs(pattern=Some(q), name=Some(x), ..) => {
      check_unbound(x, p, ctx)
      let delta = check_pattern(q, tau, ctx)
      pattern_bindings([delta, context_of([(x, Var(matched_as(tau, q, ctx)))])])
    }
    MatchAs(pattern=Some(q), name=None, ..) => check_pattern(q, tau, ctx)
    MatchValue(..) | MatchSingleton(..) => empty_context()
    MatchSequence(kind=Tuple, patterns~, span~) => {
      if has_list_values(sigma, tau) {
        raise ill(
          SequenceKindMismatch(kind="tuple", tau=render(tau), other="list"),
          span,
        )
      }
      if has_range_values(sigma, tau) {
        raise ill(
          SequenceKindMismatch(kind="tuple", tau=render(tau), other="range"),
          span,
        )
      }
      bindings_at(tau, p, ctx, fn(s) raise {
        match s {
          Tuple(cs) if cs.length() == patterns.length() =>
            Some(check_pattern_seq(patterns, cs, ctx))
          _ => None
        }
      })
    }
    MatchSequence(kind=List, patterns~, span~) => {
      if has_tuple_values(sigma, tau) {
        raise ill(
          SequenceKindMismatch(kind="list", tau=render(tau), other="tuple"),
          span,
        )
      }
      if has_range_values(sigma, tau) {
        raise ill(
          SequenceKindMismatch(kind="list", tau=render(tau), other="range"),
          span,
        )
      }
      bindings_at(tau, p, ctx, fn(s) raise {
        match s {
          List(e) =>
            Some(
              check_pattern_seq(
                patterns,
                Array::make(patterns.length(), e),
                ctx,
              ),
            )
          _ => None
        }
      })
    }
    MatchMapping(patterns~, ..) =>
      bindings_at(tau, p, ctx, fn(s) raise {
        match s {
          Dict(v) =>
            Some(
              check_pattern_seq(
                patterns,
                Array::make(patterns.length(), v),
                ctx,
              ),
            )
          _ => None
        }
      })
    MatchClass(span~, ..) => {
      let c = class_of_pattern(p, ctx)
      // Checked before the instance: the rules would report a pattern with no
      // instance as unreachable.
      let qs = pattern_seq(sigma, c, p)
      bindings_at(tau, p, ctx, fn(s) raise {
        match @types.instance(sigma, c, s) {
          Undetermined =>
            raise ill(
              PatternClassUndetermined(c=@types.short_name(c), tau=render(s)),
              span,
            )
          NoInstance => None
          Found(_, args) =>
            Some(check_pattern_seq(qs, field_types(sigma, c, args), ctx))
        }
      })
    }
    _ => abort("rejected by the sieve")
  }
}

///|
fn check_unbound(x : String, p : @ast.Pattern, ctx : ModCtx) -> Unit raise {
  if !(ctx.gamma.get(x) is Some(Unbound)) {
    raise ill(Redeclaration(x~), p.span())
  }
}

///|
fn check_pattern_seq(
  ps : Array[@ast.Pattern],
  taus : Array[@types.Type],
  ctx : ModCtx,
) -> Context raise {
  let deltas = []
  for i, q in ps {
    if i < taus.length() {
      deltas.push(check_pattern(q, taus[i], ctx))
    }
  }
  pattern_bindings(deltas)
}

///|
/// Bindings joined over the disjuncts of a type: a disjunct the pattern can't
/// match binds every variable at `Never`.
fn bindings_at(
  tau : @types.Type,
  p : @ast.Pattern,
  ctx : ModCtx,
  at_disjunct : (@types.Type) -> Context? raise,
) -> Context raise {
  let never = context_of(
    @analysis.binds(p).to_array().map(fn(x) { (x, Var(@types.t_never)) }),
  )
  let deltas = []
  for s in @types.disjuncts(tau) {
    deltas.push(
      match at_disjunct(s) {
        Some(d) => d
        None => never
      },
    )
  }
  join_context(ctx.sigma(), deltas)
}

///|
/// The type of the values of `tau` a pattern matches.
fn matched_as(
  tau : @types.Type,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> @types.Type raise {
  let sigma = ctx.sigma()
  match (tau, p) {
    (Union(s, t), _) =>
      @types.join(sigma, matched_as(s, p, ctx), matched_as(t, p, ctx))
    (_, MatchAs(pattern=None, ..)) => tau
    (_, MatchAs(pattern=Some(q), ..)) => matched_as(tau, q, ctx)
    (_, MatchValue(..)) if literal_of(p) is Float(_) =>
      @types.meet(sigma, @types.t_float, tau)
    (_, MatchValue(..) | MatchSingleton(..)) =>
      @types.meet(sigma, Literal(literal_of(p)), tau)
    (Tuple(taus), MatchSequence(kind=Tuple, patterns~, ..)) if taus.length() ==
      patterns.length() =>
      Tuple(taus.mapi(fn(i, s) raise { matched_as(s, patterns[i], ctx) }))
    (List(_), MatchSequence(kind=List, ..)) => tau
    (Dict(_), MatchMapping(..)) => tau
    (_, MatchClass(..)) =>
      match pattern_instance(sigma, class_of_pattern(p, ctx), tau) {
        None => @types.t_never
        Some(inst) => @types.meet(sigma, tau, inst)
      }
    _ => @types.t_never
  }
}

///|
/// The type of the values of `tau` a pattern does not match, as far as a type
/// can say.
fn remaining(
  tau : @types.Type,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> @types.Type raise {
  let sigma = ctx.sigma()
  match (tau, p) {
    (Union(s, t), _) =>
      @types.join(sigma, remaining(s, p, ctx), remaining(t, p, ctx))
    (_, MatchAs(pattern=None, ..)) => @types.t_never
    (_, MatchAs(pattern=Some(q), ..)) => remaining(tau, q, ctx)
    (_, MatchValue(..) | MatchSingleton(..)) => {
      let ell = literal_of(p)
      if tau == Literal(ell) || (tau == @types.t_none && ell == NoneLit) {
        return @types.t_never
      }
      match (tau, ell) {
        (Prim(Bool), Bool(b)) => Literal(Bool(!b))
        _ => tau
      }
    }
    (Tuple(taus), MatchSequence(kind=Tuple, patterns~, ..)) if taus.length() ==
      patterns.length() => {
      let rests = taus.mapi(fn(i, s) raise { remaining(s, patterns[i], ctx) })
      let open : Array[Int32] = []
      for i, r in rests {
        if r != @types.t_never {
          open.push(i)
        }
      }
      match open {
        [] => @types.t_never
        [i] => Tuple(taus.mapi(fn(j, t) { if j == i { rests[i] } else { t } }))
        _ => tau
      }
    }
    (Dict(_), MatchMapping(keys=[], ..)) => @types.t_never
    (_, MatchClass(..)) => {
      let c = class_of_pattern(p, ctx)
      guard pattern_instance(sigma, c, tau) is Some(Class(_, args) as inst) &&
        @types.subtype(sigma, tau, inst) else {
        return tau
      }
      let qs = pattern_seq(sigma, c, p)
      let sigmas = field_types(sigma, c, args)
      for i, q in qs {
        if i < sigmas.length() && remaining(sigmas[i], q, ctx) != @types.t_never {
          return tau
        }
      }
      @types.t_never
    }
    _ => tau
  }
}

///|
/// A disjunct other than a list type is above every list type or none, so
/// `list[object]` stands for all of them.
fn has_list_values(sigma : @types.ClassTable, tau : @types.Type) -> Bool {
  @types.disjuncts(tau)
  .iter()
  .any(fn(s) {
    s is (List(_) | TypeVar(_)) ||
    @types.subtype(sigma, List(@types.t_object), s)
  })
}

///|
/// A disjunct other than a tuple type is above every tuple type or none, so
/// `tuple[()]` stands for all of them.
fn has_tuple_values(sigma : @types.ClassTable, tau : @types.Type) -> Bool {
  @types.disjuncts(tau)
  .iter()
  .any(fn(s) {
    s is (Tuple(_) | TypeVar(_)) || @types.subtype(sigma, Tuple([]), s)
  })
}

///|
/// Whether a type has `range` values, which neither sequence pattern
/// matches.
fn has_range_values(sigma : @types.ClassTable, tau : @types.Type) -> Bool {
  @types.disjuncts(tau)
  .iter()
  .any(fn(s) {
    s is TypeVar(_) || @types.subtype(sigma, Class(@types.range_class, []), s)
  })
}

///|
/// The union of several patterns' bindings, which the parser has made
/// disjoint.
fn pattern_bindings(deltas : Array[Context]) -> Context {
  let mut merged = empty_context()
  for d in deltas {
    merged = override_context(merged, d)
  }
  merged
}

///|
fn map_seq_match(
  form : (Array[@types.Shape]) -> @types.Shape,
  result : (Array[Array[@types.Shape]], Array[Array[@types.Shape]])?,
) -> MatchResult? {
  match result {
    None => None
    Some((matched, residual)) =>
      Some({ matched: matched.map(form), residual: residual.map(form), })
  }
}

///|
fn padded(ps : Array[@ast.Pattern], n : Int32) -> Array[@ast.Pattern] {
  let out = [..ps]
  while out.length() < n {
    out.push(MatchAs(pattern=None, name=None, span=@basic.nowhere))
  }
  out
}

///|
/// A dict shape with some keys' shapes set, kept sorted by key so that two
/// equal shapes compare equal.
fn with_keys(
  k : @types.Shape,
  ws : Array[String],
  ks : Array[@types.Shape],
) -> @types.Shape {
  guard k is Dict(value, beta, hs) else { abort("a dict shape") }
  let out = beta.filter(fn(b) { !ws.contains(b.0) })
  for i, w in ws {
    out.push((w, ks[i]))
  }
  out.sort_by(fn(a, b) { @basic.lexical_compare(a.0, b.0) })
  Dict(value, out, hs)
}

///|
fn key_patterns(p : @ast.Pattern) -> Array[(String, @ast.Pattern)] {
  guard p is MatchMapping(keys~, patterns~, ..) else { abort("a dict pattern") }
  keys.mapi(fn(i, k) {
    match k {
      Constant(value=Str(s), ..) => (s, patterns[i])
      _ => abort("rejected by the sieve")
    }
  })
}

///|
fn literal_of(p : @ast.Pattern) -> @types.Lit {
  let lit = match p {
    MatchSingleton(value~, ..) => @types.lit_of_constant(value)
    MatchValue(value~, ..) => @types.literal_type(value)
    _ => None
  }
  match lit {
    Some(v) => v
    None => abort("rejected by the sieve")
  }
}
