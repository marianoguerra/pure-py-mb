///|
/// A minimal evaluator for expressions over LITERALS, so that the operator
/// tables can be written as Python source rather than as constructed values.
///
/// It knows constants, the operators, containers and subscripting, and
/// nothing else -- no names, no calls, no closures. The real evaluator of the
/// `eval` package subsumes it; this exists so that phase 7 can be tested
/// before phase 8 is written.
fn evaluate(source : String) -> String {
  let m = @parser.parse_string("x = " + source + "\n") catch {
    e => return "!syntax \{e}"
  }
  let e = match m.body[0] {
    Assign(value~, ..) => value
    _ => return "!not an expression"
  }
  match literal(e) {
    Val(v) =>
      match v.repr() {
        Some(t) => t
        None => "!unprintable"
      }
    Aborts(k) => "!" + k.name()
    Stuck(_) => "!stuck"
  }
}

///|
fn literal(e : @ast.Expr) -> @value.Outcome {
  match e {
    Constant(value~, ..) =>
      match value {
        Int(n) => Val(Int(n))
        Float(d) => Val(Float(d))
        Str(s) => Val(Str(s))
        Bool(b) => Val(Bool(b))
        None => Val(None)
        _ => Stuck("literal")
      }
    UnaryOp(op~, operand~, ..) =>
      match literal(operand) {
        Val(v) => @value.unop(op, v)
        other => other
      }
    BinOp(left~, op~, right~, ..) =>
      match literal(left) {
        Val(a) =>
          match literal(right) {
            Val(b) => @value.binop(op, a, b)
            other => other
          }
        other => other
      }
    Compare(left~, ops~, comparators~, ..) =>
      match literal(left) {
        Val(a) =>
          match literal(comparators[0]) {
            Val(b) => @value.compare(ops[0], a, b)
            other => other
          }
        other => other
      }
    List(elts~, ..) =>
      match literal_all(elts) {
        Ok(vs) => Val(List(vs))
        Err(o) => o
      }
    Tuple(elts~, ..) =>
      match literal_all(elts) {
        Ok(vs) => Val(Tuple(vs))
        Err(o) => o
      }
    Dict(keys~, values~, ..) => {
      let entries : Array[(String, @value.Value)] = []
      for i, k in keys {
        let key = match k {
          Some(x) =>
            match literal(x) {
              Val(Str(s)) => s
              Val(_) => return Stuck("a dict key that is not a string")
              other => return other
            }
          None => return Stuck("dict unpacking")
        }
        match literal(values[i]) {
          Val(v) => entries.push((key, v))
          other => return other
        }
      }
      Val(Dict(@value.entries([], entries)))
    }
    Subscript(value~, slice~, ..) =>
      match literal(value) {
        Val(a) =>
          match literal(slice) {
            Val(b) => @value.getitem(a, b)
            other => other
          }
        other => other
      }
    _ => Stuck("expression")
  }
}

///|
fn literal_all(
  es : Array[@ast.Expr],
) -> Result[Array[@value.Value], @value.Outcome] {
  let out : Array[@value.Value] = []
  for e in es {
    match literal(e) {
      Val(v) => out.push(v)
      other => return Err(other)
    }
  }
  Ok(out)
}

///|
/// The value an expression over literals denotes, for the printing table.
fn value_of(source : String) -> @value.Value? {
  let m = @parser.parse_string("x = " + source + "\n") catch {
    _ => return None
  }
  let e = match m.body[0] {
    Assign(value~, ..) => value
    _ => return None
  }
  match literal(e) {
    Val(v) => Some(v)
    _ => None
  }
}
