///|
/// Constructors for a code generator.
///
/// A generator builds a tree and prints it with `write`; it has no source, so
/// it has no positions. Every builder here supplies `@basic.nowhere` and
/// sensible defaults, so that `Expr::call(Expr::name("print"), [Expr::str("hi")])`
/// is a whole statement's worth of tree.
///
/// The builders are also what keeps `ast` honest as a package a consumer can
/// use alone: `tools/embed-smoke.sh` builds a program from them and checks
/// that doing so links neither the lexer, the parser, the checker nor the
/// evaluator.
pub fn Expr::name(id : String, ctx? : ExprContext = Load) -> Expr {
  Name(id~, ctx~, span=@basic.nowhere)
}

///|
pub fn Expr::int(n : Int) -> Expr {
  Constant(value=Int(BigInt::from_int(n)), span=@basic.nowhere)
}

///|
pub fn Expr::bigint(n : BigInt) -> Expr {
  Constant(value=Int(n), span=@basic.nowhere)
}

///|
pub fn Expr::float(d : Double) -> Expr {
  Constant(value=Float(d), span=@basic.nowhere)
}

///|
pub fn Expr::str(s : String) -> Expr {
  Constant(value=Str(s), span=@basic.nowhere)
}

///|
pub fn Expr::bool(b : Bool) -> Expr {
  Constant(value=Bool(b), span=@basic.nowhere)
}

///|
pub fn Expr::none() -> Expr {
  Constant(value=None, span=@basic.nowhere)
}

///|
pub fn Expr::call(
  func : Expr,
  args : Array[Expr],
  keywords? : Array[Keyword] = [],
) -> Expr {
  Call(func~, args~, keywords~, span=@basic.nowhere)
}

///|
pub fn Expr::attribute(
  value : Expr,
  attr : String,
  ctx? : ExprContext = Load,
) -> Expr {
  Attribute(value~, attr~, ctx~, span=@basic.nowhere)
}

///|
pub fn Expr::subscript(
  value : Expr,
  slice : Expr,
  ctx? : ExprContext = Load,
) -> Expr {
  Subscript(value~, slice~, ctx~, span=@basic.nowhere)
}

///|
pub fn Expr::binop(left : Expr, op : Operator, right : Expr) -> Expr {
  BinOp(left~, op~, right~, span=@basic.nowhere)
}

///|
pub fn Expr::compare(left : Expr, op : CmpOp, right : Expr) -> Expr {
  Compare(left~, ops=[op], comparators=[right], span=@basic.nowhere)
}

///|
pub fn Expr::bool_op(op : BoolOp, values : Array[Expr]) -> Expr {
  BoolOp(op~, values~, span=@basic.nowhere)
}

///|
pub fn Expr::not_(e : Expr) -> Expr {
  UnaryOp(op=Not, operand=e, span=@basic.nowhere)
}

///|
pub fn Expr::neg(e : Expr) -> Expr {
  UnaryOp(op=USub, operand=e, span=@basic.nowhere)
}

///|
pub fn Expr::if_exp(cond : Expr, body : Expr, or_else : Expr) -> Expr {
  IfExp(cond~, body~, or_else~, span=@basic.nowhere)
}

///|
pub fn Expr::list(elts : Array[Expr], ctx? : ExprContext = Load) -> Expr {
  List(elts~, ctx~, span=@basic.nowhere)
}

///|
pub fn Expr::tuple(elts : Array[Expr], ctx? : ExprContext = Load) -> Expr {
  Tuple(elts~, ctx~, span=@basic.nowhere)
}

///|
pub fn Expr::dict(entries : Array[(Expr, Expr)]) -> Expr {
  Dict(
    keys=entries.map(fn(e) { Some(e.0) }),
    values=entries.map(fn(e) { e.1 }),
    span=@basic.nowhere,
  )
}

///|
pub fn Expr::lambda(params : Array[String], body : Expr) -> Expr {
  Lambda(args=arguments(params), body~, span=@basic.nowhere)
}

///|
/// A plain parameter list: names, no defaults, no annotations, no stars.
pub fn arguments(params : Array[String]) -> Arguments {
  {
    posonlyargs: [],
    args: params.map(fn(p) {
      { arg: p, annotation: None, span: @basic.nowhere, }
    }),
    vararg: None,
    kwonlyargs: [],
    kw_defaults: [],
    kwarg: None,
    defaults: [],
  }
}

///|
pub fn Stmt::expr_stmt(e : Expr) -> Stmt {
  ExprStmt(value=e, span=@basic.nowhere)
}

///|
pub fn Stmt::assign(target : String, value : Expr) -> Stmt {
  Assign(targets=[Expr::name(target, ctx=Store)], value~, span=@basic.nowhere)
}

///|
pub fn Stmt::return_(value? : Expr) -> Stmt {
  Return(value~, span=@basic.nowhere)
}

///|
pub fn Stmt::pass() -> Stmt {
  Pass(span=@basic.nowhere)
}

///|
pub fn Stmt::if_(
  cond : Expr,
  body : Array[Stmt],
  or_else? : Array[Stmt] = [],
) -> Stmt {
  If(cond~, body~, or_else~, span=@basic.nowhere)
}

///|
pub fn Stmt::def_(
  name : String,
  params : Array[String],
  body : Array[Stmt],
) -> Stmt {
  FunctionDef(
    name~,
    args=arguments(params),
    body~,
    decorators=[],
    returns=None,
    is_async=false,
    span=@basic.nowhere,
  )
}

///|
/// A PurePy dataclass: `@dataclass` on a class whose body is `x: Any` for
/// each field, with an optional base class. That is the only class form
/// PurePy accepts, so it is the only one the builder offers.
pub fn Stmt::dataclass(
  name : String,
  fields : Array[String],
  base? : String,
) -> Stmt {
  ClassDef(
    name~,
    bases=match base {
      None => []
      Some(b) => [Expr::name(b)]
    },
    keywords=[],
    body=fields.map(fn(f) {
      Stmt::AnnAssign(
        target=Expr::name(f, ctx=Store),
        annotation=Expr::name("Any"),
        value=None,
        simple=true,
        span=@basic.nowhere,
      )
    }),
    decorators=[Expr::name("dataclass")],
    span=@basic.nowhere,
  )
}

///|
pub fn Stmt::match_(subject : Expr, cases : Array[MatchCase]) -> Stmt {
  Match(subject~, cases~, span=@basic.nowhere)
}

///|
pub fn Stmt::import_(names : Array[String]) -> Stmt {
  Import(
    names=names.map(fn(n) { { name: n, asname: None, span: @basic.nowhere, } }),
    span=@basic.nowhere,
  )
}

///|
pub fn Stmt::from_import(module_name : String, names : Array[String]) -> Stmt {
  ImportFrom(
    module_name=Some(module_name),
    names=names.map(fn(n) { { name: n, asname: None, span: @basic.nowhere, } }),
    level=0,
    span=@basic.nowhere,
  )
}

///|
pub fn case_(pattern : Pattern, body : Array[Stmt], when? : Expr) -> MatchCase {
  { pattern, guard_: when, body, }
}

///|
pub fn Pattern::capture(name : String) -> Pattern {
  MatchAs(pattern=None, name=Some(name), span=@basic.nowhere)
}

///|
pub fn Pattern::wildcard() -> Pattern {
  MatchAs(pattern=None, name=None, span=@basic.nowhere)
}

///|
pub fn Pattern::literal(c : Constant) -> Pattern {
  MatchValue(value=Constant(value=c, span=@basic.nowhere), span=@basic.nowhere)
}

///|
pub fn Pattern::constr(
  cls : String,
  patterns : Array[Pattern],
  keywords? : Array[(String, Pattern)] = [],
) -> Pattern {
  MatchClass(
    cls=Expr::name(cls),
    patterns~,
    kwd_attrs=keywords.map(fn(k) { k.0 }),
    kwd_patterns=keywords.map(fn(k) { k.1 }),
    span=@basic.nowhere,
  )
}

///|
pub fn Pattern::sequence(kind : SeqKind, patterns : Array[Pattern]) -> Pattern {
  MatchSequence(kind~, patterns~, span=@basic.nowhere)
}

///|
pub fn module_of(body : Array[Stmt]) -> Module {
  { body, span: @basic.nowhere, }
}
