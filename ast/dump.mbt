///|
/// The canonical dump of a tree.
///
/// The format exists so that it can be implemented TWICE -- here and in
/// `tools/pyast_dump.py` over CPython's `ast` -- and the two compared over
/// every source in the suite. So it is defined precisely and kept dull:
///
///   * One node per line, indented two spaces per level of nesting.
///   * A node's line is its kind, then its scalar fields as `name=value`,
///     in the order they are declared here (which is `Python.asdl`'s order).
///   * A field holding a node, an optional node or a list is a line of its
///     own, `name:`, at the next level, with its contents below that. An
///     absent optional is `name: -`; an empty list is `name:` with nothing
///     under it.
///   * Scalars: an identifier bare, an enumerated value by CPython's class
///     name (`Load`, `Add`, `Lt`), a boolean as `True`/`False`, an integer in
///     decimal, a string as Python's `repr`, a float as Python's `repr`, and
///     an absent optional scalar as `-`.
///   * With `pos=true`, a node's line ends with ` @l:c-l:c`, the columns in
///     CODE POINTS. The Python side converts `col_offset` from UTF-8 bytes.
///
/// This is not `ast.dump`'s format. `ast.dump` is a Python expression whose
/// re-parsing is the only way to compare it structurally, and it renders a
/// constant through Python's own `repr` of an arbitrary object. Defining our
/// own costs one Python script and buys a line-oriented diff.
pub fn dump(m : Module, pos~ : Bool = false) -> String {
  let d = { out: StringBuilder(), pos }
  d.node("Module", [], 0, m.span)
  d.field_stmts("body", m.body, 1)
  d.out.to_string()
}

///|
priv struct Dumper {
  out : StringBuilder
  pos : Bool
}

///|
fn Dumper::indent(self : Dumper, depth : Int) -> Unit {
  for _ in 0..<depth {
    self.out.write_string("  ")
  }
}

///|
/// A node's own line: its kind, its scalar fields, and its span when asked.
fn Dumper::node(
  self : Dumper,
  kind : String,
  scalars : Array[(String, String)],
  depth : Int,
  span : @basic.Span,
) -> Unit {
  self.indent(depth)
  self.out.write_string(kind)
  for s in scalars {
    self.out.write_string(" \{s.0}=\{s.1}")
  }
  if self.pos {
    self.out.write_string(" @\{span.to_display()}")
  }
  self.out.write_string("\n")
}

///|
/// A field's introducing line, `name:`, optionally with an inline `-`.
fn Dumper::field(self : Dumper, name : String, depth : Int, absent~ : Bool = false) -> Unit {
  self.indent(depth)
  self.out.write_string(if absent { "\{name}: -\n" } else { "\{name}:\n" })
}

// ---------------------------------------------------------------------------
// Scalars

///|
fn opt_id(s : String?) -> String {
  match s {
    Some(x) => x
    None => "-"
  }
}

///|
fn bool_text(b : Bool) -> String {
  if b {
    "True"
  } else {
    "False"
  }
}

///|
/// A constant, exactly as Python's `repr` writes it.
pub fn Constant::to_literal(self : Constant) -> String {
  match self {
    Int(n) => n.to_string()
    Float(d) => @basic.py_float_repr(d)
    Complex(d) => @basic.py_float_repr(d) + "j"
    Str(s) => @basic.py_repr(s)
    Bytes(b) => @basic.py_bytes_repr(b)
    Bool(b) => bool_text(b)
    None => "None"
    Ellipsis => "Ellipsis"
  }
}

// ---------------------------------------------------------------------------
// Statements

///|
fn Dumper::field_stmts(
  self : Dumper,
  name : String,
  body : Array[Stmt],
  depth : Int,
) -> Unit {
  self.field(name, depth)
  for s in body {
    self.stmt(s, depth + 1)
  }
}

///|
fn Dumper::field_exprs(
  self : Dumper,
  name : String,
  items : Array[Expr],
  depth : Int,
) -> Unit {
  self.field(name, depth)
  for e in items {
    self.expr(e, depth + 1)
  }
}

///|
fn Dumper::field_expr(self : Dumper, name : String, e : Expr, depth : Int) -> Unit {
  self.field(name, depth)
  self.expr(e, depth + 1)
}

///|
fn Dumper::field_opt_expr(
  self : Dumper,
  name : String,
  e : Expr?,
  depth : Int,
) -> Unit {
  match e {
    None => self.field(name, depth, absent=true)
    Some(x) => {
      self.field(name, depth)
      self.expr(x, depth + 1)
    }
  }
}

///|
fn Dumper::stmt(self : Dumper, s : Stmt, depth : Int) -> Unit {
  let d = depth + 1
  match s {
    FunctionDef(name~, args~, body~, decorators~, returns~, is_async~, span~) => {
      self.node(
        "FunctionDef",
        [("name", name), ("is_async", bool_text(is_async))],
        depth,
        span,
      )
      self.field("args", d)
      self.arguments(args, d + 1)
      self.field_stmts("body", body, d)
      self.field_exprs("decorator_list", decorators, d)
      self.field_opt_expr("returns", returns, d)
    }
    ClassDef(name~, bases~, keywords~, body~, decorators~, span~) => {
      self.node("ClassDef", [("name", name)], depth, span)
      self.field_exprs("bases", bases, d)
      self.field("keywords", d)
      for k in keywords {
        self.keyword(k, d + 1)
      }
      self.field_stmts("body", body, d)
      self.field_exprs("decorator_list", decorators, d)
    }
    Return(value~, span~) => {
      self.node("Return", [], depth, span)
      self.field_opt_expr("value", value, d)
    }
    Delete(targets~, span~) => {
      self.node("Delete", [], depth, span)
      self.field_exprs("targets", targets, d)
    }
    Assign(targets~, value~, span~) => {
      self.node("Assign", [], depth, span)
      self.field_exprs("targets", targets, d)
      self.field_expr("value", value, d)
    }
    AugAssign(target~, op~, value~, span~) => {
      self.node("AugAssign", [("op", op.name())], depth, span)
      self.field_expr("target", target, d)
      self.field_expr("value", value, d)
    }
    AnnAssign(target~, annotation~, value~, simple~, span~) => {
      self.node("AnnAssign", [("simple", bool_text(simple))], depth, span)
      self.field_expr("target", target, d)
      self.field_expr("annotation", annotation, d)
      self.field_opt_expr("value", value, d)
    }
    For(target~, iter~, body~, or_else~, is_async~, span~) => {
      self.node("For", [("is_async", bool_text(is_async))], depth, span)
      self.field_expr("target", target, d)
      self.field_expr("iter", iter, d)
      self.field_stmts("body", body, d)
      self.field_stmts("orelse", or_else, d)
    }
    While(cond~, body~, or_else~, span~) => {
      self.node("While", [], depth, span)
      self.field_expr("test", cond, d)
      self.field_stmts("body", body, d)
      self.field_stmts("orelse", or_else, d)
    }
    If(cond~, body~, or_else~, span~) => {
      self.node("If", [], depth, span)
      self.field_expr("test", cond, d)
      self.field_stmts("body", body, d)
      self.field_stmts("orelse", or_else, d)
    }
    With(items~, body~, is_async~, span~) => {
      self.node("With", [("is_async", bool_text(is_async))], depth, span)
      self.field("items", d)
      for it in items {
        self.with_item(it, d + 1)
      }
      self.field_stmts("body", body, d)
    }
    Match(subject~, cases~, span~) => {
      self.node("Match", [], depth, span)
      self.field_expr("subject", subject, d)
      self.field("cases", d)
      for c in cases {
        self.match_case(c, d + 1)
      }
    }
    Raise(exc~, cause~, span~) => {
      self.node("Raise", [], depth, span)
      self.field_opt_expr("exc", exc, d)
      self.field_opt_expr("cause", cause, d)
    }
    Try(body~, handlers~, or_else~, finalbody~, is_star~, span~) => {
      self.node("Try", [("is_star", bool_text(is_star))], depth, span)
      self.field_stmts("body", body, d)
      self.field("handlers", d)
      for h in handlers {
        self.handler(h, d + 1)
      }
      self.field_stmts("orelse", or_else, d)
      self.field_stmts("finalbody", finalbody, d)
    }
    Assert(cond~, msg~, span~) => {
      self.node("Assert", [], depth, span)
      self.field_expr("test", cond, d)
      self.field_opt_expr("msg", msg, d)
    }
    Import(names~, span~) => {
      self.node("Import", [], depth, span)
      self.field("names", d)
      for a in names {
        self.import_alias(a, d + 1)
      }
    }
    ImportFrom(module_name~, names~, level~, span~) => {
      self.node(
        "ImportFrom",
        [("module", opt_id(module_name)), ("level", level.to_string())],
        depth,
        span,
      )
      self.field("names", d)
      for a in names {
        self.import_alias(a, d + 1)
      }
    }
    Global(names~, span~) =>
      self.node("Global", [("names", id_list(names))], depth, span)
    Nonlocal(names~, span~) =>
      self.node("Nonlocal", [("names", id_list(names))], depth, span)
    ExprStmt(value~, span~) => {
      self.node("Expr", [], depth, span)
      self.field_expr("value", value, d)
    }
    Pass(span~) => self.node("Pass", [], depth, span)
    Break(span~) => self.node("Break", [], depth, span)
    Continue(span~) => self.node("Continue", [], depth, span)
  }
}

///|
fn id_list(names : Array[String]) -> String {
  let out = StringBuilder()
  out.write_char('[')
  for i, n in names {
    if i > 0 {
      out.write_char(' ')
    }
    out.write_string(n)
  }
  out.write_char(']')
  out.to_string()
}

// ---------------------------------------------------------------------------
// Expressions

///|
fn Dumper::expr(self : Dumper, e : Expr, depth : Int) -> Unit {
  let d = depth + 1
  match e {
    BoolOp(op~, values~, span~) => {
      self.node("BoolOp", [("op", op.name())], depth, span)
      self.field_exprs("values", values, d)
    }
    NamedExpr(target~, value~, span~) => {
      self.node("NamedExpr", [], depth, span)
      self.field_expr("target", target, d)
      self.field_expr("value", value, d)
    }
    BinOp(left~, op~, right~, span~) => {
      self.node("BinOp", [("op", op.name())], depth, span)
      self.field_expr("left", left, d)
      self.field_expr("right", right, d)
    }
    UnaryOp(op~, operand~, span~) => {
      self.node("UnaryOp", [("op", op.name())], depth, span)
      self.field_expr("operand", operand, d)
    }
    Lambda(args~, body~, span~) => {
      self.node("Lambda", [], depth, span)
      self.field("args", d)
      self.arguments(args, d + 1)
      self.field_expr("body", body, d)
    }
    IfExp(cond~, body~, or_else~, span~) => {
      self.node("IfExp", [], depth, span)
      self.field_expr("test", cond, d)
      self.field_expr("body", body, d)
      self.field_expr("orelse", or_else, d)
    }
    Dict(keys~, values~, span~) => {
      self.node("Dict", [], depth, span)
      self.field("keys", d)
      for k in keys {
        match k {
          None => {
            self.indent(d + 1)
            self.out.write_string("-\n")
          }
          Some(x) => self.expr(x, d + 1)
        }
      }
      self.field_exprs("values", values, d)
    }
    Set(elts~, span~) => {
      self.node("Set", [], depth, span)
      self.field_exprs("elts", elts, d)
    }
    ListComp(elt~, generators~, span~) => {
      self.node("ListComp", [], depth, span)
      self.field_expr("elt", elt, d)
      self.comprehensions(generators, d)
    }
    SetComp(elt~, generators~, span~) => {
      self.node("SetComp", [], depth, span)
      self.field_expr("elt", elt, d)
      self.comprehensions(generators, d)
    }
    DictComp(key~, value~, generators~, span~) => {
      self.node("DictComp", [], depth, span)
      self.field_expr("key", key, d)
      self.field_expr("value", value, d)
      self.comprehensions(generators, d)
    }
    GeneratorExp(elt~, generators~, span~) => {
      self.node("GeneratorExp", [], depth, span)
      self.field_expr("elt", elt, d)
      self.comprehensions(generators, d)
    }
    Await(value~, span~) => {
      self.node("Await", [], depth, span)
      self.field_expr("value", value, d)
    }
    Yield(value~, span~) => {
      self.node("Yield", [], depth, span)
      self.field_opt_expr("value", value, d)
    }
    YieldFrom(value~, span~) => {
      self.node("YieldFrom", [], depth, span)
      self.field_expr("value", value, d)
    }
    Compare(left~, ops~, comparators~, span~) => {
      self.node("Compare", [("ops", op_list(ops))], depth, span)
      self.field_expr("left", left, d)
      self.field_exprs("comparators", comparators, d)
    }
    Call(func~, args~, keywords~, span~) => {
      self.node("Call", [], depth, span)
      self.field_expr("func", func, d)
      self.field_exprs("args", args, d)
      self.field("keywords", d)
      for k in keywords {
        self.keyword(k, d + 1)
      }
    }
    JoinedStr(raw~, span~) =>
      self.node("JoinedStr", [("raw", @basic.py_repr(raw))], depth, span)
    Constant(value~, span~) =>
      self.node("Constant", [("value", value.to_literal())], depth, span)
    Attribute(value~, attr~, ctx~, span~) => {
      self.node("Attribute", [("attr", attr), ("ctx", ctx.name())], depth, span)
      self.field_expr("value", value, d)
    }
    Subscript(value~, slice~, ctx~, span~) => {
      self.node("Subscript", [("ctx", ctx.name())], depth, span)
      self.field_expr("value", value, d)
      self.field_expr("slice", slice, d)
    }
    Starred(value~, ctx~, span~) => {
      self.node("Starred", [("ctx", ctx.name())], depth, span)
      self.field_expr("value", value, d)
    }
    Name(id~, ctx~, span~) =>
      self.node("Name", [("id", id), ("ctx", ctx.name())], depth, span)
    List(elts~, ctx~, span~) => {
      self.node("List", [("ctx", ctx.name())], depth, span)
      self.field_exprs("elts", elts, d)
    }
    Tuple(elts~, ctx~, span~) => {
      self.node("Tuple", [("ctx", ctx.name())], depth, span)
      self.field_exprs("elts", elts, d)
    }
    Slice(lower~, upper~, step~, span~) => {
      self.node("Slice", [], depth, span)
      self.field_opt_expr("lower", lower, d)
      self.field_opt_expr("upper", upper, d)
      self.field_opt_expr("step", step, d)
    }
  }
}

///|
fn op_list(ops : Array[CmpOp]) -> String {
  let out = StringBuilder()
  out.write_char('[')
  for i, o in ops {
    if i > 0 {
      out.write_char(' ')
    }
    out.write_string(o.name())
  }
  out.write_char(']')
  out.to_string()
}

// ---------------------------------------------------------------------------
// The helper nodes

///|
fn Dumper::comprehensions(
  self : Dumper,
  gens : Array[Comprehension],
  depth : Int,
) -> Unit {
  self.field("generators", depth)
  for g in gens {
    self.node(
      "comprehension",
      [("is_async", bool_text(g.is_async))],
      depth + 1,
      g.target.span(),
    )
    self.field_expr("target", g.target, depth + 2)
    self.field_expr("iter", g.iter, depth + 2)
    self.field_exprs("ifs", g.ifs, depth + 2)
  }
}

///|
fn Dumper::arguments(self : Dumper, a : Arguments, depth : Int) -> Unit {
  self.indent(depth)
  self.out.write_string("arguments\n")
  let d = depth + 1
  self.field("posonlyargs", d)
  for x in a.posonlyargs {
    self.arg(x, d + 1)
  }
  self.field("args", d)
  for x in a.args {
    self.arg(x, d + 1)
  }
  match a.vararg {
    None => self.field("vararg", d, absent=true)
    Some(x) => {
      self.field("vararg", d)
      self.arg(x, d + 1)
    }
  }
  self.field("kwonlyargs", d)
  for x in a.kwonlyargs {
    self.arg(x, d + 1)
  }
  self.field("kw_defaults", d)
  for x in a.kw_defaults {
    match x {
      None => {
        self.indent(d + 1)
        self.out.write_string("-\n")
      }
      Some(e) => self.expr(e, d + 1)
    }
  }
  match a.kwarg {
    None => self.field("kwarg", d, absent=true)
    Some(x) => {
      self.field("kwarg", d)
      self.arg(x, d + 1)
    }
  }
  self.field_exprs("defaults", a.defaults, d)
}

///|
fn Dumper::arg(self : Dumper, a : Arg, depth : Int) -> Unit {
  self.node("arg", [("arg", a.arg)], depth, a.span)
  self.field_opt_expr("annotation", a.annotation, depth + 1)
}

///|
fn Dumper::keyword(self : Dumper, k : Keyword, depth : Int) -> Unit {
  self.node("keyword", [("arg", opt_id(k.arg))], depth, k.span)
  self.field_expr("value", k.value, depth + 1)
}

///|
fn Dumper::import_alias(self : Dumper, a : Alias, depth : Int) -> Unit {
  self.node(
    "alias",
    [("name", a.name), ("asname", opt_id(a.asname))],
    depth,
    a.span,
  )
}

///|
fn Dumper::with_item(self : Dumper, w : WithItem, depth : Int) -> Unit {
  self.indent(depth)
  self.out.write_string("withitem\n")
  self.field_expr("context_expr", w.context_expr, depth + 1)
  self.field_opt_expr("optional_vars", w.optional_vars, depth + 1)
}

///|
fn Dumper::handler(self : Dumper, h : ExceptHandler, depth : Int) -> Unit {
  self.node("ExceptHandler", [("name", opt_id(h.name))], depth, h.span)
  self.field_opt_expr("type", h.type_, depth + 1)
  self.field_stmts("body", h.body, depth + 1)
}

///|
fn Dumper::match_case(self : Dumper, c : MatchCase, depth : Int) -> Unit {
  self.indent(depth)
  self.out.write_string("match_case\n")
  let d = depth + 1
  self.field("pattern", d)
  self.pattern(c.pattern, d + 1)
  self.field_opt_expr("guard", c.guard_, d)
  self.field_stmts("body", c.body, d)
}

// ---------------------------------------------------------------------------
// Patterns

///|
fn Dumper::field_patterns(
  self : Dumper,
  name : String,
  ps : Array[Pattern],
  depth : Int,
) -> Unit {
  self.field(name, depth)
  for p in ps {
    self.pattern(p, depth + 1)
  }
}

///|
fn Dumper::pattern(self : Dumper, p : Pattern, depth : Int) -> Unit {
  let d = depth + 1
  match p {
    MatchValue(value~, span~) => {
      self.node("MatchValue", [], depth, span)
      self.field_expr("value", value, d)
    }
    MatchSingleton(value~, span~) =>
      self.node("MatchSingleton", [("value", value.to_literal())], depth, span)
    MatchSequence(kind~, patterns~, span~) => {
      self.node("MatchSequence", [("kind", kind.name())], depth, span)
      self.field_patterns("patterns", patterns, d)
    }
    MatchMapping(keys~, patterns~, rest~, span~) => {
      self.node("MatchMapping", [("rest", opt_id(rest))], depth, span)
      self.field_exprs("keys", keys, d)
      self.field_patterns("patterns", patterns, d)
    }
    MatchClass(cls~, patterns~, kwd_attrs~, kwd_patterns~, span~) => {
      self.node(
        "MatchClass",
        [("kwd_attrs", id_list(kwd_attrs))],
        depth,
        span,
      )
      self.field_expr("cls", cls, d)
      self.field_patterns("patterns", patterns, d)
      self.field_patterns("kwd_patterns", kwd_patterns, d)
    }
    MatchStar(name~, span~) =>
      self.node("MatchStar", [("name", opt_id(name))], depth, span)
    MatchAs(pattern~, name~, span~) => {
      self.node("MatchAs", [("name", opt_id(name))], depth, span)
      match pattern {
        None => self.field("pattern", d, absent=true)
        Some(x) => {
          self.field("pattern", d)
          self.pattern(x, d + 1)
        }
      }
    }
    MatchOr(patterns~, span~) => {
      self.node("MatchOr", [], depth, span)
      self.field_patterns("patterns", patterns, d)
    }
  }
}
