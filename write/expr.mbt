///|
/// An expression, with no brackets of its own: `Writer::expr` has already
/// decided whether the caller's position demands them.
fn Writer::raw_expr(self : Writer, e : @ast.Expr) -> Unit {
  match e {
    BoolOp(op~, values~, ..) => {
      let level = if op is And { prec_and } else { prec_or }
      for i, v in values {
        if i > 0 {
          self.out.write_string(" \{op.symbol()} ")
        }
        self.expr(v, level + 1)
      }
    }
    NamedExpr(target~, value~, ..) => {
      self.expr(target, prec_atom)
      self.out.write_string(" := ")
      self.expr(value, prec_atom)
    }
    BinOp(left~, op~, right~, ..) => {
      let level = operator_precedence(op)
      // `**` is right-associative, so its LEFT operand is the one that needs
      // to be tighter; every other operator is the other way round.
      let (l, r) = if op is Pow {
        (level + 1, level)
      } else {
        (level, level + 1)
      }
      self.expr(left, l)
      self.out.write_string(" \{op.symbol()} ")
      self.expr(right, r)
    }
    UnaryOp(op~, operand~, ..) =>
      if op is Not {
        self.out.write_string("not ")
        self.expr(operand, prec_not)
      } else {
        self.out.write_string(op.symbol())
        self.expr(operand, prec_factor)
      }
    Lambda(args~, body~, ..) => {
      self.out.write_string("lambda")
      let params = self.arguments_text(args)
      if params != "" {
        self.out.write_string(" ")
        self.out.write_string(params)
      }
      self.out.write_string(": ")
      self.expr(body, prec_test)
    }
    IfExp(cond~, body~, or_else~, ..) => {
      self.expr(body, prec_test + 1)
      self.out.write_string(" if ")
      self.expr(cond, prec_test + 1)
      self.out.write_string(" else ")
      self.expr(or_else, prec_test)
    }
    Dict(keys~, values~, ..) => {
      self.out.write_string("{")
      for i, k in keys {
        if i > 0 {
          self.out.write_string(", ")
        }
        match k {
          None => {
            self.out.write_string("**")
            self.expr(values[i], prec_bor)
          }
          Some(key) => {
            self.expr(key, prec_test)
            self.out.write_string(": ")
            self.expr(values[i], prec_test)
          }
        }
      }
      self.out.write_string("}")
    }
    Set(elts~, ..) => {
      self.out.write_string("{")
      self.comma_exprs(elts, prec_test)
      self.out.write_string("}")
    }
    ListComp(elt~, generators~, ..) => {
      self.out.write_string("[")
      self.expr(elt, prec_test)
      self.comprehensions(generators)
      self.out.write_string("]")
    }
    SetComp(elt~, generators~, ..) => {
      self.out.write_string("{")
      self.expr(elt, prec_test)
      self.comprehensions(generators)
      self.out.write_string("}")
    }
    DictComp(key~, value~, generators~, ..) => {
      self.out.write_string("{")
      self.expr(key, prec_test)
      self.out.write_string(": ")
      self.expr(value, prec_test)
      self.comprehensions(generators)
      self.out.write_string("}")
    }
    GeneratorExp(elt~, generators~, ..) => {
      // A generator always carries its own brackets here. Written bare it
      // would only be legal as a call's sole argument, and the tree is the
      // same either way.
      self.out.write_string("(")
      self.expr(elt, prec_test)
      self.comprehensions(generators)
      self.out.write_string(")")
    }
    Await(value~, ..) => {
      self.out.write_string("await ")
      self.expr(value, prec_atom)
    }
    Yield(value~, ..) => {
      self.out.write_string("yield")
      match value {
        Some(v) => {
          self.out.write_string(" ")
          self.expr(v, prec_tuple + 1)
        }
        None => ()
      }
    }
    YieldFrom(value~, ..) => {
      self.out.write_string("yield from ")
      self.expr(value, prec_tuple + 1)
    }
    Compare(left~, ops~, comparators~, ..) => {
      self.expr(left, prec_cmp + 1)
      for i, op in ops {
        self.out.write_string(" \{op.symbol()} ")
        self.expr(comparators[i], prec_cmp + 1)
      }
    }
    Call(func~, args~, keywords~, ..) => {
      self.expr(func, prec_atom)
      self.out.write_string("(")
      let mut first = true
      for a in args {
        if !first {
          self.out.write_string(", ")
        }
        first = false
        self.expr(a, prec_test)
      }
      for k in keywords {
        if !first {
          self.out.write_string(", ")
        }
        first = false
        self.keyword(k)
      }
      self.out.write_string(")")
    }
    JoinedStr(raw~, ..) => self.out.write_string(raw)
    Constant(value~, ..) => self.out.write_string(constant_source(value))
    Attribute(value~, attr~, ..) => {
      // `1.real` would lex as a float; CPython brackets a bare number here.
      let numeric = match value {
        Constant(value=Int(_), ..) | Constant(value=Float(_), ..) => true
        _ => false
      }
      if numeric {
        self.out.write_string("(")
        self.raw_expr(value)
        self.out.write_string(")")
      } else {
        self.expr(value, prec_atom)
      }
      self.out.write_string(".")
      self.out.write_string(attr)
    }
    Subscript(value~, slice~, ..) => {
      self.expr(value, prec_atom)
      self.out.write_string("[")
      // A tuple of slices inside a subscript is written bare: `a[1:2, 3]`.
      match slice {
        Tuple(elts~, ..) if !elts.is_empty() => {
          for i, x in elts {
            if i > 0 {
              self.out.write_string(", ")
            }
            self.expr(x, prec_test)
          }
          if elts.length() == 1 {
            self.out.write_string(",")
          }
        }
        _ => self.expr(slice, prec_tuple + 1)
      }
      self.out.write_string("]")
    }
    Starred(value~, ..) => {
      self.out.write_string("*")
      self.expr(value, prec_bor)
    }
    Name(id~, ..) => self.out.write_string(id)
    List(elts~, ..) => {
      self.out.write_string("[")
      self.comma_exprs(elts, prec_test)
      self.out.write_string("]")
    }
    Tuple(elts~, ..) =>
      // Always bracketed. A bare comma list is legal in a few positions and
      // means the same tree in all of them, so the brackets cost nothing and
      // remove every question of where it is legal.
      if elts.is_empty() {
        self.out.write_string("()")
      } else {
        self.out.write_string("(")
        self.comma_exprs(elts, prec_test)
        if elts.length() == 1 {
          self.out.write_string(",")
        }
        self.out.write_string(")")
      }
    Slice(lower~, upper~, step~, ..) => {
      match lower {
        Some(l) => self.expr(l, prec_test)
        None => ()
      }
      self.out.write_string(":")
      match upper {
        Some(u) => self.expr(u, prec_test)
        None => ()
      }
      match step {
        Some(s) => {
          self.out.write_string(":")
          self.expr(s, prec_test)
        }
        None => ()
      }
    }
  }
}

///|
/// A constant as SOURCE, which is not always its `repr`.
///
///   * `Ellipsis` is spelled `...`.
///   * `inf` and `nan` are not literals at all. CPython's own unparser writes
///     `1e309` for an infinity, which overflows to one when read back; `nan`
///     it cannot express, and neither can this, so it is left as `nan` and the
///     round trip on such a file is the one thing the printer cannot promise.
fn constant_source(value : @ast.Constant) -> String {
  match value {
    Ellipsis => "..."
    Float(d) => float_source(d)
    Complex(d) => float_source(d) + "j"
    other => other.to_literal()
  }
}

///|
fn float_source(d : Double) -> String {
  let text = @basic.py_float_repr(d)
  match text {
    "inf" => "1e309"
    "-inf" => "-1e309"
    _ => text
  }
}

///|
fn Writer::keyword(self : Writer, k : @ast.Keyword) -> Unit {
  match k.arg {
    None => {
      self.out.write_string("**")
      self.expr(k.value, prec_test)
    }
    Some(name) => {
      self.out.write_string(name)
      self.out.write_string("=")
      self.expr(k.value, prec_test)
    }
  }
}

///|
fn Writer::comprehensions(
  self : Writer,
  gens : Array[@ast.Comprehension],
) -> Unit {
  for g in gens {
    self.out.write_string(if g.is_async { " async for " } else { " for " })
    self.expr(g.target, prec_tuple + 1)
    self.out.write_string(" in ")
    self.expr(g.iter, prec_or)
    for c in g.ifs {
      self.out.write_string(" if ")
      self.expr(c, prec_or)
    }
  }
}

// ---------------------------------------------------------------------------
// Parameters

///|
fn Writer::arguments(self : Writer, a : @ast.Arguments) -> Unit {
  self.out.write_string(self.arguments_text(a))
}

///|
/// A parameter list. Built as a string because `lambda` needs to know whether
/// it is empty before writing the space in front of it.
fn Writer::arguments_text(_self : Writer, a : @ast.Arguments) -> String {
  let inner : Writer = { out: StringBuilder(), depth: 0, }
  let parts : Array[String] = []
  // Defaults fill the positional parameters from the right.
  let positional = a.posonlyargs + a.args
  let first_default = positional.length() - a.defaults.length()
  for i, p in positional {
    let piece = StringBuilder()
    piece.write_string(inner.arg_text(p))
    if i >= first_default {
      let d = a.defaults[i - first_default]
      // With an annotation Python writes ` = `, without it `=`.
      piece.write_string(if p.annotation is Some(_) { " = " } else { "=" })
      piece.write_string(inner.sub_expr(d, prec_test))
    }
    parts.push(piece.to_string())
    if i + 1 == a.posonlyargs.length() {
      parts.push("/")
    }
  }
  match a.vararg {
    Some(v) => parts.push("*" + inner.arg_text(v))
    None => if !a.kwonlyargs.is_empty() { parts.push("*") }
  }
  for i, p in a.kwonlyargs {
    let piece = StringBuilder()
    piece.write_string(inner.arg_text(p))
    if i < a.kw_defaults.length() {
      match a.kw_defaults[i] {
        Some(d) => {
          piece.write_string(if p.annotation is Some(_) { " = " } else { "=" })
          piece.write_string(inner.sub_expr(d, prec_test))
        }
        None => ()
      }
    }
    parts.push(piece.to_string())
  }
  match a.kwarg {
    Some(k) => parts.push("**" + inner.arg_text(k))
    None => ()
  }
  join(parts, ", ")
}

///|
fn Writer::arg_text(self : Writer, a : @ast.Arg) -> String {
  match a.annotation {
    None => a.arg
    Some(t) => a.arg + ": " + self.sub_expr(t, prec_test)
  }
}

///|
/// An expression rendered on its own, for assembling a list of pieces.
fn Writer::sub_expr(_self : Writer, e : @ast.Expr, demanded : Int) -> String {
  let w : Writer = { out: StringBuilder(), depth: 0, }
  w.expr(e, demanded)
  w.out.to_string()
}

// ---------------------------------------------------------------------------
// Patterns

///|
fn Writer::pattern(self : Writer, p : @ast.Pattern) -> Unit {
  match p {
    MatchValue(value~, ..) => self.expr(value, prec_bor)
    MatchSingleton(value~, ..) => self.out.write_string(value.to_literal())
    MatchSequence(kind~, patterns~, ..) => {
      let (open, close) = if kind is List { ("[", "]") } else { ("(", ")") }
      self.out.write_string(open)
      for i, q in patterns {
        if i > 0 {
          self.out.write_string(", ")
        }
        self.pattern(q)
      }
      // A one-element tuple pattern needs its comma, as a tuple does.
      if kind is Tuple && patterns.length() == 1 {
        self.out.write_string(",")
      }
      self.out.write_string(close)
    }
    MatchMapping(keys~, patterns~, rest~, ..) => {
      self.out.write_string("{")
      for i, k in keys {
        if i > 0 {
          self.out.write_string(", ")
        }
        self.expr(k, prec_test)
        self.out.write_string(": ")
        self.pattern(patterns[i])
      }
      match rest {
        Some(r) => {
          if !keys.is_empty() {
            self.out.write_string(", ")
          }
          self.out.write_string("**\{r}")
        }
        None => ()
      }
      self.out.write_string("}")
    }
    MatchClass(cls~, patterns~, kwd_attrs~, kwd_patterns~, ..) => {
      self.expr(cls, prec_atom)
      self.out.write_string("(")
      let mut first = true
      for q in patterns {
        if !first {
          self.out.write_string(", ")
        }
        first = false
        self.pattern(q)
      }
      for i, name in kwd_attrs {
        if !first {
          self.out.write_string(", ")
        }
        first = false
        self.out.write_string("\{name}=")
        self.pattern(kwd_patterns[i])
      }
      self.out.write_string(")")
    }
    MatchStar(name~, ..) => {
      let bound = match name {
        Some(n) => n
        None => "_"
      }
      self.out.write_string("*" + bound)
    }
    MatchAs(pattern~, name~, ..) =>
      match (pattern, name) {
        (None, None) => self.out.write_string("_")
        (None, Some(n)) => self.out.write_string(n)
        (Some(q), None) => self.pattern(q)
        (Some(q), Some(n)) => {
          self.pattern(q)
          self.out.write_string(" as \{n}")
        }
      }
    MatchOr(patterns~, ..) =>
      for i, q in patterns {
        if i > 0 {
          self.out.write_string(" | ")
        }
        self.pattern(q)
      }
  }
}
