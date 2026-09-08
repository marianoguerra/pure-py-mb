///|
/// The abstract syntax tree.
///
/// It is CPython's, node for node and field for field, following
/// `Parser/Python.asdl` for every construct PurePy needs to NAME -- to accept,
/// or to reject with the right message. Being CPython's is the point: the
/// reference checker walks CPython nodes, so a checker written against this
/// tree can be put beside `statements.py` and read line for line, and the AST
/// oracle can compare our dump against `ast.dump` over the whole suite.
///
/// It is typed rather than stringly: operators, expression contexts and
/// pattern kinds are enums, not strings.
///
/// Five deliberate departures from `Python.asdl`, each earning its keep:
///
///   * `MatchSequence` carries the bracket it was written with. The spec
///     distinguishes a list pattern from a tuple pattern and CPython does not,
///     so the reference recovers the bracket from the source text; this port
///     records it where it is known, in the parser.
///   * Async is a FLAG on `FunctionDef`, `For` and `With`, not three more node
///     kinds. The sieve's message is `async prohibited` either way.
///   * `Constant` is a typed enum, not a Python object. `Complex` and `Bytes`
///     are arms so that the sieve can say "complex literals prohibited".
///   * An f-string is `JoinedStr` with its text unparsed. The sieve rejects
///     f-strings as not yet supported (#55); when that changes, the parts are
///     parsed here and nothing else moves.
///   * Positions are a `Span` of two `Pos`, and the column counts CODE POINTS.
///     CPython's `col_offset` counts UTF-8 bytes; `Source::byte_col` converts,
///     and only where a message in the reference's format needs it.
///
/// Deliberately absent: `type_comment`, `type_ignores`, `type_params`,
/// `TemplateStr` and `Interpolation`. PurePy is Python 3.12 and PEP 695 syntax
/// is a syntax error here.
pub(all) struct Module {
  body : Array[Stmt]
  span : @basic.Span
} derive(Eq, Debug)

///|
pub(all) enum Stmt {
  FunctionDef(
    name~ : String,
    args~ : Arguments,
    body~ : Array[Stmt],
    decorators~ : Array[Expr],
    returns~ : Expr?,
    is_async~ : Bool,
    span~ : @basic.Span
  )
  ClassDef(
    name~ : String,
    bases~ : Array[Expr],
    keywords~ : Array[Keyword],
    body~ : Array[Stmt],
    decorators~ : Array[Expr],
    span~ : @basic.Span
  )
  Return(value~ : Expr?, span~ : @basic.Span)
  Delete(targets~ : Array[Expr], span~ : @basic.Span)
  Assign(targets~ : Array[Expr], value~ : Expr, span~ : @basic.Span)
  AugAssign(target~ : Expr, op~ : Operator, value~ : Expr, span~ : @basic.Span)
  AnnAssign(
    target~ : Expr,
    annotation~ : Expr,
    value~ : Expr?,
    simple~ : Bool,
    span~ : @basic.Span
  )
  For(
    target~ : Expr,
    iter~ : Expr,
    body~ : Array[Stmt],
    or_else~ : Array[Stmt],
    is_async~ : Bool,
    span~ : @basic.Span
  )
  While(
    cond~ : Expr,
    body~ : Array[Stmt],
    or_else~ : Array[Stmt],
    span~ : @basic.Span
  )
  If(
    cond~ : Expr,
    body~ : Array[Stmt],
    or_else~ : Array[Stmt],
    span~ : @basic.Span
  )
  With(
    items~ : Array[WithItem],
    body~ : Array[Stmt],
    is_async~ : Bool,
    span~ : @basic.Span
  )
  Match(subject~ : Expr, cases~ : Array[MatchCase], span~ : @basic.Span)
  Raise(exc~ : Expr?, cause~ : Expr?, span~ : @basic.Span)
  Try(
    body~ : Array[Stmt],
    handlers~ : Array[ExceptHandler],
    or_else~ : Array[Stmt],
    finalbody~ : Array[Stmt],
    is_star~ : Bool,
    span~ : @basic.Span
  )
  Assert(cond~ : Expr, msg~ : Expr?, span~ : @basic.Span)
  Import(names~ : Array[Alias], span~ : @basic.Span)
  ImportFrom(
    module_name~ : String?,
    names~ : Array[Alias],
    level~ : Int,
    span~ : @basic.Span
  )
  Global(names~ : Array[String], span~ : @basic.Span)
  Nonlocal(names~ : Array[String], span~ : @basic.Span)
  ExprStmt(value~ : Expr, span~ : @basic.Span)
  Pass(span~ : @basic.Span)
  Break(span~ : @basic.Span)
  Continue(span~ : @basic.Span)
} derive(Eq, Debug)

///|
pub(all) enum Expr {
  BoolOp(op~ : BoolOp, values~ : Array[Expr], span~ : @basic.Span)
  NamedExpr(target~ : Expr, value~ : Expr, span~ : @basic.Span)
  BinOp(left~ : Expr, op~ : Operator, right~ : Expr, span~ : @basic.Span)
  UnaryOp(op~ : UnaryOp, operand~ : Expr, span~ : @basic.Span)
  Lambda(args~ : Arguments, body~ : Expr, span~ : @basic.Span)
  IfExp(cond~ : Expr, body~ : Expr, or_else~ : Expr, span~ : @basic.Span)
  /// A `None` key is `**e` unpacking, as in the ASDL.
  Dict(keys~ : Array[Expr?], values~ : Array[Expr], span~ : @basic.Span)
  Set(elts~ : Array[Expr], span~ : @basic.Span)
  ListComp(elt~ : Expr, generators~ : Array[Comprehension], span~ : @basic.Span)
  SetComp(elt~ : Expr, generators~ : Array[Comprehension], span~ : @basic.Span)
  DictComp(
    key~ : Expr,
    value~ : Expr,
    generators~ : Array[Comprehension],
    span~ : @basic.Span
  )
  GeneratorExp(
    elt~ : Expr,
    generators~ : Array[Comprehension],
    span~ : @basic.Span
  )
  Await(value~ : Expr, span~ : @basic.Span)
  Yield(value~ : Expr?, span~ : @basic.Span)
  YieldFrom(value~ : Expr, span~ : @basic.Span)
  Compare(
    left~ : Expr,
    ops~ : Array[CmpOp],
    comparators~ : Array[Expr],
    span~ : @basic.Span
  )
  Call(
    func~ : Expr,
    args~ : Array[Expr],
    keywords~ : Array[Keyword],
    span~ : @basic.Span
  )
  /// An f-string, its parts unparsed (#55). `raw` is the whole literal.
  /// An f-string.
  ///
  /// `raw` is the whole adjacent-string group as it was written, which is what
  /// `dump` prints and what `unparse` writes back: CPython's own dump of a
  /// `JoinedStr` is a tree of `Constant` and `FormattedValue`, and this port's
  /// AST oracle compares the source segment instead (see `tools/pyast_dump.py`).
  /// Keeping `raw` is what keeps that comparison meaningful.
  ///
  /// `parts` is the same literal taken apart, and is what everything that
  /// LOOKS INSIDE an f-string uses -- free variables, the checker, the
  /// evaluator. It is empty for a group that has no f-string in it, which
  /// cannot happen, and it carries the holes as real expressions with real
  /// positions in the file.
  JoinedStr(raw~ : String, parts~ : Array[FStringPart], span~ : @basic.Span)
  Constant(value~ : Constant, span~ : @basic.Span)
  Attribute(
    value~ : Expr,
    attr~ : String,
    ctx~ : ExprContext,
    span~ : @basic.Span
  )
  Subscript(
    value~ : Expr,
    slice~ : Expr,
    ctx~ : ExprContext,
    span~ : @basic.Span
  )
  Starred(value~ : Expr, ctx~ : ExprContext, span~ : @basic.Span)
  Name(id~ : String, ctx~ : ExprContext, span~ : @basic.Span)
  List(elts~ : Array[Expr], ctx~ : ExprContext, span~ : @basic.Span)
  Tuple(elts~ : Array[Expr], ctx~ : ExprContext, span~ : @basic.Span)
  Slice(lower~ : Expr?, upper~ : Expr?, step~ : Expr?, span~ : @basic.Span)
} derive(Eq, Debug)

///|
/// A literal's value. `Complex` keeps only the imaginary part: a Python
/// complex LITERAL is always `0+bj`, and the sieve rejects it before anything
/// needs the real part.
pub(all) enum Constant {
  Int(BigInt)
  Float(Double)
  Complex(Double)
  Str(String)
  Bytes(Bytes)
  Bool(Bool)
  None
  Ellipsis
} derive(Eq, Debug)

///|
pub(all) enum ExprContext {
  Load
  Store
  Del
} derive(Eq, Debug)

///|
pub(all) enum BoolOp {
  And
  Or
} derive(Eq, Debug)

///|
pub(all) enum Operator {
  Add
  Sub
  Mult
  MatMult
  Div
  Mod
  Pow
  LShift
  RShift
  BitOr
  BitXor
  BitAnd
  FloorDiv
} derive(Eq, Debug)

///|
pub(all) enum UnaryOp {
  Invert
  Not
  UAdd
  USub
} derive(Eq, Debug)

///|
pub(all) enum CmpOp {
  Eq
  NotEq
  Lt
  LtE
  Gt
  GtE
  Is
  IsNot
  In
  NotIn
} derive(Eq, Debug)

///|
pub(all) struct Comprehension {
  target : Expr
  iter : Expr
  ifs : Array[Expr]
  is_async : Bool
} derive(Eq, Debug)

///|
pub(all) struct ExceptHandler {
  type_ : Expr?
  name : String?
  body : Array[Stmt]
  span : @basic.Span
} derive(Eq, Debug)

///|
/// One piece of an f-string: literal text, or an interpolation.
///
/// `conversion` is the `r` of `f"{x!r}"`, and `=` for the `f"{x=}"` debug
/// form, which has the same shape and the same decision behind it. `spec` is
/// the `>10` of `f"{x:>10}"`, kept as source: it is a language of its own, and
/// nothing here pretends to implement it.
pub(all) enum FStringPart {
  Text(String)
  Hole(value~ : Expr, conversion~ : Char?, spec~ : String?)
} derive(Eq, Debug)

///|
pub(all) struct Arguments {
  posonlyargs : Array[Arg]
  args : Array[Arg]
  vararg : Arg?
  kwonlyargs : Array[Arg]
  kw_defaults : Array[Expr?]
  kwarg : Arg?
  defaults : Array[Expr]
} derive(Eq, Debug)

///|
pub(all) struct Arg {
  arg : String
  annotation : Expr?
  span : @basic.Span
} derive(Eq, Debug)

///|
/// A keyword argument. `arg` of `None` is `**kwargs`.
pub(all) struct Keyword {
  arg : String?
  value : Expr
  span : @basic.Span
} derive(Eq, Debug)

///|
pub(all) struct Alias {
  name : String
  asname : String?
  span : @basic.Span
} derive(Eq, Debug)

///|
pub(all) struct WithItem {
  context_expr : Expr
  optional_vars : Expr?
} derive(Eq, Debug)

///|
pub(all) struct MatchCase {
  pattern : Pattern
  guard_ : Expr?
  body : Array[Stmt]
} derive(Eq, Debug)

///|
/// Which bracket a sequence pattern was written with. CPython forgets; the
/// spec distinguishes `[p]` from `(p)`, and a bare `case a, b:` is a tuple.
pub(all) enum SeqKind {
  List
  Tuple
} derive(Eq, Debug)

///|
pub(all) enum Pattern {
  /// A literal, a negated literal, a complex literal, or a dotted name.
  MatchValue(value~ : Expr, span~ : @basic.Span)
  /// `None`, `True` or `False`, which match by identity.
  MatchSingleton(value~ : Constant, span~ : @basic.Span)
  MatchSequence(
    kind~ : SeqKind,
    patterns~ : Array[Pattern],
    span~ : @basic.Span
  )
  MatchMapping(
    keys~ : Array[Expr],
    patterns~ : Array[Pattern],
    rest~ : String?,
    span~ : @basic.Span
  )
  MatchClass(
    cls~ : Expr,
    patterns~ : Array[Pattern],
    kwd_attrs~ : Array[String],
    kwd_patterns~ : Array[Pattern],
    span~ : @basic.Span
  )
  MatchStar(name~ : String?, span~ : @basic.Span)
  /// `_` is `MatchAs(None, None)`; `x` is `MatchAs(None, Some("x"))`.
  MatchAs(pattern~ : Pattern?, name~ : String?, span~ : @basic.Span)
  MatchOr(patterns~ : Array[Pattern], span~ : @basic.Span)
} derive(Eq, Debug)
