///|
/// Statement evaluation: Figures 4.3 and 4.4.
///
/// A sequence's result is the bindings the SEQUENCE made, not the whole
/// environment: `eval-seq` composes `assigns ρ'` with what follows, and the
/// caller overrides its own environment with the result. That is what keeps a
/// function body's locals out of its caller.
pub async fn Interp::eval_seq(
  self : Interp,
  items : ArrayView[@analysis.Statement],
  env : Env,
) -> StmtResult noraise {
  let mut accumulated = StmtResult::Assigns(@value.empty_env())
  let mut current = env
  for item in items {
    let r = self.eval_statement(item, current)
    match r {
      Assigns(delta) => {
        accumulated = accumulated.then(Assigns(delta))
        current = @value.override_env(current, delta)
      }
      _ => return accumulated.then(r)
    }
  }
  accumulated
}

///|
pub async fn Interp::eval_body(
  self : Interp,
  body : Array[@ast.Stmt],
  env : Env,
) -> StmtResult noraise {
  self.eval_seq(@analysis.statements(body)[:], env)
}

///|
async fn Interp::eval_statement(
  self : Interp,
  item : @analysis.Statement,
  env : Env,
) -> StmtResult noraise {
  match item {
    Single(s) => self.eval_stmt(s, env)
    // eval-def: a whole region at once, each definition closing over the
    // environment the region starts in.
    Region(defs) => {
      let entries : Array[(String, Value)] = []
      for i, d in defs {
        match d {
          FunctionDef(name~, ..) =>
            entries.push(
              (
                name,
                Value::Def({
                  env,
                  region: defs,
                  index: i,
                  in_module: self.in_module,
                }),
              ),
            )
          _ => ()
        }
      }
      Assigns(@value.env_of(entries))
    }
  }
}

///|
async fn Interp::eval_stmt(
  self : Interp,
  s : @ast.Stmt,
  env : Env,
) -> StmtResult noraise {
  match s {
    // eval-pass
    Pass(..) => Assigns(@value.empty_env())
    // eval-assign
    Assign(targets~, value~, ..) =>
      match self.eval_expr(value, env) {
        Val(v) =>
          match targets[0] {
            Name(id~, ..) => Assigns(@value.env_of([(id, v)]))
            _ => ResultStuck("an assignment target that is not a name")
          }
        Aborts(k) => ResultAborts(k)
        Stuck(op) => ResultStuck(op)
      }
    // eval-expr-stmt
    ExprStmt(value~, ..) =>
      match self.eval_expr(value, env) {
        Val(_) => Assigns(@value.empty_env())
        Aborts(k) => ResultAborts(k)
        Stuck(op) => ResultStuck(op)
      }
    // eval-return, eval-return-none
    Return(value~, ..) =>
      match value {
        None => Returns(Value::None)
        Some(e) =>
          match self.eval_expr(e, env) {
            Val(v) => Returns(v)
            Aborts(k) => ResultAborts(k)
            Stuck(op) => ResultStuck(op)
          }
      }
    // eval-assert and its four companions. The message is evaluated only
    // when the condition is False, and it must be a string.
    Assert(cond~, msg~, ..) =>
      match self.eval_expr(cond, env) {
        Val(Bool(true)) => Assigns(@value.empty_env())
        Val(Bool(false)) =>
          match msg {
            None => {
              self.record(s.span())
              ResultAborts(AssertionError(None))
            }
            Some(m) =>
              match self.eval_expr(m, env) {
                Val(Str(w)) => {
                  self.record(s.span())
                  ResultAborts(AssertionError(Some(w)))
                }
                Val(v) =>
                  ResultStuck("an assertion message of type " + v.kind_name())
                Aborts(k) => ResultAborts(k)
                Stuck(op) => ResultStuck(op)
              }
          }
        Val(v) => ResultStuck("an assertion on " + v.kind_name())
        Aborts(k) => ResultAborts(k)
        Stuck(op) => ResultStuck(op)
      }
    // eval-if, eval-if-none, eval-if-else, eval-else
    If(cond~, body~, or_else~, ..) =>
      match self.eval_expr(cond, env) {
        Val(Bool(true)) => self.eval_body(body, env)
        Val(Bool(false)) =>
          if or_else.is_empty() {
            Assigns(@value.empty_env())
          } else {
            self.eval_body(or_else, env)
          }
        Val(v) => ResultStuck("an if condition on " + v.kind_name())
        Aborts(k) => ResultAborts(k)
        Stuck(op) => ResultStuck(op)
      }
    // eval-match: the result carries the pattern's bindings as well as the
    // body's, composed in that order.
    Match(subject~, cases~, ..) =>
      match self.eval_expr(subject, env) {
        Val(v) =>
          match self.dispatch(env, v, cases) {
            FellThrough => Assigns(@value.empty_env())
            DispatchStuck(op) => ResultStuck(op)
            Taken(bindings, body) => {
              let inner = @value.override_env(env, bindings)
              StmtResult::Assigns(bindings).then(self.eval_body(body, inner))
            }
          }
        Aborts(k) => ResultAborts(k)
        Stuck(op) => ResultStuck(op)
      }
    // eval-class, eval-class-extend
    ClassDef(name~, bases~, ..) => {
      let base = if bases.is_empty() {
        None
      } else {
        match bases[0] {
          Name(id~, ..) => Some(id)
          _ => return ResultStuck("a base class that is not a name")
        }
      }
      // The class entry carries the context its base can be resolved in. At
      // run time that context is built from the environment, where the base
      // class is already a value.
      let declaring = match base {
        None => @context.empty_context()
        Some(b) =>
          match env.get(b) {
            Some(Class(be)) =>
              @context.context_of([(b, @context.Entry::Class(be))])
            _ => return ResultStuck("a base class that is not a class")
          }
      }
      let module_name = match env.get("__name__") {
        Some(Str(q)) => q
        _ => "__main__"
      }
      let entry : @context.ClassEntry = {
        context: declaring,
        name: module_name + "." + name,
        own_fields: @analysis.own_fields(s),
        base,
      }
      Assigns(@value.env_of([(name, Value::Class(entry))]))
    }
    _ => ResultStuck("statement " + s.kind_name())
  }
}
