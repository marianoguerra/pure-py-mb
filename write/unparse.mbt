///|
/// The tree, printed back as Python source.
///
/// The claim it has to meet is a round trip: parsing what this writes gives
/// the tree it was given, for every source in the corpus and the suite. So
/// the layout follows `ast.unparse` -- four spaces of indentation, one
/// statement per line, brackets driven by precedence, constants through
/// `repr` -- but where the two differ in whitespace and nothing else, the
/// round trip is what decides.
///
/// The package links `ast` and `basic` and nothing else: a code generator
/// builds a tree and prints it, and pays for neither the lexer nor the parser.
/// `tools/embed-smoke.sh` is that claim.
pub fn unparse(m : @ast.Module) -> String {
  let w = { out: StringBuilder(), depth: 0, }
  if m.body.is_empty() {
    return ""
  }
  w.statements(m.body)
  w.out.to_string()
}

///|
/// One expression, for a doctest or a message.
pub fn unparse_expr(e : @ast.Expr) -> String {
  let w = { out: StringBuilder(), depth: 0, }
  w.expr(e, prec_tuple)
  w.out.to_string()
}

///|
priv struct Writer {
  out : StringBuilder
  mut depth : Int
}

///|
fn Writer::line(self : Writer, text : String) -> Unit {
  for _ in 0..<self.depth {
    self.out.write_string("    ")
  }
  self.out.write_string(text)
  self.out.write_string("\n")
}

///|
fn Writer::statements(self : Writer, body : Array[@ast.Stmt]) -> Unit {
  if body.is_empty() {
    self.line("pass")
    return
  }
  for s in body {
    self.stmt(s)
  }
}

///|
fn Writer::block(self : Writer, body : Array[@ast.Stmt]) -> Unit {
  self.depth += 1
  self.statements(body)
  self.depth -= 1
}

// ---------------------------------------------------------------------------
// Precedence
//
// The levels of CPython's `_Unparser`, as integers so that "one tighter" is
// addition. A sub-expression is bracketed when its own level is below the
// level its position demands.

///|
let prec_tuple : Int = 0

///|
let prec_yield : Int = 1

///|
let prec_test : Int = 2

///|
let prec_or : Int = 3

///|
let prec_and : Int = 4

///|
let prec_not : Int = 5

///|
let prec_cmp : Int = 6

///|
let prec_bor : Int = 7

///|
let prec_bxor : Int = 8

///|
let prec_band : Int = 9

///|
let prec_shift : Int = 10

///|
let prec_arith : Int = 11

///|
let prec_term : Int = 12

///|
let prec_factor : Int = 13

///|
let prec_power : Int = 14

///|
let prec_await : Int = 15

///|
let prec_atom : Int = 16

///|
fn operator_precedence(op : @ast.Operator) -> Int {
  match op {
    BitOr => prec_bor
    BitXor => prec_bxor
    BitAnd => prec_band
    LShift | RShift => prec_shift
    Add | Sub => prec_arith
    Mult | MatMult | Div | Mod | FloorDiv => prec_term
    Pow => prec_power
  }
}

///|
/// The level at which an expression may be written without brackets.
fn expr_precedence(e : @ast.Expr) -> Int {
  match e {
    // A tuple and a generator always carry their own brackets here, so
    // nothing can ever demand more of them.
    Tuple(..) => prec_atom
    Yield(..) | YieldFrom(..) => prec_yield
    IfExp(..) | Lambda(..) => prec_test
    NamedExpr(..) => prec_tuple
    BoolOp(op=Or, ..) => prec_or
    BoolOp(op=And, ..) => prec_and
    UnaryOp(op=Not, ..) => prec_not
    Compare(..) => prec_cmp
    BinOp(op~, ..) => operator_precedence(op)
    UnaryOp(..) => prec_factor
    Await(..) => prec_await
    Starred(..) => prec_bor
    _ => prec_atom
  }
}

///|
/// Write `e`, bracketed if its level is below `demanded`.
fn Writer::expr(self : Writer, e : @ast.Expr, demanded : Int) -> Unit {
  let need = expr_precedence(e) < demanded
  if need {
    self.out.write_string("(")
  }
  self.raw_expr(e)
  if need {
    self.out.write_string(")")
  }
}

// ---------------------------------------------------------------------------
// Statements

///|
fn Writer::stmt(self : Writer, s : @ast.Stmt) -> Unit {
  match s {
    FunctionDef(name~, args~, body~, decorators~, returns~, is_async~, ..) => {
      for d in decorators {
        self.out_prefix("@")
        self.expr(d, prec_tuple)
        self.out.write_string("\n")
      }
      self.out_prefix(if is_async { "async def " } else { "def " })
      self.out.write_string(name)
      self.out.write_string("(")
      self.arguments(args)
      self.out.write_string(")")
      match returns {
        Some(r) => {
          self.out.write_string(" -> ")
          self.expr(r, prec_test)
        }
        None => ()
      }
      self.out.write_string(":\n")
      self.block(body)
    }
    ClassDef(name~, bases~, keywords~, body~, decorators~, ..) => {
      for d in decorators {
        self.out_prefix("@")
        self.expr(d, prec_tuple)
        self.out.write_string("\n")
      }
      self.out_prefix("class ")
      self.out.write_string(name)
      if !bases.is_empty() || !keywords.is_empty() {
        self.out.write_string("(")
        let mut first = true
        for b in bases {
          if !first {
            self.out.write_string(", ")
          }
          first = false
          self.expr(b, prec_test)
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
      self.out.write_string(":\n")
      self.block(body)
    }
    Return(value~, ..) =>
      match value {
        None => self.line("return")
        Some(v) => {
          self.out_prefix("return ")
          self.expr(v, prec_tuple)
          self.out.write_string("\n")
        }
      }
    Delete(targets~, ..) => {
      self.out_prefix("del ")
      self.comma_exprs(targets, prec_test)
      self.out.write_string("\n")
    }
    Assign(targets~, value~, ..) => {
      self.out_prefix("")
      for t in targets {
        self.expr(t, prec_tuple + 1)
        self.out.write_string(" = ")
      }
      self.expr(value, prec_tuple + 1)
      self.out.write_string("\n")
    }
    AugAssign(target~, op~, value~, ..) => {
      self.out_prefix("")
      self.expr(target, prec_atom)
      self.out.write_string(" \{op.symbol()}= ")
      self.expr(value, prec_tuple + 1)
      self.out.write_string("\n")
    }
    AnnAssign(target~, annotation~, value~, simple~, ..) => {
      self.out_prefix("")
      // CPython brackets a non-simple target so that the tree round-trips:
      // `(x): int` is not the same node as `x: int`.
      if simple {
        self.expr(target, prec_atom)
      } else {
        self.out.write_string("(")
        self.expr(target, prec_tuple)
        self.out.write_string(")")
      }
      self.out.write_string(": ")
      self.expr(annotation, prec_test)
      match value {
        Some(v) => {
          self.out.write_string(" = ")
          self.expr(v, prec_tuple + 1)
        }
        None => ()
      }
      self.out.write_string("\n")
    }
    For(target~, iter~, body~, or_else~, is_async~, ..) => {
      self.out_prefix(if is_async { "async for " } else { "for " })
      self.expr(target, prec_tuple + 1)
      self.out.write_string(" in ")
      self.expr(iter, prec_tuple + 1)
      self.out.write_string(":\n")
      self.block(body)
      self.else_block(or_else)
    }
    While(cond~, body~, or_else~, ..) => {
      self.out_prefix("while ")
      self.expr(cond, prec_tuple)
      self.out.write_string(":\n")
      self.block(body)
      self.else_block(or_else)
    }
    If(cond~, body~, or_else~, ..) => {
      self.out_prefix("if ")
      self.expr(cond, prec_tuple)
      self.out.write_string(":\n")
      self.block(body)
      self.elif_chain(or_else)
    }
    With(items~, body~, is_async~, ..) => {
      self.out_prefix(if is_async { "async with " } else { "with " })
      for i, it in items {
        if i > 0 {
          self.out.write_string(", ")
        }
        self.expr(it.context_expr, prec_test)
        match it.optional_vars {
          Some(v) => {
            self.out.write_string(" as ")
            self.expr(v, prec_atom)
          }
          None => ()
        }
      }
      self.out.write_string(":\n")
      self.block(body)
    }
    Match(subject~, cases~, ..) => {
      self.out_prefix("match ")
      self.expr(subject, prec_tuple + 1)
      self.out.write_string(":\n")
      self.depth += 1
      for c in cases {
        self.out_prefix("case ")
        self.pattern(c.pattern)
        match c.guard_ {
          Some(g) => {
            self.out.write_string(" if ")
            self.expr(g, prec_tuple)
          }
          None => ()
        }
        self.out.write_string(":\n")
        self.block(c.body)
      }
      self.depth -= 1
    }
    Raise(exc~, cause~, ..) => {
      self.out_prefix("raise")
      match exc {
        Some(e) => {
          self.out.write_string(" ")
          self.expr(e, prec_test)
        }
        None => ()
      }
      match cause {
        Some(c) => {
          self.out.write_string(" from ")
          self.expr(c, prec_test)
        }
        None => ()
      }
      self.out.write_string("\n")
    }
    Try(body~, handlers~, or_else~, finalbody~, is_star~, ..) => {
      self.line("try:")
      self.block(body)
      for h in handlers {
        self.out_prefix(if is_star { "except*" } else { "except" })
        match h.type_ {
          Some(t) => {
            self.out.write_string(" ")
            self.expr(t, prec_test)
          }
          None => ()
        }
        match h.name {
          Some(n) => self.out.write_string(" as \{n}")
          None => ()
        }
        self.out.write_string(":\n")
        self.block(h.body)
      }
      self.else_block(or_else)
      if !finalbody.is_empty() {
        self.line("finally:")
        self.block(finalbody)
      }
    }
    Assert(cond~, msg~, ..) => {
      self.out_prefix("assert ")
      self.expr(cond, prec_test)
      match msg {
        Some(m) => {
          self.out.write_string(", ")
          self.expr(m, prec_test)
        }
        None => ()
      }
      self.out.write_string("\n")
    }
    Import(names~, ..) => {
      self.out_prefix("import ")
      for i, a in names {
        if i > 0 {
          self.out.write_string(", ")
        }
        self.out.write_string(a.name)
        match a.asname {
          Some(n) => self.out.write_string(" as \{n}")
          None => ()
        }
      }
      self.out.write_string("\n")
    }
    ImportFrom(module_name~, names~, level~, ..) => {
      self.out_prefix("from ")
      for _ in 0..<level {
        self.out.write_string(".")
      }
      match module_name {
        Some(m) => self.out.write_string(m)
        None => ()
      }
      self.out.write_string(" import ")
      for i, a in names {
        if i > 0 {
          self.out.write_string(", ")
        }
        self.out.write_string(a.name)
        match a.asname {
          Some(n) => self.out.write_string(" as \{n}")
          None => ()
        }
      }
      self.out.write_string("\n")
    }
    Global(names~, ..) => self.line("global " + join(names, ", "))
    Nonlocal(names~, ..) => self.line("nonlocal " + join(names, ", "))
    ExprStmt(value~, ..) => {
      self.out_prefix("")
      self.expr(value, prec_yield)
      self.out.write_string("\n")
    }
    Pass(..) => self.line("pass")
    Break(..) => self.line("break")
    Continue(..) => self.line("continue")
  }
}

///|
/// Indentation, then the text, with no newline: the start of a line that will
/// have expressions written into it.
fn Writer::out_prefix(self : Writer, text : String) -> Unit {
  for _ in 0..<self.depth {
    self.out.write_string("    ")
  }
  self.out.write_string(text)
}

///|
fn Writer::else_block(self : Writer, or_else : Array[@ast.Stmt]) -> Unit {
  if !or_else.is_empty() {
    self.line("else:")
    self.block(or_else)
  }
}

///|
/// `elif` is a nested `If` in `orelse`, and is written back as `elif` when it
/// is the only statement there -- which is exactly when the parser would
/// build the same tree from either spelling.
fn Writer::elif_chain(self : Writer, or_else : Array[@ast.Stmt]) -> Unit {
  if or_else.is_empty() {
    return
  }
  if or_else.length() == 1 && or_else[0] is If(..) {
    match or_else[0] {
      If(cond~, body~, or_else=inner, ..) => {
        self.out_prefix("elif ")
        self.expr(cond, prec_tuple)
        self.out.write_string(":\n")
        self.block(body)
        self.elif_chain(inner)
      }
      _ => ()
    }
    return
  }
  self.line("else:")
  self.block(or_else)
}

///|
fn join(items : Array[String], sep : String) -> String {
  let out = StringBuilder()
  for i, s in items {
    if i > 0 {
      out.write_string(sep)
    }
    out.write_string(s)
  }
  out.to_string()
}

///|
fn Writer::comma_exprs(
  self : Writer,
  items : Array[@ast.Expr],
  demanded : Int,
) -> Unit {
  for i, e in items {
    if i > 0 {
      self.out.write_string(", ")
    }
    self.expr(e, demanded)
  }
}
