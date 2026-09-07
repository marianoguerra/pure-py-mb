///|
/// Statement and expression well-formedness: Figures 3.1 and 3.2.
///
/// A port of the reference's `statements.py`. Three things carry the weight:
///
///   * **The result type is definite assignment.** A statement either returns
///     or leaves a delta saying which names are certainly bound and which are
///     only sometimes bound. `if` merges its branches; a sequence overrides.
///   * **A captured name may not be reassigned afterwards.** That is the one
///     rule that makes closures behave without mutable cells, and `check_seq`
///     is where it lives.
///   * **`min` decides which name a message reports** when several qualify.
///     Sorted sets make that answer the same as the reference's.
using @context {type ResultType, type Status, type Entry}

///|
/// Figure 3.1's result type for one Python statement.
pub fn result_type(node : @ast.Stmt) -> ResultType {
  match node {
    Pass(..) | ExprStmt(..) | Assert(..) | ClassDef(..) =>
      @context.assigns_empty()
    Assign(targets~, ..) => {
      let entries : Array[(String, Status)] = []
      for t in targets {
        match t {
          Name(id~, ..) => entries.push((id, TT))
          _ => ()
        }
      }
      Assigns(@context.vars_of(entries))
    }
    Return(..) => Returns
    FunctionDef(name~, ..) => Assigns(@context.vars_of([(name, TT)]))
    If(body~, or_else~, ..) =>
      @context.merge_results([
        result_type_body(body),
        if or_else.is_empty() {
          @context.assigns_empty()
        } else {
          result_type_body(or_else)
        },
      ])
    Match(cases~, ..) => {
      let branches : Array[ResultType] = []
      for c in cases {
        let bound : Array[(String, Status)] = []
        for x in @analysis.binds(c.pattern) {
          bound.push((x, TT))
        }
        branches.push(
          @context.override_results(
            Assigns(@context.vars_of(bound)),
            result_type_body(c.body),
          ),
        )
      }
      // A match whose last case is not a catch-all may fall through, and then
      // it assigns nothing at all.
      if !is_catch_all(cases[cases.length() - 1].pattern) {
        branches.push(@context.assigns_empty())
      }
      @context.merge_results(branches)
    }
    _ => abort("unreachable after the sieve: " + node.kind_name())
  }
}

///|
pub fn result_type_body(body : ArrayView[@ast.Stmt]) -> ResultType {
  if body.length() == 1 {
    return result_type(body[0])
  }
  @context.override_results(result_type(body[0]), result_type_body(body[1:]))
}

///|
pub fn result_type_statement(item : @analysis.Statement) -> ResultType {
  match item {
    Single(s) => result_type(s)
    Region(defs) => {
      let entries : Array[(String, Status)] = []
      for d in defs {
        match d {
          FunctionDef(name~, ..) => entries.push((name, TT))
          _ => ()
        }
      }
      Assigns(@context.vars_of(entries))
    }
  }
}

// ---------------------------------------------------------------------------

///|
pub fn check_body(body : Array[@ast.Stmt], ctx : Ctx) -> Ctx raise {
  check_seq(@analysis.statements(body)[:], ctx)
}

///|
/// A sequence, one statement at a time, threading the context.
pub fn check_seq(
  items : ArrayView[@analysis.Statement],
  ctx : Ctx,
) -> Ctx raise {
  if items.is_empty() {
    return ctx
  }
  let head = items[0]
  check_statement(head, ctx)
  if items.length() == 1 {
    return next_ctx_after(head, ctx)
  }
  let tail = items[1:]
  if result_type_statement(head) is Returns {
    raise @err.ill_formed(UnreachableStatement, span=first_node(tail[0]).span())
  }
  // The rule that makes closures work without mutable cells: a name a
  // previous statement captured may not be reassigned after it.
  let reassigned = @analysis.captures_statement(head).intersection(
    @analysis.assigns_seq(tail),
  )
  if !reassigned.is_empty() {
    // Python's `min`, not the set's own order: the two differ on strings.
    let name = @basic.min_name(reassigned.to_array()).unwrap()
    match @analysis.find_first_reassigning(tail, reassigned) {
      Some(node) => {
        // The reference records one position. A person reading "captured by
        // previous statement" wants to see WHICH statement, so the capturing
        // one is carried alongside; `short` never prints it, so the
        // comparison with the reference is unaffected.
        let d = @err.Diagnostic::new(
          IllFormed(CapturedReassignment(name~)),
          span=node.span(),
        ).with_related(first_node(head).span(), "'\{name}' captured here")
        raise d.raise_()
      }
      None =>
        abort("a name in assigns_seq must have a statement that assigns it")
    }
  }
  check_seq(tail, next_ctx_after(head, ctx))
}

///|
fn first_node(item : @analysis.Statement) -> @ast.Stmt {
  match item {
    Single(s) => s
    Region(defs) => defs[0]
  }
}

///|
/// What a statement leaves behind.
///
/// A class declaration is the exception: a result type carries statuses only,
/// so the class entry is added to the context here rather than through one.
pub fn next_ctx_after(head : @analysis.Statement, ctx : Ctx) -> Ctx {
  match head {
    Single(ClassDef(name~, ..) as node) =>
      ctx.override_gamma(
        @context.context_of([(name, class_entry_for(node, ctx.q, ctx.gamma))]),
      )
    _ =>
      match result_type_statement(head) {
        Assigns(delta) => ctx.override_var(delta)
        Returns => ctx.override_var(@context.empty_vars())
      }
  }
}

///|
pub fn check_statement(item : @analysis.Statement, ctx : Ctx) -> Unit raise {
  match item {
    Single(s) => check_stmt(s, ctx)
    Region(defs) => check_mutual_region(defs, ctx)
  }
}

///|
/// A mutual region: distinct names, and every body checked with the whole
/// region already in scope.
pub fn check_mutual_region(defs : Array[@ast.Stmt], ctx : Ctx) -> Unit raise {
  let seen : Array[String] = []
  for d in defs {
    match d {
      FunctionDef(name~, span~, ..) => {
        if seen.contains(name) {
          raise @err.ill_formed(DuplicateMutualName(name~), span~)
        }
        seen.push(name)
      }
      _ => ()
    }
  }
  check_bodies(defs, ctx)
}

///|
fn check_bodies(defs : Array[@ast.Stmt], ctx : Ctx) -> Unit raise {
  let region : Array[(String, Status)] = []
  for d in defs {
    match d {
      FunctionDef(name~, ..) => region.push((name, TT))
      _ => ()
    }
  }
  for d in defs {
    match d {
      FunctionDef(args~, body~, ..) => {
        let params = args.args.map(fn(p) { p.arg })
        let delta : Array[(String, Status)] = []
        for entry in region {
          delta.push(entry)
        }
        for p in params {
          delta.push((p, TT))
        }
        // A local assigned somewhere in the body is in scope from the start,
        // but not definitely assigned until it is.
        for
          x in @analysis.assigns_body(body).difference(@analysis.names(params)) {
          delta.push((x, FF))
        }
        check_body(body, ctx.override_var(@context.vars_of(delta))) |> ignore
      }
      _ => ()
    }
  }
}

///|
fn check_stmt(s : @ast.Stmt, ctx : Ctx) -> Unit raise {
  match s {
    Pass(..) => ()
    Assign(targets~, value~, ..) => {
      check_expr(value, ctx)
      // `f = lambda: f` captures the name it is about to bind.
      let captured = @analysis.captures_e(value)
      for t in targets {
        match t {
          Name(id~, span~, ..) =>
            if captured.contains(id) {
              raise @err.ill_formed(SelfCaptureAssignment(name=id), span~)
            }
          _ => ()
        }
      }
    }
    ExprStmt(value~, ..) => check_expr(value, ctx)
    Return(value~, ..) =>
      match value {
        Some(v) => check_expr(v, ctx)
        None => ()
      }
    If(cond~, body~, or_else~, ..) => {
      check_expr(cond, ctx)
      check_body(body, ctx) |> ignore
      if !or_else.is_empty() {
        check_body(or_else, ctx) |> ignore
      }
    }
    Assert(cond~, msg~, ..) => {
      check_expr(cond, ctx)
      match msg {
        Some(m) => check_expr(m, ctx)
        None => ()
      }
    }
    Match(subject~, cases~, span~) => {
      check_expr(subject, ctx)
      check_pattern_list(cases.map(fn(c) { c.pattern }), span, ctx)
      for c in cases {
        let bound : Array[(String, Status)] = []
        for x in @analysis.binds(c.pattern) {
          bound.push((x, TT))
        }
        check_body(c.body, ctx.override_var(@context.vars_of(bound))) |> ignore
      }
    }
    ClassDef(..) => check_class_decl(s, ctx.gamma, ctx.q)
    _ => abort("unreachable after the sieve: " + s.kind_name())
  }
}

///|
fn check_exprs(es : Array[@ast.Expr], ctx : Ctx) -> Unit raise {
  for e in es {
    check_expr(e, ctx)
  }
}

///|
fn check_expr(e : @ast.Expr, ctx : Ctx) -> Unit raise {
  match e {
    Name(id~, span~, ..) =>
      if !(ctx.var_status(id) is Some(TT)) {
        if ctx.module_of(id) is Some(_) {
          raise @err.ill_formed(ModuleAsValue(name=id), span~)
        }
        if ctx.class_of(id) is Some(_) {
          raise @err.ill_formed(ClassAsValue(name=id), span~)
        }
        raise @err.ill_formed(UnassignedVariable(name=id), span~)
      }
    Constant(..) => ()
    Lambda(args~, body~, ..) => {
      let params : Array[(String, Status)] = args.args.map(fn(p) { (p.arg, TT) })
      check_expr(body, ctx.override_var(@context.vars_of(params)))
    }
    Call(func~, args~, keywords~, span~) =>
      match @context.class_entry(func, ctx) {
        Some(entry) => {
          let c_name = entry.short_name()
          let xs = entry.fields()
          let kwd_names : Array[String] = []
          for k in keywords {
            match k.arg {
              Some(a) => kwd_names.push(a)
              None => ()
            }
          }
          let values = keywords.map(fn(k) { k.value })
          if entry.field_map(args, kwd_names, values) is None {
            let n = args.length()
            if n + kwd_names.length() != xs.length() {
              raise @err.ill_formed(
                ConstructorArityMismatch(
                  cls=c_name,
                  expected=xs.length(),
                  got=n + kwd_names.length(),
                ),
                span~,
              )
            }
            raise @err.ill_formed(
              UnknownConstructorKeyword(
                cls=c_name,
                expected_fields=sorted_unique(xs[n:]),
              ),
              span~,
            )
          }
          check_exprs(args, ctx)
          check_exprs(values, ctx)
        }
        // A call that is not a constructor does NOT have its keyword values
        // checked. That is the reference's behaviour, reproduced rather than
        // fixed: the grammar has no keyword arguments outside a constructor,
        // and at run time one is an undefined operation.
        None => {
          check_expr(func, ctx)
          check_exprs(args, ctx)
        }
      }
    BinOp(left~, right~, ..) => {
      check_expr(left, ctx)
      check_expr(right, ctx)
    }
    UnaryOp(operand~, ..) => check_expr(operand, ctx)
    BoolOp(values~, ..) => check_exprs(values, ctx)
    Compare(left~, comparators~, ..) => {
      check_expr(left, ctx)
      check_exprs(comparators, ctx)
    }
    IfExp(cond~, body~, or_else~, ..) => {
      check_expr(cond, ctx)
      check_expr(body, ctx)
      check_expr(or_else, ctx)
    }
    Attribute(value~, attr~, span~, ..) =>
      match @context.entry_of(value, ctx) {
        Some(ModuleLoaded(q, members)) =>
          match members.get(attr) {
            None => raise @err.ill_formed(UnknownMember(x=attr, q~), span~)
            Some(ModuleStub(sub)) =>
              raise @err.ill_formed(SubmoduleNotImported(q=sub), span~)
            Some(ModuleLoaded(_, _)) =>
              raise @err.ill_formed(
                ModuleAsValue(name=@analysis.qualified_name(e)),
                span~,
              )
            Some(Class(_)) =>
              raise @err.ill_formed(
                ClassAsValue(name=@analysis.qualified_name(e)),
                span~,
              )
            Some(Var(FF)) =>
              raise @err.ill_formed(UnassignedMember(x=attr, q~), span~)
            Some(Var(TT)) => ()
          }
        Some(ModuleStub(q)) =>
          raise @err.ill_formed(SubmoduleNotImported(q~), span~)
        _ => check_expr(value, ctx)
      }
    Subscript(value~, slice~, ..) => {
      check_expr(value, ctx)
      check_expr(slice, ctx)
    }
    List(elts~, ..) | Tuple(elts~, ..) => check_exprs(elts, ctx)
    Dict(keys~, values~, ..) => {
      for k in keys {
        match k {
          Some(x) => check_expr(x, ctx)
          None => ()
        }
      }
      check_exprs(values, ctx)
    }
    ListComp(elt~, generators~, ..) =>
      check_comprehension([elt], generators, ctx)
    DictComp(key~, value~, generators~, ..) =>
      check_comprehension([key, value], generators, ctx)
    _ => abort("unreachable after the sieve: " + e.kind_name())
  }
}

///|
/// A comprehension. The variable a generator binds may not be captured by a
/// lambda: the loop rebinds it, and PurePy has no cell to hold the change.
fn check_comprehension(
  elts : Array[@ast.Expr],
  generators : Array[@ast.Comprehension],
  ctx : Ctx,
) -> Unit raise {
  check_quals(generators[:], ctx)
  let bound = @analysis.binds_quals(generators)
  let delta : Array[(String, Status)] = []
  for n in bound {
    delta.push((n, TT))
  }
  check_exprs(elts, ctx.override_var(@context.vars_of(delta)))
  let captured = @analysis.captures_e_list(elts).intersection(bound)
  if !captured.is_empty() {
    raise @err.ill_formed(
      CapturedGeneratorVariable(
        name=@basic.min_name(captured.to_array()).unwrap(),
      ),
      span=generators[0].target.span(),
    )
  }
}

///|
fn check_quals(
  generators : ArrayView[@ast.Comprehension],
  ctx : Ctx,
) -> Unit raise {
  if generators.is_empty() {
    return
  }
  let g = generators[0]
  check_expr(g.iter, ctx)
  let targets = @analysis.names_in_target(g.target)
  let captured = targets.intersection(
    @analysis.captures_e_list(g.ifs).union(captures_quals_view(generators[1:])),
  )
  if !captured.is_empty() {
    raise @err.ill_formed(
      CapturedGeneratorVariable(
        name=@basic.min_name(captured.to_array()).unwrap(),
      ),
      span=g.target.span(),
    )
  }
  let delta : Array[(String, Status)] = []
  for n in targets {
    delta.push((n, TT))
  }
  let ctx_ = ctx.override_var(@context.vars_of(delta))
  check_exprs(g.ifs, ctx_)
  check_quals(generators[1:], ctx_)
}

///|
fn captures_quals_view(
  generators : ArrayView[@ast.Comprehension],
) -> @analysis.NameSet {
  @analysis.captures_quals_of(generators.to_owned())
}

// ---------------------------------------------------------------------------
// Classes

///|
/// The entry a class declaration adds, carrying the context it was declared
/// in -- which is how `fields` resolves its base wherever it is later used.
pub fn class_entry_for(
  node : @ast.Stmt,
  q : String,
  gamma : @context.Context,
) -> Entry {
  match node {
    ClassDef(name~, bases~, ..) => {
      let base = if bases.is_empty() {
        None
      } else {
        match bases[0] {
          Name(id~, ..) => Some(id)
          _ => None
        }
      }
      Class({
        context: gamma,
        name: "\{q}.\{name}",
        own_fields: @analysis.own_fields(node),
        base,
      })
    }
    _ => abort("not a class declaration")
  }
}

///|
fn check_class_decl(
  node : @ast.Stmt,
  gamma : @context.Context,
  q : String,
) -> Unit raise {
  match node {
    ClassDef(name~, bases~, span~, ..) => {
      if gamma.get(name) is Some(Class(_)) {
        raise @err.ill_formed(DuplicateClassName(name~, in_module=q), span~)
      }
      let names = @analysis.own_fields(node)
      let seen : Array[String] = []
      for n in names {
        if seen.contains(n) {
          raise @err.ill_formed(DuplicateFieldName(name=n, cls=name), span~)
        }
        seen.push(n)
      }
      if bases.is_empty() {
        return
      }
      let base_name = match bases[0] {
        Name(id~, ..) => id
        _ => abort("the sieve insists a base class is a simple name")
      }
      // The base must be a class declared in THIS module: its qualified name's
      // prefix is `q`.
      let entry = match gamma.get(base_name) {
        Some(Class(c)) if module_prefix(c.name) == q => c
        _ => raise @err.ill_formed(UnknownBaseClass(base=base_name), span~)
      }
      let inherited = @analysis.names(entry.fields())
      let clash = @analysis.names(names).intersection(inherited)
      if !clash.is_empty() {
        let field = @basic.min_name(clash.to_array()).unwrap()
        let mut d = @err.Diagnostic::new(
          IllFormed(InheritedFieldClash(field~, base=base_name)),
          span~,
        )
        // Point at the base class too: the clash is between two declarations
        // and the message names only one of them.
        match gamma.get(base_name) {
          Some(Class(_)) =>
            d = d.with_related(bases[0].span(), "inherits from here")
          _ => ()
        }
        raise d.raise_()
      }
    }
    _ => ()
  }
}

///|
/// Everything before the last dot of a class's qualified name: the module it
/// was declared in.
fn module_prefix(name : String) -> String {
  match name.rev_split_once(".") {
    Some((head, _)) => head.to_owned()
    None => ""
  }
}
