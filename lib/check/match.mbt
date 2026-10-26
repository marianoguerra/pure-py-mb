///|
/// Patterns against shapes: a port of the reference's `match.py`.
///
/// A case is checked against the shapes the earlier cases left uncovered: it
/// MATCHES some of them, leaving a residual for the next case, or none, and
/// is unreachable. A shape a pattern only partly covers is SPLIT into the part
/// it covers and the rest. The order of every step is the reference's: which
/// error a pattern raises first depends on it.
priv struct MatchResult {
  matched : Array[@types.Shape]
  residual : Array[@types.Shape]
  delta : Context
}

///|
fn shape_match(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  let result = match p {
    MatchAs(..) => return match_as(k, p, ctx)
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
fn match_as(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  guard p is MatchAs(pattern~, name~, span~) else { abort("an as-pattern") }
  // A pattern variable is bound once in its scope, where it starts unbound.
  match name {
    Some(x) if !(ctx.gamma.get(x) is Some(Unbound)) =>
      raise ill(Redeclaration(x~), span)
    _ => ()
  }
  match pattern {
    None => {
      let delta = match name {
        None => empty_context()
        Some(x) => context_of([(x, Var(@types.shape_type(k)))])
      }
      Some({ matched: [k], residual: [], delta, })
    }
    Some(inner) =>
      match shape_match(k, inner, ctx) {
        None => None
        Some(r) =>
          match name {
            None => Some(r)
            Some(x) => {
              let tau = @types.join_seq(
                ctx.sigma(),
                r.matched.map(@types.shape_type),
              )
              Some({
                ..r,
                delta: pattern_bindings(
                  [r.delta, context_of([(x, Var(tau))])],
                  p,
                ),
              })
            }
          }
      }
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
        Some((matched, residual_, delta)) =>
          Some({ matched, residual: [..residual, ..residual_], delta, })
      }
  }
}

///|
fn match_literal(k : @types.Shape, ell : @types.Lit) -> MatchResult? {
  match k {
    Rest(Literal(v), _) if v == ell =>
      Some({ matched: [k], residual: [], delta: empty_context(), })
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
      map_seq_match(fn(ks_) { Tuple(ks_) }, match_seq(ks, patterns, p, ctx))
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
      map_seq_match(fn(ks_) { List(tau, ks_) }, match_seq(ks, patterns, p, ctx))
    _ => None
  }
}

///|
fn match_dict(
  k : @types.Shape,
  p : @ast.Pattern,
  ctx : ModCtx,
) -> MatchResult? raise {
  guard p is MatchMapping(patterns~, span~, ..) else { abort("a dict pattern") }
  guard k is Dict(_, beta, _) else { return None }
  let keys = key_patterns(p).map(fn(w) { w.0 })
  for i, w in keys {
    if keys[:i].contains(w) {
      raise ill(DuplicateDictKey(w~), span)
    }
  }
  let ks : Array[@types.Shape] = []
  for w in keys {
    match lookup_key(beta, w) {
      Some(s) => ks.push(s)
      None => return None
    }
  }
  map_seq_match(
    fn(ks_) { with_keys(k, keys, ks_) },
    match_seq(ks, patterns, p, ctx),
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
    Constr(d, ks, hs) =>
      if @types.subtype(ctx.sigma(), Class(d), Class(c)) {
        map_seq_match(
          fn(ks_) { Constr(d, ks_, hs) },
          match_seq(ks, padded(ps, ks.length()), p, ctx),
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
fn declared_types(
  sigma : @types.ClassTable,
  c : String,
  xs : ArrayView[String],
) -> Array[@types.Type] {
  xs.to_owned().map(fn(x) { @types.declared_type(sigma, c, x) })
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
  let tau = @types.meet(sigma, ty, Class(c))
  match tau {
    Class(d) => {
      let sigmas = declared_types(sigma, d, @types.fields(sigma, d)[:])
      let hs_ = @types.typed_heads(sigma, hs, tau)
      Some(
        (
          @types.shapes_seq(sigma, sigmas).map(fn(ks) { Constr(d, ks, hs_) }),
          @types.shapes(sigma, ty, @types.heads_add(hs, HClass(c))),
        ),
      )
    }
    _ => None
  }
}

///|
fn split_subclass(
  sigma : @types.ClassTable,
  k : @types.Shape,
  c : String,
) -> (Array[@types.Shape], Array[@types.Shape])? {
  guard k is Constr(kc, args, hs) else { return None }
  if c == kc || !@types.subtype(sigma, Class(c), Class(kc)) {
    return None
  }
  if @types.below_excluded(sigma, c, hs) {
    return None
  }
  let sigmas = declared_types(sigma, c, @types.fields(sigma, c)[args.length():])
  let hs_ = @types.typed_heads(sigma, hs, Class(c))
  Some(
    (
      @types.shapes_seq(sigma, sigmas).map(fn(ks) {
        Constr(c, [..args, ..ks], hs_)
      }),
      [Constr(kc, args, @types.heads_add(hs, HClass(c)))],
    ),
  )
}

///|
fn class_of_pattern(p : @ast.Pattern, ctx : ModCtx) -> String raise {
  guard p is MatchClass(cls~, span~, ..) else { abort("a class pattern") }
  match class_of_name(cls, ctx) {
    Some(c) => c
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
      @types.fields(sigma, c).map(fn(x) { @types.lookup(pairs, x) })
    None => {
      let name = @types.short_name(c)
      let xs = @types.fields(sigma, c)
      let n = patterns.length()
      if n + kwd_attrs.length() != xs.length() {
        raise ill(
          PatternArityMismatch(
            c=name,
            expected=xs.length(),
            got=n + kwd_attrs.length(),
          ),
          span,
        )
      }
      for i, a in kwd_attrs {
        if kwd_attrs[:i].contains(a) {
          raise ill(DuplicatePatternKeyword(c=name), span)
        }
      }
      let rest : Array[String] = []
      for x in xs[n:] {
        if !rest.contains(x) {
          rest.push(x)
        }
      }
      @basic.sort_names(rest)
      raise ill(UnknownFieldInPattern(c=name, xs=rest), span)
    }
  }
}

///|
fn match_seq(
  ks : Array[@types.Shape],
  ps : Array[@ast.Pattern],
  node : @ast.Pattern,
  ctx : ModCtx,
) -> (Array[Array[@types.Shape]], Array[Array[@types.Shape]], Context)? raise {
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
  Some(
    (matched, residual, pattern_bindings(matches.map(fn(m) { m.delta }), node)),
  )
}

///|
fn match_shapes(
  residual : Array[@types.Shape],
  p : @ast.Pattern,
  ctx : ModCtx,
) -> (Array[@types.Shape], Array[@types.Shape], Context)? raise {
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
  let deltas : Array[Context] = []
  let matched_keys : Array[@types.Shape] = []
  for i, k in keys {
    match results[i] {
      Some(m) => {
        matched_keys.push(k)
        for s in m.matched {
          matched.push(s)
        }
        for s in m.residual {
          residual_.push(s)
        }
        deltas.push(m.delta)
      }
      None => ()
    }
  }
  if deltas.is_empty() {
    return None
  }
  for k in residual {
    if !matched_keys.contains(k) {
      residual_.push(k)
    }
  }
  Some((matched, residual_, join_context(ctx.sigma(), deltas)))
}

///|
/// A list pattern against a tuple type, or the other way round, is refused
/// rather than left to never match: it is the one sequence confusion Python
/// accepts silently.
fn sequence_kind_mismatch(
  p : @ast.Pattern,
  tau : @types.Type,
  ctx : ModCtx,
) -> (@ast.Pattern, @types.Type)? {
  if tau is Union(s, s_) {
    return match first_mismatch([(p, s), (p, s_)], ctx) {
      None => None
      Some((q, sigma)) => if q == p { Some((q, tau)) } else { Some((q, sigma)) }
    }
  }
  match p {
    MatchSequence(kind=Tuple, patterns~, ..) =>
      if tau is List(_) || tau == @types.t_sized || tau == @types.t_object {
        Some((p, tau))
      } else {
        match tau {
          Tuple(ts) if ts.length() == patterns.length() =>
            first_mismatch(patterns.mapi(fn(i, q) { (q, ts[i]) }), ctx)
          _ => None
        }
      }
    MatchSequence(kind=List, patterns~, ..) =>
      if tau is Tuple(_) || tau == @types.t_sized || tau == @types.t_object {
        Some((p, tau))
      } else {
        match tau {
          List(e) => first_mismatch(patterns.map(fn(q) { (q, e) }), ctx)
          _ => None
        }
      }
    MatchMapping(patterns~, ..) =>
      match tau {
        Dict(v) => first_mismatch(patterns.map(fn(q) { (q, v) }), ctx)
        _ => None
      }
    MatchClass(cls~, patterns~, kwd_attrs~, kwd_patterns~, ..) => {
      guard class_of_name(cls, ctx) is Some(c) else { return None }
      let sigma = ctx.sigma()
      guard @types.field_map(sigma, c, patterns, kwd_attrs, kwd_patterns)
        is Some(pairs) else {
        return None
      }
      first_mismatch(
        @types.fields(sigma, c).map(fn(x) {
          (@types.lookup(pairs, x), @types.declared_type(sigma, c, x))
        }),
        ctx,
      )
    }
    MatchAs(pattern=Some(q), ..) => sequence_kind_mismatch(q, tau, ctx)
    _ => None
  }
}

///|
fn first_mismatch(
  pairs : Array[(@ast.Pattern, @types.Type)],
  ctx : ModCtx,
) -> (@ast.Pattern, @types.Type)? {
  for pr in pairs {
    match sequence_kind_mismatch(pr.0, pr.1, ctx) {
      Some(m) => return Some(m)
      None => ()
    }
  }
  None
}

///|
/// The union of several patterns' bindings, which must be disjoint.
fn pattern_bindings(
  deltas : Array[Context],
  node : @ast.Pattern,
) -> Context raise {
  let mut merged = empty_context()
  for d in deltas {
    let repeated : Array[String] = []
    d.each(fn(x, _) { if merged.contains(x) { repeated.push(x) } })
    if !repeated.is_empty() {
      @basic.sort_names(repeated)
      raise ill(NonlinearPattern(x=repeated[0]), node.span())
    }
    merged = override_context(merged, d)
  }
  merged
}

///|
fn map_seq_match(
  form : (Array[@types.Shape]) -> @types.Shape,
  result : (Array[Array[@types.Shape]], Array[Array[@types.Shape]], Context)?,
) -> MatchResult? {
  match result {
    None => None
    Some((matched, residual, delta)) =>
      Some({ matched: matched.map(form), residual: residual.map(form), delta, })
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
