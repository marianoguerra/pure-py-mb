///|
/// `match` statements and the pattern grammar of PEP 634.
///
/// The one place this port keeps something CPython throws away: a sequence
/// pattern records whether it was written with brackets or with parentheses
/// (or with neither, which is a tuple). The spec distinguishes the two and the
/// reference recovers the bracket from the source text; recording it in the
/// parser is the same information, obtained where it is still known.
fn Parser::parse_match(self : Parser) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("match")
  let subject = self.parse_subject()
  let _ = self.expect_op(":")
  self.expect_newline()
  if !(self.peek().kind is Indent) {
    raise self.error("expected an indented block")
  }
  let _ = self.advance()
  let cases : Array[@ast.MatchCase] = []
  while self.at_name("case") {
    let _ = self.advance()
    let pattern = self.parse_patterns()
    let when = if self.at_name("if") {
      let _ = self.advance()
      Some(self.parse_namedexpr())
    } else {
      None
    }
    let _ = self.expect_op(":")
    let body = self.parse_block()
    cases.push({ pattern, guard_: when, body, })
    while self.peek().kind is Newline {
      let _ = self.advance()
    }
  }
  if cases.is_empty() {
    raise self.error("expected 'case' block")
  }
  if self.peek().kind is Dedent {
    let _ = self.advance()
  }
  let last = cases[cases.length() - 1].body
  Match(subject~, cases~, span=span_to(start, body_end(last, start)))
}

///|
/// `match a, b:` matches a tuple, so a bare comma list is a tuple here too.
fn Parser::parse_subject(self : Parser) -> Expr raise {
  let start = self.here()
  let first = self.parse_star_or_namedexpr()
  if !self.at_op(",") {
    return first
  }
  let elts : Array[Expr] = [first]
  while self.eat_op(",") {
    if self.at_op(":") {
      break
    }
    elts.push(self.parse_star_or_namedexpr())
  }
  Tuple(elts~, ctx=Load, span=self.span_from(start))
}

///|
/// `case a, b:` is a tuple pattern without brackets.
fn Parser::parse_patterns(self : Parser) -> Pattern raise {
  let start = self.here()
  let first = self.parse_pattern()
  if !self.at_op(",") {
    return first
  }
  let patterns : Array[Pattern] = [first]
  while self.eat_op(",") {
    if self.at_op(":") || self.at_name("if") {
      break
    }
    patterns.push(self.parse_pattern())
  }
  MatchSequence(kind=Tuple, patterns~, span=self.span_from(start))
}

///|
/// `p | q as x`: alternatives first, then the capture.
fn Parser::parse_pattern(self : Parser) -> Pattern raise {
  let start = self.here()
  let first = self.parse_closed_pattern()
  let mut result = first
  if self.at_op("|") {
    let patterns : Array[Pattern] = [first]
    while self.eat_op("|") {
      patterns.push(self.parse_closed_pattern())
    }
    result = MatchOr(patterns~, span=self.span_from(start))
  }
  if self.at_name("as") {
    let _ = self.advance()
    let name = self.expect_identifier().text
    return MatchAs(
      pattern=Some(result),
      name=Some(name),
      span=self.span_from(start),
    )
  }
  result
}

///|
fn Parser::parse_closed_pattern(self : Parser) -> Pattern raise {
  self.descend()
  let p = self.parse_closed_pattern_()
  self.ascend()
  p
}

///|
fn Parser::parse_closed_pattern_(self : Parser) -> Pattern raise {
  let start = self.here()
  let t = self.peek()
  match t.kind {
    Op("[") => {
      let _ = self.advance()
      let patterns = self.parse_sequence_items("]")
      let _ = self.expect_op("]")
      return MatchSequence(kind=List, patterns~, span=self.span_from(start))
    }
    Op("(") => return self.parse_group_or_tuple_pattern(start)
    Op("{") => return self.parse_mapping_pattern(start)
    Op("*") => {
      let _ = self.advance()
      let name = self.parse_capture_name()
      return MatchStar(name~, span=self.span_from(start))
    }
    Op("-") => {
      let value = self.parse_literal_value()
      return MatchValue(value~, span=self.span_from(start))
    }
    Number => {
      let value = self.parse_literal_value()
      return MatchValue(value~, span=self.span_from(start))
    }
    Str(..) | Bytes(..) | FString(..) => {
      let value = self.parse_string_literal()
      return MatchValue(value~, span=self.span_from(start))
    }
    Name =>
      match t.text {
        "None" => {
          let _ = self.advance()
          return MatchSingleton(value=None, span=self.span_from(start))
        }
        "True" => {
          let _ = self.advance()
          return MatchSingleton(value=Bool(true), span=self.span_from(start))
        }
        "False" => {
          let _ = self.advance()
          return MatchSingleton(value=Bool(false), span=self.span_from(start))
        }
        "_" => {
          let _ = self.advance()
          return MatchAs(pattern=None, name=None, span=self.span_from(start))
        }
        _ => {
          if @token.is_keyword(t.text) {
            raise self.error("invalid syntax")
          }
          // A dotted name is a value pattern; a bare name followed by `(` is a
          // class pattern; a bare name alone is a capture.
          if self.peek_at(1).is_op(".") || self.peek_at(1).is_op("(") {
            let head = self.parse_dotted_pattern_head()
            if self.at_op("(") {
              return self.parse_class_pattern(head, start)
            }
            return MatchValue(value=head, span=self.span_from(start))
          }
          let _ = self.advance()
          return MatchAs(
            pattern=None,
            name=Some(t.text),
            span=self.span_from(start),
          )
        }
      }
    _ => ()
  }
  raise self.error("invalid syntax")
}

///|
/// `(p)` is a group and keeps the inner pattern; `(p,)` and `(p, q)` are
/// tuple sequence patterns; `()` is the empty tuple pattern.
fn Parser::parse_group_or_tuple_pattern(
  self : Parser,
  start : Pos,
) -> Pattern raise {
  let _ = self.expect_op("(")
  if self.at_op(")") {
    let _ = self.advance()
    return MatchSequence(kind=Tuple, patterns=[], span=self.span_from(start))
  }
  let first = self.parse_pattern()
  if !self.at_op(",") {
    let _ = self.expect_op(")")
    return first
  }
  let patterns : Array[Pattern] = [first]
  while self.eat_op(",") {
    if self.at_op(")") {
      break
    }
    patterns.push(self.parse_pattern())
  }
  let _ = self.expect_op(")")
  MatchSequence(kind=Tuple, patterns~, span=self.span_from(start))
}

///|
fn Parser::parse_sequence_items(
  self : Parser,
  closer : String,
) -> Array[Pattern] raise {
  let patterns : Array[Pattern] = []
  while !self.at_op(closer) {
    patterns.push(self.parse_pattern())
    if !self.eat_op(",") {
      break
    }
  }
  patterns
}

///|
/// `{"k": p, **rest}`. The keys are expressions; the sieve is what insists
/// they are string literals.
fn Parser::parse_mapping_pattern(self : Parser, start : Pos) -> Pattern raise {
  let _ = self.expect_op("{")
  let keys : Array[Expr] = []
  let patterns : Array[Pattern] = []
  let mut rest : String? = None
  while !self.at_op("}") {
    if self.at_op("**") {
      let _ = self.advance()
      rest = Some(self.expect_identifier().text)
      let _ = self.eat_op(",")
      break
    }
    keys.push(self.parse_mapping_key())
    let _ = self.expect_op(":")
    patterns.push(self.parse_pattern())
    if !self.eat_op(",") {
      break
    }
  }
  let _ = self.expect_op("}")
  MatchMapping(keys~, patterns~, rest~, span=self.span_from(start))
}

///|
fn Parser::parse_mapping_key(self : Parser) -> Expr raise {
  let start = self.here()
  let t = self.peek()
  match t.kind {
    Str(..) | Bytes(..) | FString(..) => self.parse_string_literal()
    Number | Op("-") => self.parse_literal_value()
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
        _ => self.parse_dotted_pattern_head()
      }
    _ => raise self.error("invalid syntax")
  }
}

///|
/// A signed or complex number, or a plain one. `-1` is `UnaryOp(USub, 1)` and
/// `1 + 2j` is a `BinOp`, exactly as CPython builds them inside a pattern.
fn Parser::parse_literal_value(self : Parser) -> Expr raise {
  let start = self.here()
  let mut e = if self.at_op("-") {
    let _ = self.advance()
    let inner = self.parse_number_atom()
    @ast.Expr::UnaryOp(op=USub, operand=inner, span=self.span_from(start))
  } else {
    self.parse_number_atom()
  }
  // `1 + 2j` and `1 - 2j`: a complex literal in a pattern.
  if self.at_op("+") || self.at_op("-") {
    let op : @ast.Operator = if self.at_op("+") { Add } else { Sub }
    let _ = self.advance()
    let right = self.parse_number_atom()
    e = BinOp(left=e, op~, right~, span=self.span_from(start))
  }
  e
}

///|
fn Parser::parse_number_atom(self : Parser) -> Expr raise {
  let start = self.here()
  let t = self.peek()
  if !(t.kind is Number) {
    raise self.error("invalid syntax")
  }
  let _ = self.advance()
  let value : @ast.Constant = match t.number_value() {
    Int(n) => Int(n)
    Float(d) => Float(d)
    Imaginary(d) => Complex(d)
  }
  Constant(value~, span=self.span_from(start))
}

///|
/// `a`, `a.b`, `a.b.c` -- the head of a class pattern or the whole of a value
/// pattern.
fn Parser::parse_dotted_pattern_head(self : Parser) -> Expr raise {
  let start = self.here()
  let first = self.expect_identifier()
  let mut e = @ast.Expr::Name(
    id=first.text,
    ctx=Load,
    span=self.span_from(start),
  )
  while self.at_op(".") {
    let _ = self.advance()
    let attr = self.expect_identifier().text
    e = Attribute(value=e, attr~, ctx=Load, span=self.span_from(start))
  }
  e
}

///|
fn Parser::parse_class_pattern(
  self : Parser,
  cls : Expr,
  start : Pos,
) -> Pattern raise {
  let _ = self.expect_op("(")
  let patterns : Array[Pattern] = []
  let kwd_attrs : Array[String] = []
  let kwd_patterns : Array[Pattern] = []
  while !self.at_op(")") {
    if self.peek().kind is Name &&
      self.peek_at(1).is_op("=") &&
      !@token.is_keyword(self.peek().text) {
      kwd_attrs.push(self.advance().text)
      let _ = self.advance()
      kwd_patterns.push(self.parse_pattern())
    } else {
      patterns.push(self.parse_pattern())
    }
    if !self.eat_op(",") {
      break
    }
  }
  let _ = self.expect_op(")")
  MatchClass(
    cls~,
    patterns~,
    kwd_attrs~,
    kwd_patterns~,
    span=self.span_from(start),
  )
}

///|
/// `*rest` binds a name; `*_` binds nothing.
fn Parser::parse_capture_name(self : Parser) -> String? raise {
  if self.at_name("_") {
    let _ = self.advance()
    None
  } else {
    Some(self.expect_identifier().text)
  }
}
