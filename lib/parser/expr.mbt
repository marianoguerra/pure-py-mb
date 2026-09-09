///|
/// Expressions, in Python's precedence order.
///
/// Lowest to highest: `lambda`, conditional, `or`, `and`, `not`, comparison
/// (chained, with `in`, `not in`, `is` and `is not`), `|`, `^`, `&`, shifts,
/// `+ -`, `* @ / // %`, unary `+ - ~`, `**`, `await`, primary (call, subscript,
/// attribute), atom.
///
/// `**` is the awkward one: it binds tighter than unary on its LEFT and looser
/// on its right, so `-2**2` is `-(2**2)` and `2**-1` parses.
fn Parser::parse_expr(self : Parser) -> Expr raise {
  self.descend()
  let e = self.parse_expr_()
  self.ascend()
  e
}

///|
fn Parser::parse_expr_(self : Parser) -> Expr raise {
  if self.at_name("lambda") {
    return self.parse_lambda()
  }
  let start = self.here()
  let cond = self.parse_or()
  if self.at_name("if") {
    let _ = self.advance()
    let branch_cond = self.parse_or()
    let _ = self.expect_name("else")
    let or_else = self.parse_expr()
    return IfExp(
      cond=branch_cond,
      body=cond,
      or_else~,
      span=self.span_from(start),
    )
  }
  cond
}

///|
/// An expression that may be a bare tuple: `a, b` and `a,`. Statement
/// positions accept one; an argument or a subscript does not.
fn Parser::parse_expr_list(
  self : Parser,
  ctx~ : @ast.ExprContext,
) -> Expr raise {
  let start = self.here()
  let first = self.parse_star_or_expr()
  if !self.at_op(",") {
    return first
  }
  let elts : Array[Expr] = [first]
  while self.eat_op(",") {
    if self.ends_expr_list() {
      break
    }
    elts.push(self.parse_star_or_expr())
  }
  Tuple(elts~, ctx~, span=self.span_from(start))
}

///|
fn Parser::ends_expr_list(self : Parser) -> Bool {
  self.ends_statement() ||
  self.at_op("=") ||
  self.at_op(")") ||
  self.at_op("]") ||
  self.at_op("}") ||
  self.at_op(":")
}

///|
/// A `for` target, a `with ... as` target, or a comprehension's target.
///
/// Python calls these `star_targets`, and they are NOT expressions: a name, an
/// attribute, a subscript, a starred one of those, or a bracketed list of
/// them, and no operators at all. Parsing them as expressions is what makes
/// `for y in xs` swallow the `in` as a comparison.
fn Parser::parse_star_targets(self : Parser) -> Expr raise {
  let start = self.here()
  let first = self.parse_star_target()
  if !self.at_op(",") {
    return first
  }
  let elts : Array[Expr] = [first]
  while self.eat_op(",") {
    if self.at_name("in") || self.ends_expr_list() {
      break
    }
    elts.push(self.parse_star_target())
  }
  Tuple(elts~, ctx=Load, span=self.span_from(start))
}

///|
fn Parser::parse_star_target(self : Parser) -> Expr raise {
  if self.at_op("*") {
    let start = self.here()
    let _ = self.advance()
    let value = self.parse_target_atom()
    return Starred(value~, ctx=Load, span=self.span_from(start))
  }
  self.parse_target_atom()
}

///|
fn Parser::parse_target_atom(self : Parser) -> Expr raise {
  let start = self.here()
  if self.at_op("(") {
    let _ = self.advance()
    if self.at_op(")") {
      let _ = self.advance()
      return Tuple(elts=[], ctx=Load, span=self.span_from(start))
    }
    let inner = self.parse_star_targets()
    let _ = self.expect_op(")")
    // `(a)` is `a`; `(a, b)` is already a tuple.
    return inner
  }
  if self.at_op("[") {
    let _ = self.advance()
    let elts : Array[Expr] = []
    while !self.at_op("]") {
      elts.push(self.parse_star_target())
      if !self.eat_op(",") {
        break
      }
    }
    let _ = self.expect_op("]")
    return List(elts~, ctx=Load, span=self.span_from(start))
  }
  let first = self.expect_identifier()
  let mut e = @ast.Expr::Name(
    id=first.text,
    ctx=Load,
    span=self.span_from(start),
  )
  while true {
    if self.at_op(".") {
      let _ = self.advance()
      let attr = self.expect_identifier().text
      e = Attribute(value=e, attr~, ctx=Load, span=self.span_from(start))
    } else if self.at_op("[") {
      let _ = self.advance()
      let slice = self.parse_subscript()
      let _ = self.expect_op("]")
      e = Subscript(value=e, slice~, ctx=Load, span=self.span_from(start))
    } else {
      break
    }
  }
  e
}

///|
fn Parser::parse_star_or_expr(self : Parser) -> Expr raise {
  if self.at_op("*") {
    let start = self.here()
    let _ = self.advance()
    let value = self.parse_or()
    return Starred(value~, ctx=Load, span=self.span_from(start))
  }
  self.parse_expr()
}

///|
/// `x := e`, where the grammar allows it.
fn Parser::parse_namedexpr(self : Parser) -> Expr raise {
  let start = self.here()
  let e = self.parse_expr()
  if self.at_op(":=") {
    let _ = self.advance()
    let value = self.parse_expr()
    return NamedExpr(
      target=set_context(e, Store),
      value~,
      span=self.span_from(start),
    )
  }
  e
}

///|
fn Parser::parse_lambda(self : Parser) -> Expr raise {
  let start = self.here()
  let _ = self.expect_name("lambda")
  let args = self.parse_parameters(annotations=false)
  let _ = self.expect_op(":")
  let body = self.parse_expr()
  Lambda(args~, body~, span=self.span_from(start))
}

///|
fn Parser::parse_or(self : Parser) -> Expr raise {
  let start = self.here()
  let first = self.parse_and()
  if !self.at_name("or") {
    return first
  }
  let values : Array[Expr] = [first]
  while self.eat_name("or") {
    values.push(self.parse_and())
  }
  BoolOp(op=Or, values~, span=self.span_from(start))
}

///|
fn Parser::parse_and(self : Parser) -> Expr raise {
  let start = self.here()
  let first = self.parse_not()
  if !self.at_name("and") {
    return first
  }
  let values : Array[Expr] = [first]
  while self.eat_name("and") {
    values.push(self.parse_not())
  }
  BoolOp(op=And, values~, span=self.span_from(start))
}

///|
fn Parser::parse_not(self : Parser) -> Expr raise {
  if self.at_name("not") {
    let start = self.here()
    let _ = self.advance()
    let operand = self.parse_not()
    return UnaryOp(op=Not, operand~, span=self.span_from(start))
  }
  self.parse_comparison()
}

///|
/// A chain: `a < b <= c` is one `Compare` with two operators.
fn Parser::parse_comparison(self : Parser) -> Expr raise {
  let start = self.here()
  let left = self.parse_bitor()
  let ops : Array[@ast.CmpOp] = []
  let comparators : Array[Expr] = []
  while true {
    match self.comparison_operator() {
      None => break
      Some(op) => {
        ops.push(op)
        comparators.push(self.parse_bitor())
      }
    }
  }
  if ops.is_empty() {
    return left
  }
  Compare(left~, ops~, comparators~, span=self.span_from(start))
}

///|
/// Consume a comparison operator, including the two-word ones.
fn Parser::comparison_operator(self : Parser) -> @ast.CmpOp? {
  let simple : @ast.CmpOp? = match self.peek().kind {
    Op("<") => Some(Lt)
    Op("<=") => Some(LtE)
    Op(">") => Some(Gt)
    Op(">=") => Some(GtE)
    Op("==") => Some(Eq)
    Op("!=") => Some(NotEq)
    _ => None
  }
  match simple {
    Some(op) => {
      let _ = self.advance()
      return Some(op)
    }
    None => ()
  }
  if self.at_name("in") {
    let _ = self.advance()
    return Some(In)
  }
  if self.at_name("not") && self.peek_at(1).is_name("in") {
    let _ = self.advance()
    let _ = self.advance()
    return Some(NotIn)
  }
  if self.at_name("is") {
    let _ = self.advance()
    if self.at_name("not") {
      let _ = self.advance()
      return Some(IsNot)
    }
    return Some(Is)
  }
  None
}

///|
/// The binary levels, each the same shape: a tighter level, then a loop.
fn Parser::parse_bitor(self : Parser) -> Expr raise {
  self.parse_binary(0)
}

///|
/// The binary operator levels, loosest first. `**` is not here: it is
/// right-associative and sits above unary.
fn binary_levels() -> Array[Array[(String, @ast.Operator)]] {
  [
    [("|", BitOr)],
    [("^", BitXor)],
    [("&", BitAnd)],
    [("<<", LShift), (">>", RShift)],
    [("+", Add), ("-", Sub)],
    [("*", Mult), ("@", MatMult), ("/", Div), ("//", FloorDiv), ("%", Mod)],
  ]
}

///|
fn Parser::parse_binary(self : Parser, level : Int) -> Expr raise {
  let levels = binary_levels()
  if level >= levels.length() {
    return self.parse_unary()
  }
  let start = self.here()
  let mut left = self.parse_binary(level + 1)
  while true {
    let mut matched = false
    for entry in levels[level] {
      if self.at_op(entry.0) {
        let _ = self.advance()
        let right = self.parse_binary(level + 1)
        left = BinOp(left~, op=entry.1, right~, span=self.span_from(start))
        matched = true
        break
      }
    }
    if !matched {
      break
    }
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> Expr raise {
  self.descend()
  let e = self.parse_unary_()
  self.ascend()
  e
}

///|
fn Parser::parse_unary_(self : Parser) -> Expr raise {
  let op : @ast.UnaryOp? = match self.peek().kind {
    Op("-") => Some(USub)
    Op("+") => Some(UAdd)
    Op("~") => Some(Invert)
    _ => None
  }
  match op {
    Some(o) => {
      let start = self.here()
      let _ = self.advance()
      let operand = self.parse_unary()
      UnaryOp(op=o, operand~, span=self.span_from(start))
    }
    None => self.parse_power()
  }
}

///|
fn Parser::parse_power(self : Parser) -> Expr raise {
  let start = self.here()
  let base = self.parse_await()
  if self.at_op("**") {
    let _ = self.advance()
    // The right operand is a unary expression, so `2 ** -1` parses.
    let right = self.parse_unary()
    return BinOp(left=base, op=Pow, right~, span=self.span_from(start))
  }
  base
}

///|
fn Parser::parse_await(self : Parser) -> Expr raise {
  if self.at_name("await") {
    let start = self.here()
    let _ = self.advance()
    let value = self.parse_await()
    return Await(value~, span=self.span_from(start))
  }
  self.parse_primary()
}

///|
/// An atom followed by any number of trailers: `f(x).y[0]`.
fn Parser::parse_primary(self : Parser) -> Expr raise {
  let start = self.here()
  let mut e = self.parse_atom()
  while true {
    if self.at_op(".") {
      let _ = self.advance()
      let attr = self.expect_identifier().text
      e = Attribute(value=e, attr~, ctx=Load, span=self.span_from(start))
    } else if self.at_op("(") {
      e = self.parse_call(e, start)
    } else if self.at_op("[") {
      let _ = self.advance()
      let slice = self.parse_subscript()
      let _ = self.expect_op("]")
      e = Subscript(value=e, slice~, ctx=Load, span=self.span_from(start))
    } else {
      break
    }
  }
  e
}

///|
fn Parser::parse_call(self : Parser, func : Expr, start : Pos) -> Expr raise {
  let open = self.expect_op("(")
  let args : Array[Expr] = []
  let keywords : Array[@ast.Keyword] = []
  // A generator written WITHOUT its own brackets -- `f(x for x in y)` -- takes
  // the call's brackets as its extent in CPython's tree. One written with
  // them, `f((x for x in y))`, keeps its own, so which it was has to be
  // remembered rather than guessed from the shape.
  let mut bare_generator = false
  while !self.at_op(")") {
    let arg_start = self.here()
    if self.at_op("**") {
      let _ = self.advance()
      let value = self.parse_expr()
      keywords.push(
        ({ arg: None, value, span: self.span_from(arg_start), } : @ast.Keyword),
      )
    } else if self.at_op("*") {
      let _ = self.advance()
      let value = self.parse_expr()
      args.push(Starred(value~, ctx=Load, span=self.span_from(arg_start)))
    } else if self.peek().kind is Name &&
      self.peek_at(1).is_op("=") &&
      !@token.is_keyword(self.peek().text) {
      let key = self.advance().text
      let _ = self.advance()
      let value = self.parse_expr()
      keywords.push(
        (
          { arg: Some(key), value, span: self.span_from(arg_start), } :
          @ast.Keyword),
      )
    } else {
      let e = self.parse_namedexpr()
      // A bare generator: `f(x for x in y)`.
      if self.at_name("for") ||
        (self.at_name("async") && self.peek_at(1).is_name("for")) {
        let generators = self.parse_comprehension_clauses()
        bare_generator = true
        args.push(
          GeneratorExp(elt=e, generators~, span=self.span_from(arg_start)),
        )
      } else {
        args.push(e)
      }
    }
    if !self.eat_op(",") {
      break
    }
  }
  let close = self.expect_op(")")
  if bare_generator && args.length() == 1 {
    match args[0] {
      GeneratorExp(elt~, generators~, ..) =>
        args[0] = GeneratorExp(elt~, generators~, span={
          start: open.span.start,
          end: close.span.end,
        })
      _ => ()
    }
  }
  Call(func~, args~, keywords~, span=self.span_from(start))
}

///|
/// What goes between `[` and `]`: an expression, a slice, or a tuple of
/// either.
fn Parser::parse_subscript(self : Parser) -> Expr raise {
  let start = self.here()
  let first = self.parse_slice_item()
  if !self.at_op(",") {
    return first
  }
  let elts : Array[Expr] = [first]
  while self.eat_op(",") {
    if self.at_op("]") {
      break
    }
    elts.push(self.parse_slice_item())
  }
  Tuple(elts~, ctx=Load, span=self.span_from(start))
}

///|
fn Parser::parse_slice_item(self : Parser) -> Expr raise {
  let start = self.here()
  let lower = if self.at_op(":") {
    None
  } else {
    Some(self.parse_star_or_expr())
  }
  if !self.at_op(":") {
    return lower.unwrap()
  }
  let _ = self.advance()
  let upper = if self.at_op(":") || self.at_op("]") || self.at_op(",") {
    None
  } else {
    Some(self.parse_expr())
  }
  let step = if self.eat_op(":") {
    if self.at_op("]") || self.at_op(",") {
      None
    } else {
      Some(self.parse_expr())
    }
  } else {
    None
  }
  Slice(lower~, upper~, step~, span=self.span_from(start))
}

// ---------------------------------------------------------------------------
// Atoms

///|
fn Parser::parse_atom(self : Parser) -> Expr raise {
  self.descend()
  let e = self.parse_atom_()
  self.ascend()
  e
}

///|
fn Parser::parse_atom_(self : Parser) -> Expr raise {
  let t = self.peek()
  let start = self.here()
  match t.kind {
    Number => {
      let _ = self.advance()
      let value : @ast.Constant = match t.number_value() {
        Int(n) => Int(n)
        Float(d) => Float(d)
        Imaginary(d) => Complex(d)
      }
      Constant(value~, span=self.span_from(start))
    }
    Str(..) | Bytes(..) | FString(..) => self.parse_string_literal()
    Name =>
      match t.text {
        "None" => {
          let _ = self.advance()
          Constant(value=None, span=self.span_from(start))
        }
        "True" => {
          let _ = self.advance()
          Constant(value=Bool(true), span=self.span_from(start))
        }
        "False" => {
          let _ = self.advance()
          Constant(value=Bool(false), span=self.span_from(start))
        }
        "lambda" => self.parse_lambda()
        "not" => self.parse_not()
        "await" => self.parse_await()
        "yield" => self.parse_yield()
        _ =>
          if @token.is_keyword(t.text) {
            raise self.error("invalid syntax")
          } else {
            let _ = self.advance()
            Name(id=t.text, ctx=Load, span=self.span_from(start))
          }
      }
    Op("...") => {
      let _ = self.advance()
      Constant(value=Ellipsis, span=self.span_from(start))
    }
    Op("(") => self.parse_parenthesised()
    Op("[") => self.parse_bracketed()
    Op("{") => self.parse_braced()
    _ => raise self.error("invalid syntax")
  }
}

///|
fn Parser::parse_yield(self : Parser) -> Expr raise {
  let start = self.here()
  let _ = self.expect_name("yield")
  if self.eat_name("from") {
    let value = self.parse_expr()
    return YieldFrom(value~, span=self.span_from(start))
  }
  let value = if self.ends_statement() ||
    self.at_op(")") ||
    self.at_op("]") ||
    self.at_op("}") {
    None
  } else {
    Some(self.parse_expr_list(ctx=Load))
  }
  Yield(value~, span=self.span_from(start))
}

///|
/// Adjacent string literals are one constant. A group containing an f-string
/// is a `JoinedStr` whose text is the whole group, left unparsed (#55); a
/// group may not mix bytes with text.
fn Parser::parse_string_literal(self : Parser) -> Expr raise {
  let start = self.here()
  let parts : Array[Token] = []
  while self.peek().is_string() {
    parts.push(self.advance())
  }
  let mut any_f = false
  let mut any_bytes = false
  let mut any_text = false
  for p in parts {
    match p.kind {
      FString(..) => {
        any_f = true
        any_text = true
      }
      Bytes(..) => any_bytes = true
      _ => any_text = true
    }
  }
  let span = self.span_from(start)
  if any_bytes && any_text {
    raise error_at("cannot mix bytes and nonbytes literals", span)
  }
  if any_f {
    // The whole group as it was written, whitespace between the parts
    // included: CPython's `ast.get_source_segment` of the node, which is what
    // the oracle compares. Reassembling it from the lexemes loses the gaps.
    return JoinedStr(
      raw=self.src.slice(span),
      parts=self.fstring_parts(parts),
      span~,
    )
  }
  if any_bytes {
    let out = Array()
    for p in parts {
      for b in p.bytes_value() {
        out.push(b)
      }
    }
    return Constant(value=Bytes(Bytes::from_array(out)), span~)
  }
  let text = StringBuilder()
  for p in parts {
    text.write_string(p.str_value())
  }
  Constant(value=Str(text.to_string()), span~)
}

///|
/// `()`, `(e)`, `(a, b)`, `(e for x in y)`, `(yield e)`.
fn Parser::parse_parenthesised(self : Parser) -> Expr raise {
  let start = self.here()
  let _ = self.expect_op("(")
  if self.at_op(")") {
    let _ = self.advance()
    return Tuple(elts=[], ctx=Load, span=self.span_from(start))
  }
  let first = self.parse_star_or_namedexpr()
  if self.at_name("for") ||
    (self.at_name("async") && self.peek_at(1).is_name("for")) {
    let generators = self.parse_comprehension_clauses()
    let _ = self.expect_op(")")
    return GeneratorExp(elt=first, generators~, span=self.span_from(start))
  }
  if self.at_op(",") {
    let elts : Array[Expr] = [first]
    while self.eat_op(",") {
      if self.at_op(")") {
        break
      }
      elts.push(self.parse_star_or_namedexpr())
    }
    let _ = self.expect_op(")")
    return Tuple(elts~, ctx=Load, span=self.span_from(start))
  }
  let _ = self.expect_op(")")
  // A parenthesised expression keeps its OWN position in CPython, not the
  // brackets'. `(a)` is the `Name` at `a`.
  first
}

///|
fn Parser::parse_star_or_namedexpr(self : Parser) -> Expr raise {
  if self.at_op("*") {
    let start = self.here()
    let _ = self.advance()
    let value = self.parse_or()
    return Starred(value~, ctx=Load, span=self.span_from(start))
  }
  self.parse_namedexpr()
}

///|
/// `[]`, `[a, b]`, `[e for x in y]`.
fn Parser::parse_bracketed(self : Parser) -> Expr raise {
  let start = self.here()
  let _ = self.expect_op("[")
  if self.at_op("]") {
    let _ = self.advance()
    return List(elts=[], ctx=Load, span=self.span_from(start))
  }
  let first = self.parse_star_or_namedexpr()
  if self.at_name("for") ||
    (self.at_name("async") && self.peek_at(1).is_name("for")) {
    let generators = self.parse_comprehension_clauses()
    let _ = self.expect_op("]")
    return ListComp(elt=first, generators~, span=self.span_from(start))
  }
  let elts : Array[Expr] = [first]
  while self.eat_op(",") {
    if self.at_op("]") {
      break
    }
    elts.push(self.parse_star_or_namedexpr())
  }
  let _ = self.expect_op("]")
  List(elts~, ctx=Load, span=self.span_from(start))
}

///|
/// `{}` is an empty dict; the rest is decided by whether a `:` follows the
/// first element.
fn Parser::parse_braced(self : Parser) -> Expr raise {
  let start = self.here()
  let _ = self.expect_op("{")
  if self.at_op("}") {
    let _ = self.advance()
    return Dict(keys=[], values=[], span=self.span_from(start))
  }
  if self.at_op("**") {
    return self.parse_dict_rest(start, [], [])
  }
  let first = self.parse_star_or_namedexpr()
  if self.at_op(":") {
    let _ = self.advance()
    let value = self.parse_expr()
    if self.at_name("for") ||
      (self.at_name("async") && self.peek_at(1).is_name("for")) {
      let generators = self.parse_comprehension_clauses()
      let _ = self.expect_op("}")
      return DictComp(
        key=first,
        value~,
        generators~,
        span=self.span_from(start),
      )
    }
    if !self.eat_op(",") {
      let _ = self.expect_op("}")
      return Dict(
        keys=[Some(first)],
        values=[value],
        span=self.span_from(start),
      )
    }
    return self.parse_dict_rest(start, [Some(first)], [value])
  }
  if self.at_name("for") ||
    (self.at_name("async") && self.peek_at(1).is_name("for")) {
    let generators = self.parse_comprehension_clauses()
    let _ = self.expect_op("}")
    return SetComp(elt=first, generators~, span=self.span_from(start))
  }
  let elts : Array[Expr] = [first]
  while self.eat_op(",") {
    if self.at_op("}") {
      break
    }
    elts.push(self.parse_star_or_namedexpr())
  }
  let _ = self.expect_op("}")
  Set(elts~, span=self.span_from(start))
}

///|
fn Parser::parse_dict_rest(
  self : Parser,
  start : Pos,
  keys : Array[Expr?],
  values : Array[Expr],
) -> Expr raise {
  while !self.at_op("}") {
    if self.at_op("**") {
      let _ = self.advance()
      keys.push(None)
      values.push(self.parse_or())
    } else {
      keys.push(Some(self.parse_expr()))
      let _ = self.expect_op(":")
      values.push(self.parse_expr())
    }
    if !self.eat_op(",") {
      break
    }
  }
  let _ = self.expect_op("}")
  Dict(keys~, values~, span=self.span_from(start))
}

///|
/// `for t in e` clauses with their `if` conditions, and `async for`.
fn Parser::parse_comprehension_clauses(
  self : Parser,
) -> Array[@ast.Comprehension] raise {
  let out : Array[@ast.Comprehension] = []
  while true {
    let is_async = if self.at_name("async") && self.peek_at(1).is_name("for") {
      let _ = self.advance()
      true
    } else {
      false
    }
    if !self.at_name("for") {
      break
    }
    let _ = self.advance()
    let target = set_context(self.parse_star_targets(), Store)
    let _ = self.expect_name("in")
    // The iterable of a comprehension is an `or` expression: a bare `if` after
    // it is the comprehension's condition, not a conditional expression.
    let iter = self.parse_or()
    let ifs : Array[Expr] = []
    while self.at_name("if") {
      let _ = self.advance()
      ifs.push(self.parse_comprehension_condition())
    }
    out.push(({ target, iter, ifs, is_async, } : @ast.Comprehension))
  }
  out
}

///|
/// A comprehension's condition is an `or` expression, possibly a walrus: it
/// cannot be a conditional expression without brackets.
fn Parser::parse_comprehension_condition(self : Parser) -> Expr raise {
  let start = self.here()
  let e = self.parse_or()
  if self.at_op(":=") {
    let _ = self.advance()
    let value = self.parse_expr()
    return NamedExpr(
      target=set_context(e, Store),
      value~,
      span=self.span_from(start),
    )
  }
  e
}

// ---------------------------------------------------------------------------
// Parameters

///|
/// A parameter list, for `def` (with annotations) or `lambda` (without).
fn Parser::parse_parameters(
  self : Parser,
  annotations? : Bool = true,
) -> @ast.Arguments raise {
  let posonlyargs : Array[@ast.Arg] = []
  let args : Array[@ast.Arg] = []
  let kwonlyargs : Array[@ast.Arg] = []
  let kw_defaults : Array[Expr?] = []
  let defaults : Array[Expr] = []
  let mut vararg : @ast.Arg? = None
  let mut kwarg : @ast.Arg? = None
  let mut after_star = false
  while !self.at_op(")") && !self.at_op(":") {
    if self.at_op("/") {
      let _ = self.advance()
      // Everything so far was positional-only.
      for a in args {
        posonlyargs.push(a)
      }
      args.clear()
      if !self.eat_op(",") {
        break
      }
      continue
    }
    if self.at_op("*") {
      let _ = self.advance()
      after_star = true
      if !self.at_op(",") {
        vararg = Some(self.parse_parameter(annotations~))
      }
      if !self.eat_op(",") {
        break
      }
      continue
    }
    if self.at_op("**") {
      let _ = self.advance()
      kwarg = Some(self.parse_parameter(annotations~))
      let _ = self.eat_op(",")
      break
    }
    let a = self.parse_parameter(annotations~)
    let default = if self.eat_op("=") { Some(self.parse_expr()) } else { None }
    if after_star {
      kwonlyargs.push(a)
      kw_defaults.push(default)
    } else {
      args.push(a)
      match default {
        Some(d) => defaults.push(d)
        None => ()
      }
    }
    if !self.eat_op(",") {
      break
    }
  }
  { posonlyargs, args, vararg, kwonlyargs, kw_defaults, kwarg, defaults, }
}

///|
fn Parser::parse_parameter(
  self : Parser,
  annotations~ : Bool,
) -> @ast.Arg raise {
  let start = self.here()
  let name = self.expect_identifier().text
  let annotation = if annotations && self.eat_op(":") {
    Some(self.parse_expr())
  } else {
    None
  }
  { arg: name, annotation, span: self.span_from(start), }
}

// ---------------------------------------------------------------------------
// Expression contexts

///|
/// Retag an expression as a store or delete target.
///
/// CPython builds an expression in `Load` and rewrites the context when the
/// grammar says it is a target -- recursively through lists, tuples and
/// starred elements, and never into a call, a subscript's index or an
/// attribute's object.
pub fn set_context(e : Expr, ctx : @ast.ExprContext) -> Expr {
  match e {
    Name(id~, span~, ..) => Name(id~, ctx~, span~)
    Attribute(value~, attr~, span~, ..) => Attribute(value~, attr~, ctx~, span~)
    Subscript(value~, slice~, span~, ..) =>
      Subscript(value~, slice~, ctx~, span~)
    Starred(value~, span~, ..) =>
      Starred(value=set_context(value, ctx), ctx~, span~)
    List(elts~, span~, ..) =>
      List(elts=elts.map(fn(x) { set_context(x, ctx) }), ctx~, span~)
    Tuple(elts~, span~, ..) =>
      Tuple(elts=elts.map(fn(x) { set_context(x, ctx) }), ctx~, span~)
    other => other
  }
}

///|
/// The pieces of an adjacent-string group that contains an f-string.
///
/// Token by token rather than over the group's raw text, because the group may
/// be several literals -- `f"a" "b" f"{c}"` -- with different prefixes, quote
/// styles and raw-ness. Each token knows its own.
///
/// A hole is parsed as a whole module and its one expression taken out, over a
/// source whose text is the FILE up to the hole, blanked, followed by the
/// hole. That is what makes the positions real: line, column and offset all
/// land where they land in the file, so `f"{x}"` with `x` unassigned reports
/// the `x` and not a character in a fragment nobody wrote.
fn Parser::fstring_parts(
  self : Parser,
  tokens : Array[@token.Token],
) -> Array[@ast.FStringPart] raise {
  let out : Array[@ast.FStringPart] = []
  for t in tokens {
    match t.kind {
      FString(..) =>
        for piece in t.fstring_pieces() {
          match piece {
            Text(s) => out.push(Text(s))
            Hole(source~, at~, conversion~, spec~) => {
              let value = self.parse_hole(source, t, at)
              out.push(Hole(value~, conversion~, spec~))
            }
          }
        }
      // A plain literal in the group is literal text, escapes and all.
      _ => out.push(Text(t.str_value()))
    }
  }
  out
}

///|
/// One hole's expression, positioned where it sits in the file.
fn Parser::parse_hole(
  self : Parser,
  source : String,
  tok : @token.Token,
  at : Int,
) -> @ast.Expr raise {
  // The hole begins `at` code points into the token, and the token begins at
  // its span. Everything before it becomes whitespace -- a newline stays a
  // newline so lines line up, anything else becomes as many spaces as it was
  // UTF-16 units so offsets do too -- and the whole thing is wrapped in
  // brackets.
  //
  // The brackets are not decoration. Blank space at the start of a line is
  // INDENTATION, and a module that begins with some is an error; inside
  // brackets the tokenizer joins lines implicitly and indentation means
  // nothing, which is exactly the reading this needs. They also cost no
  // position: the `(` replaces the file's first character and the `)` comes
  // after the hole, so every token of the hole lands where it lands in the
  // file. `f"{a, b}"` becomes `(a, b)`, which is the tuple Python makes of it
  // too.
  let start = self.src.index_of_offset(tok.span.start.offset) + at
  let pad = StringBuilder()
  pad.write_char('(')
  if self.src.chars.length() > 0 && self.src.chars[0].to_int() >= 0x10000 {
    pad.write_char(' ')
  }
  for i in 1..<start {
    let c = self.src.chars[i]
    if c == '\n' {
      pad.write_char('\n')
    } else if c.to_int() >= 0x10000 {
      pad.write_string("  ")
    } else {
      pad.write_char(' ')
    }
  }
  let text = pad.to_string() + source + ")"
  let m = parse(@basic.Source::new(text, name=self.src.name))
  match m.body {
    [ExprStmt(value~, ..)] => value
    _ =>
      raise error_at(
        "f-string: invalid expression in an interpolation",
        tok.span,
      )
  }
}
