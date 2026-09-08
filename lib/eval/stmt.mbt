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
  self.machine_seq(items, env)
}

///|
pub async fn Interp::eval_body(
  self : Interp,
  body : Array[@ast.Stmt],
  env : Env,
) -> StmtResult noraise {
  self.machine_seq(@analysis.statements(body)[:], env)
}

///|
/// Match a destructuring target against a value, collecting what it binds.
///
/// Answers `None` when it bound everything and the reason when it could not.
/// Python raises `ValueError` for an arity mismatch and `TypeError` for a
/// value with no elements; PurePy models neither as a termination, so both are
/// undefined here rather than borrowing a kind that means something else.
///
/// Bindings are collected into one array rather than merged environment by
/// environment, so a repeated name -- `a, a = 1, 2`, which Python allows and
/// leaves at 2 -- resolves left to right the way Python resolves it.
fn destructure(
  target : @ast.Expr,
  v : Value,
  out : Array[(String, Value)],
) -> String? {
  match target {
    Name(id~, ..) => {
      out.push((id, v))
      None
    }
    Tuple(elts~, ..) | List(elts~, ..) => {
      let xs = match @value.elems(v) {
        Some(xs) => xs
        None => return Some("unpacking " + v.kind_name())
      }
      if xs.length() != elts.length() {
        return Some(
          "unpacking \{xs.length()} values into \{elts.length()} targets",
        )
      }
      for i, t in elts {
        match destructure(t, xs[i], out) {
          None => ()
          some => return some
        }
      }
      None
    }
    _ => Some("an assignment target that is not a name")
  }
}
