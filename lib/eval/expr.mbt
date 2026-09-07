///|
/// Expression evaluation: Figures 4.5 to 4.10.
///
/// Every rule that needs a condition -- `if`, `and`, `or`, a conditional
/// expression, `assert` -- requires an actual `True` or `False`. Python's
/// truthiness is not PurePy's, so `if 5:` has no rule and the run is
/// undefined. That is one of the conformance suite's dynamically excluded
/// tests, and it is the reason `Stuck` is threaded everywhere.
///
/// Where an abort happened is recorded by `sited`, at each of the six places
/// an expression can produce one. Not by wrapping this function: it recurses
/// and it is `async`, so a step after the recursive call is a continuation
/// allocated per expression rather than a tail call, and that measured 21%
/// on a program that does nothing but call.
pub async fn Interp::eval_expr(
  self : Interp,
  e : @ast.Expr,
  env : Env,
) -> Outcome noraise {
  match e {
    // eval-var
    Name(id~, ..) =>
      match env.get(id) {
        Some(v) => Val(v)
        None => Stuck("the unbound name '" + id + "'")
      }
    // eval-literal
    Constant(value~, ..) =>
      match value {
        Int(n) => Val(Int(n))
        Float(d) => Val(Float(d))
        Str(s) => Val(Str(s))
        Bool(b) => Val(Bool(b))
        None => Val(None)
        _ => Stuck("a literal the sieve should have rejected")
      }
    // eval-lambda
    Lambda(args~, body~, ..) =>
      Val(
        Lam({
          env,
          params: args.args.map(fn(p) { p.arg }),
          body,
          in_module: self.in_module,
        }),
      )
    // eval-unop
    UnaryOp(op~, operand~, ..) =>
      match self.eval_expr(operand, env) {
        Val(v) => self.sited(e, @value.unop(op, v))
        other => other
      }
    // eval-binop
    BinOp(left~, op~, right~, ..) =>
      match self.eval_expr(left, env) {
        Val(a) =>
          match self.eval_expr(right, env) {
            Val(b) => self.sited(e, @value.binop(op, a, b))
            other => other
          }
        other => other
      }
    // eval-and-*, eval-or-*: the second operand is evaluated only when the
    // first leaves the answer open.
    BoolOp(op~, values~, ..) => {
      let mut result = Outcome::Val(Value::None)
      for i, sub in values {
        let o = self.eval_expr(sub, env)
        match o {
          Val(Bool(b)) => {
            let decides = if op is And { !b } else { b }
            if decides {
              return Val(Bool(b))
            }
            result = o
          }
          Val(v) =>
            return Stuck("'" + op.symbol() + "' applied to " + v.kind_name())
          other => return other
        }
        ignore(i)
      }
      result
    }
    Compare(left~, ops~, comparators~, ..) =>
      match self.eval_expr(left, env) {
        Val(a) =>
          match self.eval_expr(comparators[0], env) {
            Val(b) => self.sited(e, @value.compare(ops[0], a, b))
            other => other
          }
        other => other
      }
    // eval-cond-true, eval-cond-false
    IfExp(cond~, body~, or_else~, ..) =>
      match self.eval_expr(cond, env) {
        Val(Bool(true)) => self.eval_expr(body, env)
        Val(Bool(false)) => self.eval_expr(or_else, env)
        Val(v) => Stuck("a conditional expression on " + v.kind_name())
        other => other
      }
    // eval-list, eval-tuple
    List(elts~, ..) =>
      match self.eval_exprs(elts, env) {
        Ok(vs) => Val(List(vs))
        Err(o) => o
      }
    Tuple(elts~, ..) =>
      match self.eval_exprs(elts, env) {
        Ok(vs) => Val(Tuple(vs))
        Err(o) => o
      }
    // eval-dict
    Dict(keys~, values~, ..) => {
      let pairs : Array[(String, Value)] = []
      for i, k in keys {
        let key = match k {
          None => return Stuck("dictionary unpacking")
          Some(x) =>
            match self.eval_expr(x, env) {
              Val(Str(s)) => s
              Val(v) => return Stuck("a dict key of type " + v.kind_name())
              other => return other
            }
        }
        match self.eval_expr(values[i], env) {
          Val(v) => pairs.push((key, v))
          other => return other
        }
      }
      Val(Dict(@value.entries([], pairs)))
    }
    // eval-list-comp
    ListComp(elt~, generators~, ..) =>
      match self.eval_quals(generators[:], env) {
        Ok(envs) => {
          let out : Array[Value] = []
          for e2 in envs {
            match self.eval_expr(elt, e2) {
              Val(v) => out.push(v)
              other => return other
            }
          }
          Val(List(out))
        }
        Err(o) => o
      }
    // eval-dict-comp
    DictComp(key~, value~, generators~, ..) =>
      match self.eval_quals(generators[:], env) {
        Ok(envs) => {
          let pairs : Array[(String, Value)] = []
          for e2 in envs {
            let k = match self.eval_expr(key, e2) {
              Val(Str(s)) => s
              Val(v) => return Stuck("a dict key of type " + v.kind_name())
              other => return other
            }
            match self.eval_expr(value, e2) {
              Val(v) => pairs.push((k, v))
              other => return other
            }
          }
          Val(Dict(@value.entries([], pairs)))
        }
        Err(o) => o
      }
    // eval-attr-module, eval-attr-object, eval-attr-missing
    Attribute(value~, attr~, ..) =>
      match self.eval_expr(value, env) {
        Val(Mod(q, members)) =>
          match members.get(attr) {
            Some(v) => Val(v)
            None => Stuck("module '" + q + "' has no member '" + attr + "'")
          }
        Val(Obj(_, fields_env)) =>
          match fields_env.get(attr) {
            Some(v) => Val(v)
            None => self.sited(e, Aborts(AttributeError))
          }
        // The attributes of a built-in value are undefined: `xs.append` has
        // no rule, which is what makes list mutation unreachable.
        Val(v) => Stuck("an attribute of " + v.kind_name())
        other => other
      }
    // eval-subscript
    Subscript(value~, slice~, ..) =>
      match self.eval_expr(value, env) {
        Val(v) =>
          match self.eval_expr(slice, env) {
            Val(k) => self.sited(e, @value.getitem(v, k))
            other => other
          }
        other => other
      }
    Call(func~, args~, keywords~, ..) =>
      self.eval_call(func, args, keywords, env, e)
    _ => Stuck("expression " + e.kind_name())
  }
}

///|
/// A sequence of expressions, left to right, stopping at the first that does
/// not yield a value (Figure 4.7).
pub async fn Interp::eval_exprs(
  self : Interp,
  es : Array[@ast.Expr],
  env : Env,
) -> Result[Array[Value], Outcome] noraise {
  let out : Array[Value] = []
  for e in es {
    match self.eval_expr(e, env) {
      Val(v) => out.push(v)
      other => return Err(other)
    }
  }
  Ok(out)
}

///|
/// Comprehension qualifiers (Figure 4.10): a list of environments, one per
/// binding the generators produce.
///
/// The enclosing environment is not extended by the result: a comprehension's
/// variables are local to it.
pub async fn Interp::eval_quals(
  self : Interp,
  generators : ArrayView[@ast.Comprehension],
  env : Env,
) -> Result[Array[Env], Outcome] noraise {
  if generators.is_empty() {
    return Ok([env])
  }
  let g = generators[0]
  let name = match g.target {
    Name(id~, ..) => id
    _ => return Err(Stuck("a comprehension target that is not a name"))
  }
  let source = match self.eval_expr(g.iter, env) {
    Val(v) => v
    other => return Err(other)
  }
  let items = match @value.iter(source) {
    Some(xs) => xs
    // eval-qual-generator-nonseq
    None => {
      self.record(g.iter.span())
      return Err(Aborts(TypeError))
    }
  }
  let out : Array[Env] = []
  for u in items {
    let bound = @value.override_env(env, @value.env_of([(name, u)]))
    // The conditions of THIS generator are checked before the ones after it.
    let mut keep = true
    for cond in g.ifs {
      match self.eval_expr(cond, bound) {
        Val(Bool(true)) => ()
        Val(Bool(false)) => {
          keep = false
          break
        }
        Val(v) => return Err(Stuck("a comprehension guard on " + v.kind_name()))
        other => return Err(other)
      }
    }
    if !keep {
      continue
    }
    match self.eval_quals(generators[1:], bound) {
      Ok(envs) =>
        for e2 in envs {
          out.push(e2)
        }
      Err(o) => return Err(o)
    }
  }
  Ok(out)
}

// ---------------------------------------------------------------------------
// Calls

///|
/// A call: a constructor, a lambda, a function from a mutual region, or a
/// primitive. Anything else aborts with `TypeError`.
async fn Interp::eval_call(
  self : Interp,
  func : @ast.Expr,
  args : Array[@ast.Expr],
  keywords : Array[@ast.Keyword],
  env : Env,
  /// The call expression itself, for the aborts with no nearer span: a
  /// constructor of the wrong shape, an arity mismatch, a callee that is not
  /// a function, and whatever a host answers. Passed as the node rather than
  /// its span so that a call which succeeds pays for no span at all.
  call : @ast.Expr,
) -> Outcome noraise {
  // eval-constr: the arguments are evaluated first, and the class is looked
  // up rather than evaluated.
  match self.resolve_class(func, env) {
    Some(entry) => {
      let positional = match self.eval_exprs(args, env) {
        Ok(vs) => vs
        Err(o) => return o
      }
      let kwd_names : Array[String] = []
      let kwd_exprs : Array[@ast.Expr] = []
      for k in keywords {
        match k.arg {
          Some(a) => {
            kwd_names.push(a)
            kwd_exprs.push(k.value)
          }
          None => return Stuck("`**` in a constructor call")
        }
      }
      let kwd_values = match self.eval_exprs(kwd_exprs, env) {
        Ok(vs) => vs
        Err(o) => return o
      }
      match entry.field_map(positional, kwd_names, kwd_values) {
        Some(fields) => Val(Obj(entry, @value.env_of(fields)))
        None => {
          self.record(call.span())
          Aborts(TypeError)
        }
      }
    }
    None => {
      let callee = match self.eval_expr(func, env) {
        Val(v) => v
        other => return other
      }
      // A keyword argument on a call that is not a constructor: the grammar
      // has no rule for one, and the checker does not look at it either.
      if !keywords.is_empty() {
        return Stuck("a keyword argument on a call that is not a constructor")
      }
      let actual = match self.eval_exprs(args, env) {
        Ok(vs) => vs
        Err(o) => return o
      }
      let o = self.apply(callee, actual)
      if o is Aborts(_) {
        self.record(call.span())
      }
      o
    }
  }
}

///|
/// eval-call-lambda, eval-call-def, eval-call-prim and their arity rules.
pub async fn Interp::apply(
  self : Interp,
  callee : Value,
  actual : Array[Value],
) -> Outcome noraise {
  self.depth += 1
  if self.depth > self.max_depth {
    self.depth -= 1
    return Stuck("a call stack deeper than \{self.max_depth}")
  }
  let result = self.apply_(callee, actual)
  self.depth -= 1
  result
}

///|
async fn Interp::apply_(
  self : Interp,
  callee : Value,
  actual : Array[Value],
) -> Outcome noraise {
  match callee {
    Lam(c) => {
      if c.params.length() != actual.length() {
        return Aborts(TypeError)
      }
      // The body runs in the module it was WRITTEN in, not the one calling
      // it, so that an abort inside it is reported against the right file.
      let caller = self.in_module
      self.in_module = c.in_module
      let result = self.eval_expr(c.body, bind(c.env, c.params, actual))
      self.in_module = caller
      result
    }
    // Calling one function of a mutual region rebinds the WHOLE region in the
    // callee's environment, which is what lets its siblings name each other.
    Def(c) => {
      let d = c.region[c.index]
      let (params, body) = match d {
        FunctionDef(args~, body~, ..) => (args.args.map(fn(p) { p.arg }), body)
        _ => return Stuck("a definition closure over something else")
      }
      if params.length() != actual.length() {
        return Aborts(TypeError)
      }
      let region_env = region_bindings(c.env, c.region, c.in_module)
      let inner = bind(region_env, params, actual)
      let caller = self.in_module
      self.in_module = c.in_module
      let result = self.eval_seq(@analysis.statements(body)[:], inner).outcome()
      self.in_module = caller
      result
    }
    Prim(p) => self.call_primitive(p, actual)
    // eval-call-nonfun
    _ => Aborts(TypeError)
  }
}

///|
fn bind(env : Env, params : Array[String], actual : Array[Value]) -> Env {
  let entries : Array[(String, Value)] = []
  for i, p in params {
    entries.push((p, actual[i]))
  }
  @value.override_env(env, @value.env_of(entries))
}

///|
/// `{f⃗: v⃗}`: every definition of a region, as closures over the same
/// environment.
///
/// `in_module` is the module the region was written in, which the closures
/// carry so that an abort inside one is reported against the right file.
pub fn region_bindings(
  env : Env,
  region : Array[@ast.Stmt],
  in_module : String,
) -> Env {
  let entries : Array[(String, Value)] = []
  for i, d in region {
    match d {
      FunctionDef(name~, ..) =>
        entries.push((name, Value::Def({ env, region, index: i, in_module, })))
      _ => ()
    }
  }
  @value.override_env(env, @value.env_of(entries))
}
