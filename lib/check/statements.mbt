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
/// A rejection the reference makes for mypy's sake only when the program is
/// otherwise well formed, and as an ordinary one when it is not.
fn ill_mypy_only_if(
  otherwise_well_formed : Bool,
  reason : @err.Reason,
  span : @basic.Span,
) -> @err.PurePyError {
  ill(
    if otherwise_well_formed {
      MypyCompatibility(reason)
    } else {
      reason
    },
    span,
  )
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
/// A definition's type parameters, which the sieve has insisted are plain.
fn type_params(params : Array[@ast.TypeParam]) -> Array[String] {
  params.map(fn(p) { p.name() })
}

///|
fn type_vars(alphas : Array[String]) -> Context {
  context_of(alphas.map(fn(a) { (a, TypeParam) }))
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
    TypeName(q, args) => {
      let name = q.join(".")
      match resolve_name(q, ctx) {
        Some(Unbound) => raise ill(UnboundName(x=name), span)
        Some(TypeParam) if args.is_empty() => TypeVar(name)
        Some(Alias(alphas, tau)) => {
          let sigmas = args.map(fn(a) raise { resolve_type(a, span, ctx) })
          if sigmas.length() != alphas.length() {
            raise ill(
              TypeAliasArityMismatch(
                q=name,
                expected=alphas.length(),
                given=sigmas.length(),
              ),
              span,
            )
          }
          @types.substitute(sigmas[:], alphas[:], tau)
        }
        Some(Class(c)) => {
          let taus = args.map(fn(a) raise { resolve_type(a, span, ctx) })
          let expected = @types.type_params_of(ctx.sigma(), c).length()
          if taus.length() != expected {
            raise ill(
              ClassArityMismatch(q=name, expected~, given=taus.length()),
              span,
            )
          }
          Class(c, taus)
        }
        _ => raise ill(NotClass(q=name), span)
      }
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
) -> (String, @ast.Arguments, Array[@ast.Stmt], @ast.Expr?, Array[String]) {
  match d {
    FunctionDef(name~, args~, body~, returns~, type_params=tps, ..) =>
      (name, args, body, returns, type_params(tps))
    _ => abort("not a function definition")
  }
}

///|
/// A function's signature: a callable type, or a type scheme when it has type
/// parameters.
fn def_signature(d : @ast.Stmt, ctx : ModCtx) -> Entry raise {
  let (_, args, _, returns, alphas) = def_parts(d)
  let ctx_ = ctx.override_gamma(type_vars(alphas))
  let ps = args.args.map(fn(a) raise {
    resolve_type(type_expr(a.annotation), a.span, ctx_)
  })
  let r = resolve_type(type_expr(returns), d.span(), ctx_)
  // Defaults exist only under a profile that has them (#56).
  let tau : @types.Type = if args.defaults.length() > 0 {
    Defaulted(ps, args.defaults.length(), r)
  } else {
    Callable(ps, r)
  }
  if alphas.is_empty() {
    Var(tau)
  } else {
    Scheme(alphas, tau)
  }
}

///|
/// A parameter list's names, which must be distinct.
fn parameter_names(
  args : @ast.Arguments,
  span : @basic.Span,
  f : String?,
) -> Array[String] raise {
  let xs = args.args.map(fn(a) { a.arg })
  for i, x in xs {
    if xs[:i].contains(x) {
      raise ill(DuplicateParameter(x~, f~), span)
    }
  }
  xs
}

// ---------------------------------------------------------------------------
// Sequences

///|
/// `tail`: the body ends a function body, so a fall-through is a missing
/// return.
fn check_body(
  body : Array[@ast.Stmt],
  ctx : ModCtx,
  returns : @types.Type?,
  tail~ : Bool = false,
) -> Outcome raise {
  check_seq(@analysis.statements(body)[:], ctx, returns, tail)
}

///|
/// A module body: like a sequence, except that a class or a type alias may be
/// declared.
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
    Single(ClassDef(..) as node) => dataclass(node, ctx)
    Single(TypeAlias(..) as node) => type_alias(node, ctx)
    _ => check_statement(t, ctx, None)
  }
}

///|
fn check_seq(
  ss : ArrayView[@analysis.Statement],
  ctx : ModCtx,
  returns : @types.Type?,
  tail : Bool,
) -> Outcome raise {
  if ss.is_empty() {
    return assigns_nothing()
  }
  let s = ss[0]
  let rest = ss[1:]
  let r = check_statement(s, ctx, returns, tail=tail && rest.is_empty())
  if rest.is_empty() {
    return r
  }
  guard r is Assigns(delta) else {
    raise ill(UnreachableStatement, first_node(rest[0]).span())
  }
  let r_ = check_seq(rest, ctx.override_gamma(delta), returns, tail)
  override_outcomes(r, r_)
}

///|
fn check_statement(
  s : @analysis.Statement,
  ctx : ModCtx,
  returns : @types.Type?,
  tail~ : Bool = false,
) -> Outcome raise {
  match s {
    Region(defs) => check_defs(defs, ctx)
    Single(st) => check_stmt(st, ctx, returns, tail)
  }
}

///|
/// A mutual region: every signature first, then each body with all of them in
/// scope.
fn check_defs(defs : Array[@ast.Stmt], ctx : ModCtx) -> Outcome raise {
  let pis : Array[(String, Entry)] = []
  for d in defs {
    pis.push((def_parts(d).0, def_signature(d, ctx)))
  }
  let delta = context_of(pis)
  for i, d in defs {
    def_body(d, pis[i].1, ctx.override_gamma(delta))
  }
  Assigns(delta)
}

///|
fn def_body(d : @ast.Stmt, pi : Entry, ctx : ModCtx) -> Unit raise {
  let (name, args, body, _, _) = def_parts(d)
  let (alphas, tau) = match pi {
    Scheme(alphas, tau) => (alphas, tau)
    Var(tau) => ([], tau)
    _ => abort("a signature")
  }
  let (params, result) = match tau {
    Callable(ps, r) | Defaulted(ps, _, r) => (ps, r)
    _ => abort("a callable type")
  }
  let xs = parameter_names(args, d.span(), Some(name))
  check_assignments_declared(body, xs)
  check_defaults(d, params, ctx.override_gamma(type_vars(alphas)))
  let mut delta = type_vars(alphas)
  for i, x in xs {
    delta = delta.add(x, Var(params[i]))
  }
  delta = override_context(delta, scope(xs, body))
  let r = check_body(body, ctx.override_gamma(delta), Some(result), tail=true)
  let sigma = ctx.sigma()
  if !(r is Returns) && !@types.equivalent(sigma, result, @types.t_none) {
    raise ill_mypy_only_if(
      @types.subtype(sigma, @types.t_none, result),
      MissingReturn(x=name, tau=render(result)),
      d.span(),
    )
  }
}

///|
/// Under `DefaultArguments`, each default must have its parameter's type.
fn check_defaults(
  d : @ast.Stmt,
  params : Array[@types.Type],
  ctx : ModCtx,
) -> Unit raise {
  guard d is FunctionDef(args~, ..) else { return }
  let n = args.args.length()
  let k = args.defaults.length()
  for i, e in args.defaults {
    check_expr(e, params[n - k + i], ctx)
  }
}

///|
/// The scope of a body: a name may be declared once -- by an annotation, a
/// `def`, a class, a type alias or an import -- and never where a parameter
/// or a pattern already binds it. Every other name the body assigns starts
/// out unbound.
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
    if !ys.contains(x) {
      out = out.add(x, Unbound)
    }
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
    Some(PU(_, ..)) => raise ill(MaybeAssigned(x~), span)
    Some(Unbound) => raise ill(AssignmentBeforeDeclaration(x~), span)
    Some(
      Class(_)
      | ModuleStub(_)
      | ModuleLoaded(_, _)
      | Predefined
      | TypeParam
      | Alias(_, _)
    ) => raise ill(Redeclaration(x~), span)
    _ => raise ill(Reassignment(x~), span)
  }
}

///|
fn declared_names(s : @ast.Stmt) -> Array[String] {
  @analysis.declares(s).map(fn(d) { d.0 })
}

///|
fn check_stmt(
  s : @ast.Stmt,
  ctx : ModCtx,
  returns : @types.Type?,
  tail : Bool,
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
    ExprStmt(value=Call(func~, ..) as e, ..) if !(func is Lambda(..)) &&
      class_of_name(func, ctx) is None => {
      call_stmt(e, ctx)
      assigns_nothing()
    }
    ExprStmt(value~, ..) => {
      synth_expr(value, ctx) |> ignore
      assigns_nothing()
    }
    Return(value~, span~) => {
      guard returns is Some(declared) else { raise ill(TopLevelReturn, span) }
      match value {
        None => {
          let sigma = ctx.sigma()
          if !@types.equivalent(sigma, declared, @types.t_none) {
            raise ill_mypy_only_if(
              @types.subtype(sigma, @types.t_none, declared),
              BareReturn(tau=render(declared)),
              span,
            )
          }
        }
        Some(e) => check_expr(e, declared, ctx)
      }
      Returns
    }
    If(cond~, body~, or_else~, ..) => {
      check_expr(cond, @types.t_bool, ctx)
      let branches = [check_body(body, ctx, returns, tail~)]
      branches.push(
        if or_else.is_empty() {
          assigns_nothing()
        } else {
          check_body(or_else, ctx, returns, tail~)
        },
      )
      merge_outcomes(branches, declared_names(s))
    }
    Assert(cond~, msg~, ..) => {
      check_expr(cond, @types.t_bool, ctx)
      match msg {
        Some(m) => check_expr(m, @types.t_str, ctx)
        None => ()
      }
      assigns_nothing()
    }
    Match(subject~, ..) => {
      let tau = synth_expr(subject, ctx)
      check_match_cases(s, tau, ctx, returns, tail)
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
  m : @ast.Stmt,
  tau : @types.Type,
  ctx : ModCtx,
  returns : @types.Type?,
  tail : Bool,
) -> Outcome raise {
  guard m is Match(cases~, ..) else { abort("a match") }
  let (deltas, rest, residual) = match_cases(cases, tau, ctx)
  let branches : Array[Outcome] = []
  for i, c in cases {
    branches.push(
      override_outcomes(
        Assigns(deltas[i]),
        check_body(c.body, ctx.override_gamma(deltas[i]), returns, tail~),
      ),
    )
  }
  let partial = rest != @types.t_never
  let sigma = ctx.sigma()
  if partial &&
    tail &&
    returns is Some(r) &&
    !@types.equivalent(sigma, r, @types.t_none) &&
    residual.is_empty() &&
    branches.iter().all(fn(b) { b is Returns }) {
    raise ill(
      MypyCompatibility(MissingReturnMatchPartial(remaining=render(rest))),
      m.span(),
    )
  }
  if partial {
    branches.push(assigns_nothing())
  }
  merge_outcomes(branches, declared_names(m))
}

///|
/// Each case's bindings, the type no case covers, and the shapes no case
/// covers. A case that covers none of the shapes left is unreachable.
fn match_cases(
  cases : Array[@ast.MatchCase],
  tau : @types.Type,
  ctx : ModCtx,
) -> (Array[Context], @types.Type, Array[@types.Shape]) raise {
  let mut residual = @types.shapes(ctx.sigma(), tau, [])
  let mut rest = tau
  let deltas : Array[Context] = []
  for c in cases {
    deltas.push(check_pattern(c.pattern, rest, ctx))
    match match_shapes(residual, c.pattern, ctx) {
      None =>
        raise ill(
          UnreachableCase(pattern=@write.render_pattern(c.pattern)),
          c.pattern.span(),
        )
      Some((_, r)) => residual = r
    }
    rest = remaining(rest, c.pattern, ctx)
  }
  (deltas, rest, residual)
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
          Some(TypeParam) => raise ill(TypeParameterAsValue(x=id), span)
          Some(Alias(_, _)) => raise ill(TypeAliasAsValue(q=id), span)
          Some(Scheme(_, _)) => raise ill(TypeSchemeAsValue(q=id), span)
          Some(Unbound) => raise ill(UnboundName(x=id), span)
          Some(DU(_)) => raise ill(UnassignedVariable(x=id), span)
          Some(PU(_, declared_in_branch~)) =>
            raise ill(PossiblyUnassigned(x=id, declared_in_branch~), span)
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
    Call(func=Subscript(value~, ..), ..) if class_of_name(value, ctx) is Some(_) =>
      constr_explicit(e, ctx)
    Call(func~, ..) =>
      match class_of_name(func, ctx) {
        Some(c) => constr(c, e, ctx)
        None => call(e, ctx)
      }
    BinOp(left~, op~, right~, ..) =>
      binary(binary_name(op), left, right, e.span(), ctx)
    UnaryOp(op~, operand~, span~) => {
      // A negative number is a literal: the reference folds `-1` into one
      // before it checks anything.
      match @types.literal_type(e) {
        Some(v) => return Literal(v)
        None => ()
      }
      let t = synth_expr(operand, ctx)
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
  let name = @analysis.qualified_name(e)
  match members.get(x) {
    None => raise ill(UnknownMember(x~, q~), span)
    Some(ModuleStub(sub)) => raise ill(SubmoduleNotImported(q=sub), span)
    Some(ModuleLoaded(_, _)) => raise ill(ModuleAsValue(q=name), span)
    Some(Class(_)) => raise ill(ClassAsValue(q=name), span)
    Some(Predefined) => raise ill(PredefinedNameAsValue(q=name), span)
    Some(Alias(_, _)) => raise ill(TypeAliasAsValue(q=name), span)
    Some(Scheme(_, _)) => raise ill(TypeSchemeAsValue(q=name), span)
    Some(TypeParam) => abort("a module's members have no type parameters")
    Some(Unbound | DU(_) | PU(_, ..)) =>
      raise ill(UnassignedMember(x~, q~), span)
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
    Class(c, args) =>
      match @types.field_type(ctx.sigma(), c, args, attr) {
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
  if @types.base_type(container) == @types.t_str {
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
/// A constructor call: the class's type arguments are the ones its arguments'
/// types determine.
fn constr(c : String, e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  let args = constructor_args(c, e, ctx)
  let sigma = ctx.sigma()
  let pi = @types.fields(sigma, c)
  let ss = []
  let ts = []
  for p in args {
    if synthesises(p.1) {
      ss.push(@types.lookup(pi.fields, p.0))
      ts.push(synth_expr(p.1, ctx))
    }
  }
  let gamma = @types.type_args_seq(sigma, ss, ts)
  let taus = type_arguments(gamma, pi.type_params, e.span())
  for p in args {
    check_expr(p.1, @types.declared_type(sigma, c, taus, p.0), ctx)
  }
  Class(c, taus)
}

///|
/// `Box[int](1)`: a constructor at type arguments given explicitly.
fn constr_explicit(e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  guard e is Call(func~, span~, ..) else { abort("a call") }
  let tau = resolve_type(type_expr(Some(func)), span, ctx)
  guard tau is Class(c, taus) else { abort("a class type") }
  for p in constructor_args(c, e, ctx) {
    check_expr(p.1, @types.declared_type(ctx.sigma(), c, taus, p.0), ctx)
  }
  tau
}

///|
/// The fields paired with a constructor call's arguments, or why they cannot
/// be.
fn constructor_args(
  c : String,
  e : @ast.Expr,
  ctx : ModCtx,
) -> Array[(String, @ast.Expr)] raise {
  guard e is Call(args~, keywords~, span~, ..) else { abort("a call") }
  let sigma = ctx.sigma()
  let kwd_names : Array[String] = []
  for k in keywords {
    match k.arg {
      Some(a) => kwd_names.push(a)
      None => ()
    }
  }
  let kwd_values = keywords.map(fn(k) { k.value })
  match @types.field_map(sigma, c, args, kwd_names, kwd_values) {
    Some(pairs) => pairs
    None => {
      let name = @types.short_name(c)
      match @types.no_field_map(sigma, c, args.length(), kwd_names) {
        ArityMismatch(expected~, given~) =>
          raise ill(
            ConstructorArityMismatch(c=name, expected~, got=given),
            span,
          )
        UnknownKeywordArgs(xs) =>
          raise ill(UnknownConstructorKeyword(c=name, xs~), span)
        RepeatedKeywordArg => abort("a syntax error in Python")
      }
    }
  }
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
    _ => result_type(callee(e, ctx), e, ctx)
  }
}

///|
/// A call whose value is discarded may return `None`.
fn call_stmt(e : @ast.Expr, ctx : ModCtx) -> Unit raise {
  // A method call, under a profile with methods, is typed by its own rule.
  if e is Call(func=Attribute(value~, ..), ..) &&
    ctx.program.profile.has(BuiltinMethods) &&
    !(entry_of(value, ctx) is Some(ModuleLoaded(_, _) | ModuleStub(_))) {
    call(e, ctx) |> ignore
    return
  }
  match callee(e, ctx) {
    Callable(ss, Prim(NoneType)) => check_args(e, ss, ctx)
    fn_ => result_type(fn_, e, ctx) |> ignore
  }
}

///|
/// The callee's type, a generic function's at the type arguments its
/// arguments determine.
fn callee(e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  guard e is Call(func~, args~, span~, ..) else { abort("a call") }
  match entry_of(func, ctx) {
    Some(Scheme(alphas, tau)) => {
      let params = match tau {
        Callable(ps, _) | Defaulted(ps, _, _) => ps
        _ => abort("a callable type")
      }
      let ss = []
      let ts = []
      for i, a in args {
        if i < params.length() && synthesises(a) {
          ss.push(params[i])
          ts.push(synth_expr(a, ctx))
        }
      }
      let gamma = @types.type_args_seq(ctx.sigma(), ss, ts)
      @types.substitute(type_arguments(gamma, alphas, span)[:], alphas[:], tau)
    }
    _ => synth_expr(func, ctx)
  }
}

///|
/// The type parameters' arguments, each of which the context must have.
fn type_arguments(
  gamma : Array[(String, @types.Type)],
  alphas : Array[String],
  span : @basic.Span,
) -> Array[@types.Type] raise {
  alphas.map(fn(a) raise {
    match gamma.search_by(fn(p) { p.0 == a }) {
      Some(i) => gamma[i].1
      None => raise ill(NoTypeArgument(alpha=a), span)
    }
  })
}

///|
/// A generic function named where a type is expected: instantiated at the
/// arguments the expected type determines.
fn var_scheme(
  alphas : Array[String],
  tau : @types.Type,
  e : @ast.Expr,
  expected : @types.Type,
  ctx : ModCtx,
) -> Unit raise {
  let gamma = @types.type_args_seq(ctx.sigma(), [tau], [expected])
  let actual = @types.substitute(
    type_arguments(gamma, alphas, e.span())[:],
    alphas[:],
    tau,
  )
  if !@types.subtype(ctx.sigma(), actual, expected) {
    raise ill(
      TypeMismatch(expected=render(expected), actual=render(actual)),
      e.span(),
    )
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
      check_args(e, ps, ctx)
      if t == @types.t_none {
        raise ill(MypyCompatibility(NoneResult), span)
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
fn check_args(
  e : @ast.Expr,
  ps : Array[@types.Type],
  ctx : ModCtx,
) -> Unit raise {
  guard e is Call(args~, keywords~, span~, ..) else { abort("a call") }
  if !keywords.is_empty() {
    raise ill(KeywordArgumentsNotConstructor, span)
  }
  if ps.length() != args.length() {
    raise ill(
      CallArityMismatch(expected=ps.length(), given=args.length()),
      span,
    )
  }
  for i, a in args {
    check_expr(a, ps[i], ctx)
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
  guard f is Lambda(args=params, span=fspan, ..) else { abort("a lambda") }
  guard e is Call(args~, keywords~, span~, ..) else { abort("a call") }
  let names = parameter_names(params, fspan, None)
  if !keywords.is_empty() {
    raise ill(KeywordArgumentsNotConstructor, span)
  }
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
    (Name(..) | Attribute(..), _) =>
      match entry_of(e, ctx) {
        Some(Scheme(alphas, tau)) => {
          var_scheme(alphas, tau, e, expected, ctx)
          return
        }
        _ => ()
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
  let params = parameter_names(args, span, None)
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
  if @types.base_type(tau) == @types.t_str {
    return Some(@types.t_str)
  }
  match tau {
    List(s) => Some(s)
    Dict(_) => Some(@types.t_str)
    Class(c, []) if c == @types.range_class => Some(@types.t_int)
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
// Classes and type aliases

///|
/// Declare a class: resolve its fields' types and its base under its type
/// parameters, and add it to the program's class table.
fn dataclass(node : @ast.Stmt, ctx : ModCtx) -> Outcome raise {
  guard node is ClassDef(name~, bases~, body~, type_params=tps, span~, ..) else {
    abort("a class")
  }
  if !(ctx.gamma.get("dataclass") is Some(Predefined)) {
    raise ill(NotPredefinedName(x="dataclass"), span)
  }
  let alphas = type_params(tps)
  let ctx_ = ctx.override_gamma(type_vars(alphas))
  let own : Array[(String, @types.Type)] = []
  for s in body {
    match s {
      AnnAssign(target=Name(id~, ..), annotation~, ..) =>
        own.push((id, resolve_type(type_expr(Some(annotation)), span, ctx_)))
      _ => ()
    }
  }
  let base = if bases.is_empty() {
    None
  } else {
    Some(base_class(bases[0], span, ctx_))
  }
  let inherited = match base {
    None => []
    Some((b, _)) => @types.field_names(ctx.sigma(), b)
  }
  let names = [..inherited, ..own.map(fn(p) { p.0 })]
  for i, n in names {
    if names[:i].contains(n) {
      raise ill(DuplicateField(x=n, c=name), span)
    }
  }
  let c = ctx.q + "." + name
  ctx.program.sigma = ctx.program.sigma.add(c, {
    type_params: alphas,
    own_fields: own,
    base,
  })
  Assigns(context_of([(name, Class(c))]))
}

///|
fn base_class(
  base : @ast.Expr,
  span : @basic.Span,
  ctx : ModCtx,
) -> (String, Array[@types.Type]) raise {
  guard @types.parse_annotation(base) is Some(TypeName(q, _) as psi) else {
    abort("rejected by the sieve")
  }
  if resolve_name(q, ctx) is Some(Alias(_, _)) {
    raise ill(NotClass(q=q.join(".")), span)
  }
  match resolve_type(psi, span, ctx) {
    Class(c, args) => (c, args)
    _ => raise ill(NotClass(q=q.join(".")), span)
  }
}

///|
fn type_alias(node : @ast.Stmt, ctx : ModCtx) -> Outcome raise {
  guard node is TypeAlias(name=Name(id~, ..), type_params=tps, value~, span~) else {
    abort("a type alias")
  }
  let alphas = type_params(tps)
  let tau = resolve_type(
    type_expr(Some(value)),
    span,
    ctx.override_gamma(type_vars(alphas)),
  )
  Assigns(context_of([(id, Alias(alphas, tau))]))
}
