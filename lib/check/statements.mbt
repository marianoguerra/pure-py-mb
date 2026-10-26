///|
/// The static semantics of statements and expressions: a port of the
/// reference's `statements.py`, function for function.
///
/// Typing is bidirectional. `synth_expr` finds an expression's type;
/// `check_expr` checks one against a type that is already known, which is
/// how a lambda, an empty list or a branch with no type of its own gets one.
/// Every rejection raises at the node the reference raises at, because the
/// position is part of the answer the goldens record.

///|
fn ill(reason : @err.Reason, span : @basic.Span) -> @err.PurePyError {
  @err.ill_formed(reason, span~)
}

///|
fn render(t : @types.Type) -> String {
  @types.render(t)
}

///|
/// The least of a set of names in Python's order, which is what `min` of a
/// Python set answers.
fn min_name(s : @analysis.NameSet) -> String {
  match @basic.min_name(s.to_array()) {
    Some(x) => x
    None => abort("min of an empty set")
  }
}

///|
fn first_node(t : @analysis.Statement) -> @ast.Stmt {
  match t {
    Single(s) => s
    Region(defs) => defs[0]
  }
}

// ---------------------------------------------------------------------------
// Annotations

///|
/// An annotation as written, which the sieve has already insisted is one.
fn type_expr(annotation : @ast.Expr?) -> @types.TypeExpr {
  guard annotation is Some(a) else {
    abort("missing annotation rejected by the sieve")
  }
  guard @types.parse_annotation(a) is Some(t) else {
    abort("unsupported annotation rejected by the sieve")
  }
  t
}

///|
/// What an annotation means here: every name it uses must be in scope as what
/// it says it is.
fn resolve_type(
  psi : @types.TypeExpr,
  span : @basic.Span,
  ctx : ModCtx,
) -> @types.Type raise {
  match psi {
    PrimE(p) => {
      check_in_scope(p.name(), span, ctx)
      Prim(p)
    }
    LitE(v) => {
      check_in_scope("Literal", span, ctx)
      Literal(v)
    }
    ClassName(q) =>
      match resolve_name(q, ctx) {
        Some(Class(c)) => Class(c)
        Some(Unbound) => raise ill(UnboundName(x=q.join(".")), span)
        _ => raise ill(NotClass(q=q.join(".")), span)
      }
    ListE(p) => {
      check_in_scope("list", span, ctx)
      List(resolve_type(p, span, ctx))
    }
    DictE(p) => {
      check_in_scope("dict", span, ctx)
      check_in_scope("str", span, ctx)
      Dict(resolve_type(p, span, ctx))
    }
    TupleE(ps) => {
      check_in_scope("tuple", span, ctx)
      Tuple(ps.map(fn(c) raise { resolve_type(c, span, ctx) }))
    }
    CallableE(ps, r) => {
      check_in_scope("Callable", span, ctx)
      Callable(
        ps.map(fn(p) raise { resolve_type(p, span, ctx) }),
        resolve_type(r, span, ctx),
      )
    }
    UnionE(l, r) =>
      Union(resolve_type(l, span, ctx), resolve_type(r, span, ctx))
  }
}

///|
fn check_in_scope(x : String, span : @basic.Span, ctx : ModCtx) -> Unit raise {
  // Under a profile with the extra builtins, `int` is a function as well as
  // a type, and an annotation may still name it.
  if !(ctx.gamma.get(x) is (Some(Predefined) | Some(Var(Builtin(_))))) {
    raise ill(NotPredefinedName(x~), span)
  }
}

///|
fn def_parts(
  d : @ast.Stmt,
) -> (String, Array[@ast.Arg], Array[@ast.Stmt], @ast.Expr?) {
  match d {
    FunctionDef(name~, args~, body~, returns~, ..) =>
      (name, args.args, body, returns)
    _ => abort("not a function definition")
  }
}

///|
fn signature(d : @ast.Stmt, ctx : ModCtx) -> @types.Type raise {
  let (_, params, _, returns) = def_parts(d)
  let ps = params.map(fn(a) raise {
    resolve_type(type_expr(a.annotation), a.span, ctx)
  })
  let r = resolve_type(type_expr(returns), d.span(), ctx)
  // Defaults exist only under a profile that has them (#56).
  match d {
    FunctionDef(args~, ..) if args.defaults.length() > 0 =>
      Defaulted(ps, args.defaults.length(), r)
    _ => Callable(ps, r)
  }
}

///|
/// Under `DefaultArguments`, each default must have its parameter's type.
fn check_defaults(d : @ast.Stmt, ctx : ModCtx) -> Unit raise {
  guard d is FunctionDef(args~, ..) else { return }
  let n = args.args.length()
  let k = args.defaults.length()
  let ps = parameters(d, ctx)
  for i, e in args.defaults {
    check_expr(e, ps[n - k + i].1, ctx)
  }
}

///|
fn parameters(
  d : @ast.Stmt,
  ctx : ModCtx,
) -> Array[(String, @types.Type)] raise {
  let (_, params, _, _) = def_parts(d)
  params.map(fn(a) raise {
    (a.arg, resolve_type(type_expr(a.annotation), a.span, ctx))
  })
}

// ---------------------------------------------------------------------------
// Sequences

///|
fn check_body(
  body : Array[@ast.Stmt],
  ctx : ModCtx,
  returns : @types.Type?,
) -> Outcome raise {
  check_seq(@analysis.statements(body)[:], ctx, returns)
}

///|
/// A module body: like a sequence, except that a class declaration may appear.
fn check_top_seq(
  ts : ArrayView[@analysis.Statement],
  ctx : ModCtx,
) -> ModCtx raise {
  if ts.is_empty() {
    return ctx
  }
  let delta = match check_top_statement(ts[0], ctx) {
    Assigns(d) => d
    Returns => abort("a top-level return is rejected by check_stmt")
  }
  check_top_seq(ts[1:], ctx.override_gamma(delta))
}

///|
fn check_top_statement(t : @analysis.Statement, ctx : ModCtx) -> Outcome raise {
  match t {
    Single(ClassDef(name~, ..) as node) => {
      let c = class_declared(node, ctx)
      Assigns(context_of([(name, Class(c))]))
    }
    _ => check_statement(t, ctx, None)
  }
}

///|
fn check_seq(
  ss : ArrayView[@analysis.Statement],
  ctx : ModCtx,
  returns : @types.Type?,
) -> Outcome raise {
  if ss.is_empty() {
    return assigns_nothing()
  }
  let s = ss[0]
  let rest = ss[1:]
  let r = check_statement(s, ctx, returns)
  if rest.is_empty() {
    return r
  }
  guard r is Assigns(delta) else {
    raise ill(UnreachableStatement, first_node(rest[0]).span())
  }
  let r_ = check_seq(rest, ctx.override_gamma(delta), returns)
  override_outcomes(r, r_)
}

///|
fn check_statement(
  s : @analysis.Statement,
  ctx : ModCtx,
  returns : @types.Type?,
) -> Outcome raise {
  match s {
    Region(defs) => {
      check_bodies(defs, ctx)
      let entries : Array[(String, Entry)] = []
      for d in defs {
        entries.push((def_parts(d).0, Var(signature(d, ctx))))
      }
      Assigns(context_of(entries))
    }
    Single(st) => check_stmt(st, ctx, returns)
  }
}

///|
fn check_bodies(defs : Array[@ast.Stmt], ctx : ModCtx) -> Unit raise {
  let f_names : Array[(String, Entry)] = []
  for d in defs {
    f_names.push((def_parts(d).0, Var(signature(d, ctx))))
  }
  for d in defs {
    let (name, args, body, returns) = def_parts(d)
    let param_names = args.map(fn(a) { a.arg })
    let locals = scope(param_names, body)
    check_defaults(d, ctx)
    let params = parameters(d, ctx)
    check_assignments_declared(body, param_names)
    let mut delta = context_of(f_names)
    for p in params {
      delta = delta.add(p.0, Var(p.1))
    }
    delta = override_context(delta, locals)
    let declared = resolve_type(type_expr(returns), d.span(), ctx)
    let r = check_body(body, ctx.override_gamma(delta), Some(declared))
    if !(r is Returns) && !@types.subtype(ctx.sigma(), @types.t_none, declared) {
      raise ill(MissingReturn(x=name, tau=render(declared)), d.span())
    }
  }
}

///|
/// The scope of a body: a name may be declared once -- by an annotation, a
/// `def`, a class or an import -- and never where a parameter or a pattern
/// already binds it. Every name the body assigns starts out unbound.
fn scope(ys : Array[String], body : Array[@ast.Stmt]) -> Context raise {
  let patterns = @analysis.pattern_bound(body)
  let is_pattern = fn(x : String) { patterns.iter().any(fn(p) { p.0 == x }) }
  let seen = [..ys]
  for d in @analysis.declares_body(body) {
    if seen.contains(d.0) || is_pattern(d.0) {
      raise ill(Redeclaration(x=d.0), d.1.span())
    }
    seen.push(d.0)
  }
  let clash = ys.filter(is_pattern)
  @basic.sort_names(clash)
  for x in clash {
    for p in patterns {
      if p.0 == x {
        raise ill(Redeclaration(x~), p.1.span())
      }
    }
  }
  let mut out = empty_context()
  for x in @analysis.assigns_body(body).to_array() {
    out = out.add(x, Unbound)
  }
  out
}

///|
/// An assignment to a name the scope never declared: the rules would reject
/// it as unbound, and this says why.
fn check_assignments_declared(
  body : Array[@ast.Stmt],
  bound : Array[String],
) -> Unit raise {
  let declared = @analysis.declares_body(body).map(fn(d) { d.0 })
  let patterns = @analysis.pattern_bound(body)
  for t in @analysis.assign_targets(body) {
    if !declared.contains(t.0) &&
      !bound.contains(t.0) &&
      !patterns.iter().any(fn(p) { p.0 == t.0 }) {
      raise ill(UndeclaredAssignment(x=t.0), t.1.span())
    }
  }
}

///|
/// What assigning `x` at a type does to its entry: a declared variable is
/// assigned, anything else is refused, each for its own reason.
fn assign_name(
  x : String,
  span : @basic.Span,
  ctx : ModCtx,
  check : (@types.Type) -> Unit raise,
) -> @types.Type raise {
  match ctx.gamma.get(x) {
    Some(DU(tau)) => {
      check(tau)
      tau
    }
    Some(PU(_)) => raise ill(MaybeAssigned(x~), span)
    Some(Unbound) => raise ill(AssignmentBeforeDeclaration(x~), span)
    Some(Class(_) | ModuleStub(_) | ModuleLoaded(_, _) | Predefined) =>
      raise ill(Redeclaration(x~), span)
    _ => raise ill(Reassignment(x~), span)
  }
}

///|
fn check_stmt(
  s : @ast.Stmt,
  ctx : ModCtx,
  returns : @types.Type?,
) -> Outcome raise {
  match s {
    Pass(..) => assigns_nothing()
    Assign(targets~, value~, span~) =>
      match targets[0] {
        Name(id~, ..) => {
          let tau = assign_name(id, span, ctx, fn(t) raise {
            check_expr(value, t, ctx)
          })
          Assigns(context_of([(id, Var(tau))]))
        }
        target =>
          Assigns(destructure(target, synth_expr(value, ctx), span, ctx))
      }
    AnnAssign(target~, annotation~, value~, span~, ..) => {
      guard target is Name(id~, ..) else { abort("rejected by the sieve") }
      let tau = resolve_type(type_expr(Some(annotation)), span, ctx)
      match value {
        None => Assigns(context_of([(id, DU(tau))]))
        Some(v) => {
          check_expr(v, tau, ctx)
          Assigns(context_of([(id, Var(tau))]))
        }
      }
    }
    ExprStmt(value~, ..) => {
      synth_expr(value, ctx) |> ignore
      assigns_nothing()
    }
    Return(value~, span~) => {
      guard returns is Some(declared) else { raise ill(TopLevelReturn, span) }
      match value {
        None =>
          if !@types.subtype(ctx.sigma(), @types.t_none, declared) {
            raise ill(
              TypeMismatch(expected=render(declared), actual="None"),
              span,
            )
          }
        Some(e) => check_expr(e, declared, ctx)
      }
      Returns
    }
    If(cond~, body~, or_else~, ..) => {
      check_expr(cond, @types.t_bool, ctx)
      let branches = [check_body(body, ctx, returns)]
      branches.push(
        if or_else.is_empty() {
          assigns_nothing()
        } else {
          check_body(or_else, ctx, returns)
        },
      )
      merge_outcomes(branches)
    }
    Assert(cond~, msg~, ..) => {
      check_expr(cond, @types.t_bool, ctx)
      match msg {
        Some(m) => check_expr(m, @types.t_str, ctx)
        None => ()
      }
      assigns_nothing()
    }
    Match(subject~, cases~, ..) => {
      let tau = synth_expr(subject, ctx)
      check_match_cases(cases, tau, ctx, returns)
    }
    _ => abort("unreachable after the sieve: " + s.kind_name())
  }
}

///|
/// A destructuring target, under a profile that has it: each name is
/// assigned as a plain assignment assigns it, at the type of the component
/// it lands on.
fn destructure(
  target : @ast.Expr,
  tau : @types.Type,
  stmt : @basic.Span,
  ctx : ModCtx,
) -> Context raise {
  match target {
    Name(id~, span~, ..) => {
      let declared = assign_name(id, stmt, ctx, fn(t) raise {
        if !@types.subtype(ctx.sigma(), tau, t) {
          raise ill(TypeMismatch(expected=render(t), actual=render(tau)), span)
        }
      })
      context_of([(id, Var(declared))])
    }
    Tuple(elts~, span~, ..) | List(elts~, span~, ..) => {
      let components = match tau {
        Tuple(ts) if ts.length() == elts.length() => ts
        List(t) => Array::make(elts.length(), t)
        _ =>
          raise ill(
            TypeMismatch(
              expected="tuple of \{elts.length()} components",
              actual=render(tau),
            ),
            span,
          )
      }
      let mut out = empty_context()
      for i, t in elts {
        out = override_context(out, destructure(t, components[i], stmt, ctx))
      }
      out
    }
    _ => abort("rejected by the sieve")
  }
}

// ---------------------------------------------------------------------------
// Match

///|
fn check_match_cases(
  cases : Array[@ast.MatchCase],
  tau : @types.Type,
  ctx : ModCtx,
  returns : @types.Type?,
) -> Outcome raise {
  let (deltas, partial) = match_cases(cases, tau, ctx)
  let branches : Array[Outcome] = []
  for i, c in cases {
    branches.push(
      override_outcomes(
        Assigns(deltas[i]),
        check_body(c.body, ctx.override_gamma(deltas[i]), returns),
      ),
    )
  }
  if partial {
    branches.push(assigns_nothing())
  }
  merge_outcomes(branches)
}

///|
fn match_cases(
  cases : Array[@ast.MatchCase],
  tau : @types.Type,
  ctx : ModCtx,
) -> (Array[Context], Bool) raise {
  let mut residual = @types.shapes(ctx.sigma(), tau, [])
  let deltas : Array[Context] = []
  for i, c in cases {
    match sequence_kind_mismatch(c.pattern, tau, ctx) {
      Some((q, sigma)) => {
        let kind = if q is MatchSequence(kind=List, ..) {
          "list"
        } else {
          "tuple"
        }
        raise ill(SequenceKindMismatch(kind~, tau=render(sigma)), q.span())
      }
      None => ()
    }
    match match_shapes(residual, c.pattern, ctx) {
      None => raise ill(UnreachableCase(index=i + 1), c.pattern.span())
      Some((_, r, delta)) => {
        residual = r
        deltas.push(delta)
      }
    }
  }
  (deltas, residual.length() > 0)
}

// ---------------------------------------------------------------------------
// Expressions

///|
fn synth_expr(e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  match e {
    Name(id~, span~, ..) => {
      if !ctx.is_assigned(id) {
        if ctx.module_of(id) is Some(_) {
          raise ill(ModuleAsValue(q=id), span)
        }
        match ctx.gamma.get(id) {
          Some(Class(_)) => raise ill(ClassAsValue(q=id), span)
          Some(Predefined) => raise ill(PredefinedNameAsValue(q=id), span)
          Some(Unbound) => raise ill(UnboundName(x=id), span)
          Some(DU(_)) => raise ill(UnassignedVariable(x=id), span)
          Some(PU(_)) => raise ill(PossiblyUnassigned(x=id), span)
          _ => raise ill(UndefinedVariable(x=id), span)
        }
      }
      match ctx.assigned_type(id) {
        Some(t) => t
        None => abort("assigned")
      }
    }
    Constant(value~, ..) =>
      match @types.lit_of_constant(value) {
        Some(v) => Literal(v)
        None => abort("rejected by the sieve")
      }
    Lambda(span~, ..) => raise ill(NotSynthesised, span)
    Call(func~, ..) =>
      match class_of_name(func, ctx) {
        Some(c) => constr(c, e, ctx)
        None => call(e, ctx)
      }
    BinOp(left~, op~, right~, ..) =>
      binary(binary_name(op), left, right, e.span(), ctx)
    UnaryOp(op~, operand~, span~) => {
      let t = synth_expr(operand, ctx)
      match @types.literal_type(e) {
        Some(v) => return Literal(v)
        None => ()
      }
      let name = match op {
        Not => "not"
        UAdd => "+"
        USub => "-"
        Invert => abort("rejected by the sieve")
      }
      match
        @types.minimum(
          ctx.sigma(),
          @types.overloads_unary(ctx.sigma(), name, t),
        ) {
        Some(r) => r.result
        None => raise ill(NoUnaryOverload(op=name, sigma=render(t)), span)
      }
    }
    BoolOp(values~, ..) => {
      for v in values {
        check_expr(v, @types.t_bool, ctx)
      }
      @types.t_bool
    }
    Compare(left~, ops~, comparators~, span~) => {
      // Under `core` there is one operator; a chained comparison, under a
      // profile that has it, is the conjunction of its links.
      let mut l = left
      for i, op in ops {
        let r = comparators[i]
        match op {
          Is | IsNot => {
            synth_expr(l, ctx) |> ignore
            synth_expr(r, ctx) |> ignore
          }
          _ => binary(compare_name(op), l, r, span, ctx) |> ignore
        }
        l = r
      }
      @types.t_bool
    }
    IfExp(cond~, ..) => {
      check_expr(cond, @types.t_bool, ctx)
      branch_type(e, ctx)
    }
    Attribute(value~, attr~, span~, ..) =>
      match entry_of(value, ctx) {
        Some(ModuleLoaded(q, members)) => attr_module(q, members, attr, e)
        Some(ModuleStub(q)) => raise ill(SubmoduleNotImported(q~), span)
        _ => attribute_type(synth_expr(value, ctx), e, ctx)
      }
    Subscript(value~, ..) => subscript_type(synth_expr(value, ctx), e, ctx)
    Tuple(elts~, ..) => Tuple(elts.map(fn(x) raise { synth_expr(x, ctx) }))
    List(elts~, ..) => list_type(e, elts, ctx)
    Dict(keys~, values~, ..) => {
      for k in dict_keys(keys) {
        check_expr(k, @types.t_str, ctx)
      }
      dict_type(e, values, ctx)
    }
    ListComp(elt~, generators~, ..) =>
      List(
        @types.base_type(synth_expr(elt, qual_context([elt], generators, ctx))),
      )
    DictComp(key~, value~, generators~, ..) => {
      let ctx_ = qual_context([key, value], generators, ctx)
      check_expr(key, @types.t_str, ctx_)
      Dict(@types.base_type(synth_expr(value, ctx_)))
    }
    // An f-string, under a profile that has it, is a string; each hole is an
    // expression of any type, since `str` of anything is defined.
    JoinedStr(parts~, ..) => {
      for v in @analysis.hole_values(parts) {
        synth_expr(v, ctx) |> ignore
      }
      @types.t_str
    }
    _ => abort("unreachable after the sieve: " + e.kind_name())
  }
}

///|
fn binary_name(op : @ast.Operator) -> String {
  match op {
    Add => "+"
    Sub => "-"
    Mult => "*"
    Div => "/"
    FloorDiv => "//"
    Mod => "%"
    Pow => "**"
    _ => abort("rejected by the sieve")
  }
}

///|
fn compare_name(op : @ast.CmpOp) -> String {
  match op {
    Eq => "=="
    NotEq => "!="
    Lt => "<"
    LtE => "<="
    Gt => ">"
    GtE => ">="
    In => "in"
    NotIn => "not in"
    Is | IsNot => abort("identity has no overloads")
  }
}

///|
fn dict_keys(keys : Array[@ast.Expr?]) -> Array[@ast.Expr] {
  keys.map(fn(k) {
    match k {
      Some(e) => e
      None => abort("dict unpacking rejected by the sieve")
    }
  })
}

///|
fn attr_module(
  q : String,
  members : Context,
  x : String,
  e : @ast.Expr,
) -> @types.Type raise {
  let span = e.span()
  match members.get(x) {
    None => raise ill(UnknownMember(x~, q~), span)
    Some(ModuleStub(sub)) => raise ill(SubmoduleNotImported(q=sub), span)
    Some(ModuleLoaded(_, _)) =>
      raise ill(ModuleAsValue(q=@analysis.qualified_name(e)), span)
    Some(Class(_)) =>
      raise ill(ClassAsValue(q=@analysis.qualified_name(e)), span)
    Some(Predefined) =>
      raise ill(PredefinedNameAsValue(q=@analysis.qualified_name(e)), span)
    Some(Unbound | DU(_) | PU(_)) => raise ill(UnassignedMember(x~, q~), span)
    Some(Var(t)) => t
  }
}

///|
fn attribute_type(
  obj : @types.Type,
  e : @ast.Expr,
  ctx : ModCtx,
) -> @types.Type raise {
  guard e is Attribute(attr~, span~, ..) else { abort("an attribute") }
  match obj {
    Union(s, t) =>
      @types.join_seq(ctx.sigma(), [
        attribute_type(s, e, ctx),
        attribute_type(t, e, ctx),
      ])
    Class(c) =>
      match @types.field_type(ctx.sigma(), c, attr) {
        Some(t) => t
        None => raise ill(UnknownField(c=@types.short_name(c), x=attr), span)
      }
    _ => raise ill(NoAttributes(tau=render(obj)), span)
  }
}

///|
fn subscript_type(
  container : @types.Type,
  e : @ast.Expr,
  ctx : ModCtx,
) -> @types.Type raise {
  guard e is Subscript(slice~, span~, ..) else { abort("a subscript") }
  // A slice, under a profile that has it, keeps the container's type; its
  // bounds are ints.
  if slice is Slice(lower~, upper~, step~, ..) &&
    @types.base_type(container) is (Prim(Str) | List(_) | Tuple(_)) {
    for b in [lower, upper, step] {
      match b {
        Some(x) => check_expr(x, @types.t_int, ctx)
        None => ()
      }
    }
    return match @types.base_type(container) {
      Tuple(cs) => List(@types.join_seq(ctx.sigma(), cs))
      t => t
    }
  }
  if container == @types.t_str {
    check_expr(slice, @types.t_int, ctx)
    return @types.t_str
  }
  match container {
    Union(s, t) =>
      @types.join_seq(ctx.sigma(), [
        subscript_type(s, e, ctx),
        subscript_type(t, e, ctx),
      ])
    List(t) => {
      check_expr(slice, @types.t_int, ctx)
      t
    }
    Dict(t) => {
      check_expr(slice, @types.t_str, ctx)
      t
    }
    Tuple(cs) => tuple_subscript_type(cs, slice, ctx)
    _ => raise ill(NotSubscriptable(tau=render(container)), span)
  }
}

///|
fn tuple_subscript_type(
  cs : Array[@types.Type],
  index : @ast.Expr,
  ctx : ModCtx,
) -> @types.Type raise {
  let m = cs.length()
  let actual = synth_expr(index, ctx)
  match actual {
    Literal(Int(i)) => {
      let mm = BigInt::from_int(m)
      if !(-mm <= i && i < mm) {
        raise ill(TupleIndexOutOfRange(index=i, length=m), index.span())
      }
      let k = i.to_int()
      cs[if k < 0 { m + k } else { k }]
    }
    _ => {
      if actual != @types.t_int {
        raise ill(
          TypeMismatch(expected="int", actual=render(actual)),
          index.span(),
        )
      }
      @types.join_seq(ctx.sigma(), cs)
    }
  }
}

///|
fn branch_type(e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  guard e is IfExp(body~, or_else~, span~, ..) else { abort("a conditional") }
  let branches = [body, or_else]
  let taus = []
  for b in branches {
    if synthesises(b) {
      taus.push(synth_expr(b, ctx))
    }
  }
  if taus.is_empty() {
    raise ill(NotSynthesised, span)
  }
  let tau = @types.join_seq(ctx.sigma(), taus)
  for b in branches {
    if !synthesises(b) {
      check_expr(b, tau, ctx)
    }
  }
  tau
}

///|
fn list_type(
  node : @ast.Expr,
  es : Array[@ast.Expr],
  ctx : ModCtx,
) -> @types.Type raise {
  let taus = []
  for x in es {
    if synthesises(x) {
      taus.push(@types.base_type(synth_expr(x, ctx)))
    }
  }
  if taus.is_empty() {
    raise ill(NotSynthesised, node.span())
  }
  let tau = @types.join_seq(ctx.sigma(), taus)
  for x in es {
    if !synthesises(x) {
      check_expr(x, tau, ctx)
    }
  }
  List(tau)
}

///|
fn dict_type(
  node : @ast.Expr,
  es : Array[@ast.Expr],
  ctx : ModCtx,
) -> @types.Type raise {
  match list_type(node, es, ctx) {
    List(t) => Dict(t)
    _ => abort("a list type")
  }
}

///|
/// Whether an expression has a type of its own, or only one it is checked
/// against.
fn synthesises(e : @ast.Expr) -> Bool {
  match e {
    Lambda(..) => false
    IfExp(body~, or_else~, ..) => synthesises(body) || synthesises(or_else)
    List(elts~, ..) => elts.iter().any(synthesises)
    Dict(values~, ..) => values.iter().any(synthesises)
    Tuple(elts~, ..) => elts.iter().all(synthesises)
    ListComp(elt~, ..) => synthesises(elt)
    DictComp(value~, ..) => synthesises(value)
    Call(func=Lambda(body~, ..), args~, ..) =>
      synthesises(body) && args.iter().all(synthesises)
    _ => true
  }
}

///|
fn constr(c : String, e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  guard e is Call(args~, keywords~, span~, ..) else { abort("a call") }
  let sigma = ctx.sigma()
  let xs = @types.fields(sigma, c)
  let kwd_names : Array[String] = []
  for k in keywords {
    match k.arg {
      Some(a) => kwd_names.push(a)
      None => ()
    }
  }
  let kwd_values = keywords.map(fn(k) { k.value })
  match @types.field_map(sigma, c, args, kwd_names, kwd_values) {
    None => {
      let n = args.length()
      if n + kwd_names.length() != xs.length() {
        raise ill(
          ConstructorArityMismatch(
            c=@types.short_name(c),
            expected=xs.length(),
            got=n + kwd_names.length(),
          ),
          span,
        )
      }
      let rest : Array[String] = []
      for x in xs[n:] {
        if !rest.contains(x) {
          rest.push(x)
        }
      }
      @basic.sort_names(rest)
      raise ill(
        UnknownConstructorKeyword(c=@types.short_name(c), xs=rest),
        span,
      )
    }
    Some(pairs) =>
      for p in pairs {
        check_expr(p.1, @types.declared_type(sigma, c, p.0), ctx)
      }
  }
  Class(c)
}

///|
fn call(e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  guard e is Call(func~, ..) else { abort("a call") }
  match func {
    Lambda(..) => applied_lambda(func, e, ctx)
    // A method of a builtin value, under a profile that has them. A method
    // is a call and never a value: `f = s.upper` is still refused.
    Attribute(value~, attr~, ..) if ctx.program.profile.has(BuiltinMethods) &&
      !(entry_of(value, ctx) is Some(ModuleLoaded(_, _) | ModuleStub(_))) => {
      let recv = synth_expr(value, ctx)
      match method_call_type(recv, attr, e, ctx) {
        Some(t) => t
        None => result_type(attribute_type(recv, func, ctx), e, ctx)
      }
    }
    _ => result_type(synth_expr(func, ctx), e, ctx)
  }
}

///|
fn result_type(
  fn_ : @types.Type,
  e : @ast.Expr,
  ctx : ModCtx,
) -> @types.Type raise {
  guard e is Call(args~, span~, ..) else { abort("a call") }
  match fn_ {
    Union(s, t) =>
      @types.join_seq(ctx.sigma(), [
        result_type(s, e, ctx),
        result_type(t, e, ctx),
      ])
    Callable(ps, t) => {
      if ps.length() != args.length() {
        raise ill(
          CallArityMismatch(expected=ps.length(), given=args.length()),
          span,
        )
      }
      for i, a in args {
        check_expr(a, ps[i], ctx)
      }
      t
    }
    Defaulted(ps, k, t) => {
      if args.length() < ps.length() - k || args.length() > ps.length() {
        raise ill(
          CallArityMismatch(expected=ps.length(), given=args.length()),
          span,
        )
      }
      for i, a in args {
        check_expr(a, ps[i], ctx)
      }
      t
    }
    Builtin(name) => builtin_call_type(name, e, ctx)
    _ => raise ill(NotCallable(tau=render(fn_)), span)
  }
}

///|
fn applied_lambda(
  f : @ast.Expr,
  e : @ast.Expr,
  ctx : ModCtx,
) -> @types.Type raise {
  guard f is Lambda(body~, ..) else { abort("a lambda") }
  synth_expr(body, ctx.override_gamma(lambda_arguments(f, e, ctx)))
}

///|
fn lambda_arguments(
  f : @ast.Expr,
  e : @ast.Expr,
  ctx : ModCtx,
) -> Context raise {
  guard f is Lambda(args=params, ..) else { abort("a lambda") }
  guard e is Call(args~, span~, ..) else { abort("a call") }
  let names = params.args.map(fn(a) { a.arg })
  // Under `DefaultArguments` the trailing parameters with defaults may be
  // left out, and take their defaults' types.
  let k = params.defaults.length()
  if args.length() > names.length() || args.length() < names.length() - k {
    raise ill(
      CallArityMismatch(expected=names.length(), given=args.length()),
      span,
    )
  }
  let mut out = empty_context()
  for i, x in names {
    let t = if i < args.length() {
      synth_expr(args[i], ctx)
    } else {
      @types.base_type(
        synth_expr(params.defaults[i - (names.length() - k)], ctx),
      )
    }
    out = out.add(x, Var(t))
  }
  out
}

///|
fn check_expr(
  e : @ast.Expr,
  expected : @types.Type,
  ctx : ModCtx,
) -> Unit raise {
  match (e, expected) {
    (Call(func=Lambda(body~, ..) as f, ..), _) => {
      check_expr(
        body,
        expected,
        ctx.override_gamma(lambda_arguments(f, e, ctx)),
      )
      return
    }
    (List(elts~, ..), List(t)) => {
      for x in elts {
        check_expr(x, t, ctx)
      }
      return
    }
    (Tuple(elts~, ..), Tuple(ts)) =>
      if elts.length() == ts.length() {
        for i, x in elts {
          check_expr(x, ts[i], ctx)
        }
        return
      }
    (Dict(keys~, values~, ..), Dict(t)) => {
      for k in dict_keys(keys) {
        check_expr(k, @types.t_str, ctx)
      }
      for v in values {
        check_expr(v, t, ctx)
      }
      return
    }
    (Lambda(..), _) => {
      check_lambda(e, expected, ctx)
      return
    }
    (IfExp(cond~, body~, or_else~, ..), _) => {
      check_expr(cond, @types.t_bool, ctx)
      check_expr(body, expected, ctx)
      check_expr(or_else, expected, ctx)
      return
    }
    (ListComp(elt~, generators~, ..), List(t)) => {
      check_expr(elt, t, qual_context([elt], generators, ctx))
      return
    }
    (DictComp(key~, value~, generators~, ..), Dict(t)) => {
      let ctx_ = qual_context([key, value], generators, ctx)
      check_expr(key, @types.t_str, ctx_)
      check_expr(value, t, ctx_)
      return
    }
    _ => ()
  }
  let actual = synth_expr(e, ctx)
  if !@types.subtype(ctx.sigma(), actual, expected) {
    raise ill(
      TypeMismatch(expected=render(expected), actual=render(actual)),
      e.span(),
    )
  }
}

///|
fn check_lambda(
  e : @ast.Expr,
  expected : @types.Type,
  ctx : ModCtx,
) -> Unit raise {
  guard e is Lambda(args~, body~, span~) else { abort("a lambda") }
  let params = args.args.map(fn(a) { a.arg })
  guard expected is Callable(ps, result) else {
    raise ill(LambdaTypeMismatch(expected=render(expected), arity=None), span)
  }
  // Under `DefaultArguments` a lambda may have more parameters than the type
  // asks for, if the extra ones have defaults; each gets its default's type.
  let k = args.defaults.length()
  if ps.length() > params.length() || ps.length() < params.length() - k {
    raise ill(
      LambdaTypeMismatch(expected=render(expected), arity=Some(params.length())),
      span,
    )
  }
  let mut delta = empty_context()
  for i, x in params {
    let t = if i < ps.length() {
      ps[i]
    } else {
      @types.base_type(
        synth_expr(args.defaults[i - (params.length() - k)], ctx),
      )
    }
    delta = delta.add(x, Var(t))
  }
  check_expr(body, result, ctx.override_gamma(delta))
}

///|
fn binary(
  op : String,
  left : @ast.Expr,
  right : @ast.Expr,
  span : @basic.Span,
  ctx : ModCtx,
) -> @types.Type raise {
  let s = synth_expr(left, ctx)
  let t = synth_expr(right, ctx)
  match
    @types.minimum(ctx.sigma(), @types.overloads_binary(ctx.sigma(), op, s, t)) {
    Some(r) => r.result
    None =>
      raise ill(NoBinaryOverload(op~, sigma=render(s), sigma_=render(t)), span)
  }
}

///|
fn qual_context(
  elts : Array[@ast.Expr],
  generators : Array[@ast.Comprehension],
  ctx : ModCtx,
) -> ModCtx raise {
  let delta = check_quals(generators[:], ctx)
  let captured = @analysis.captures_e_list(elts).intersection(
    @analysis.binds_quals(generators),
  )
  if !captured.is_empty() {
    raise ill(
      CapturedGeneratorVariable(x=min_name(captured)),
      generators[0].target.span(),
    )
  }
  ctx.override_gamma(delta)
}

///|
fn target_name(g : @ast.Comprehension) -> String {
  match g.target {
    Name(id~, ..) => id
    _ => abort("rejected by the sieve")
  }
}

///|
fn check_quals(
  generators : ArrayView[@ast.Comprehension],
  ctx : ModCtx,
) -> Context raise {
  if generators.is_empty() {
    return empty_context()
  }
  let g = generators[0]
  let tau = iterated_type(g.iter, ctx)
  let x = target_name(g)
  if @analysis.captures_e_list(g.ifs)
    .union(@analysis.captures_quals_of(generators[1:].to_owned()))
    .contains(x) {
    raise ill(CapturedGeneratorVariable(x~), g.target.span())
  }
  let delta = context_of([(x, Var(tau))])
  let ctx_ = ctx.override_gamma(delta)
  for i in g.ifs {
    check_expr(i, @types.t_bool, ctx_)
  }
  override_context(delta, check_quals(generators[1:], ctx_))
}

///|
fn elem_type(sigma : @types.ClassTable, tau : @types.Type) -> @types.Type? {
  if tau == @types.t_str {
    return Some(@types.t_str)
  }
  match tau {
    List(s) => Some(s)
    Dict(_) => Some(@types.t_str)
    Tuple(ts) => Some(@types.join_seq(sigma, ts.map(@types.base_type)))
    Union(s, t) =>
      match (elem_type(sigma, s), elem_type(sigma, t)) {
        (Some(a), Some(b)) => Some(@types.join_seq(sigma, [a, b]))
        _ => None
      }
    _ => None
  }
}

///|
fn iterated_type(e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  let t = synth_expr(e, ctx)
  match elem_type(ctx.sigma(), t) {
    Some(x) => x
    None => raise ill(NotIterable(tau=render(t)), e.span())
  }
}

// ---------------------------------------------------------------------------
// Classes

///|
/// Declare a class: resolve its fields' types, check them against its base's,
/// and add it to the program's class table.
fn class_declared(node : @ast.Stmt, ctx : ModCtx) -> String raise {
  guard node is ClassDef(name~, bases~, body~, span~, ..) else {
    abort("a class")
  }
  if !(ctx.gamma.get("dataclass") is Some(Predefined)) {
    raise ill(NotPredefinedName(x="dataclass"), span)
  }
  let own : Array[(String, @types.Type)] = []
  for s in body {
    match s {
      AnnAssign(target=Name(id~, ..), annotation~, ..) =>
        own.push((id, resolve_type(type_expr(Some(annotation)), span, ctx)))
      _ => ()
    }
  }
  let names = own.map(fn(p) { p.0 })
  for i, n in names {
    if names[:i].contains(n) {
      raise ill(DuplicateField(x=n, c=name), span)
    }
  }
  let mut base : String? = None
  if bases.length() > 0 {
    guard bases[0] is Name(id=base_name, ..) else {
      abort("rejected by the sieve")
    }
    guard ctx.gamma.get(base_name) is Some(Class(b)) else {
      raise ill(NotClass(q=base_name), span)
    }
    base = Some(b)
    let inherited = @types.fields(ctx.sigma(), b)
    let dups = names.filter(fn(n) { inherited.contains(n) })
    if !dups.is_empty() {
      raise ill(DuplicateField(x=min_name(@analysis.names(dups)), c=name), span)
    }
  }
  let c = ctx.q + "." + name
  ctx.program.sigma = ctx.program.sigma.add(c, { own_fields: own, base, })
  c
}
