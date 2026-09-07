///|
/// A recursive-descent parser for Python 3.12, producing the CPython-shaped
/// tree of `ast`.
///
/// It accepts the whole language, not PurePy's subset: the reference rejects
/// on the TREE, in `syntax.py`, and reproducing its messages means having the
/// node it names. So `for`, `while`, `try`, `async`, decorators and the rest
/// all parse, and the sieve is what refuses them.
///
/// Positions are CPython's, because the reference's messages carry them and
/// the goldens compare them. Where CPython's choice is surprising -- a
/// decorated function starts at `def` and not at `@`, a call ends at its
/// closing bracket, `a.b` starts at `a` -- the code says so.
using @ast {type Module, type Stmt, type Expr, type Pattern}

///|
using @basic {type Pos, type Source, type Span}

///|
using @token {type Token}

///|
priv struct Parser {
  /// The source, for the one thing a token stream cannot supply: the TEXT a
  /// span covers, which an f-string keeps verbatim until #55 parses its parts.
  src : Source
  tokens : Array[Token]
  mut i : Int
  /// How deep the recursion is. A recursive-descent parser turns nesting in
  /// the input into nesting on the machine stack, and `((((...))))` with
  /// enough brackets is a segmentation fault rather than an answer. This
  /// makes it a syntax error instead, as CPython's own bracket limit does.
  mut depth : Int
}

///|
/// How deep an expression or a statement may nest.
///
/// CPython's tokenizer refuses more than 200 levels of brackets and its
/// compiler has its own recursion limit; this is one number for both, chosen
/// an order of magnitude above anything a person writes and two below what
/// this parser's stack can take.
let max_depth : Int = 500

///|
/// Parse a source into a module. Raises `PurePyError` with a
/// `PythonSyntax` kind, which the CLI prints as `parse error: ...` when a
/// module is loaded and plainly when a file is parsed.
pub fn parse(src : Source) -> Module raise {
  let all = @lexer.lex(src)
  // Comments and the newlines of non-logical lines are the tokenizer's
  // business; the grammar never mentions them.
  let tokens = all.filter(fn(t) { !t.kind.is_trivia() })
  let p = { src, tokens, i: 0, depth: 0, }
  let body = p.parse_statements_until_end()
  let span : Span = if tokens.is_empty() {
    @basic.nowhere
  } else {
    { start: @basic.origin, end: tokens[tokens.length() - 1].span.end, }
  }
  { body, span, }
}

///|
pub fn parse_string(text : String, name? : String = "<string>") -> Module raise {
  parse(Source::new(text, name~))
}

// ---------------------------------------------------------------------------
// The cursor

///|
fn Parser::peek(self : Parser) -> Token {
  self.tokens[if self.i < self.tokens.length() {
    self.i
  } else {
    self.tokens.length() - 1
  }]
}

///|
fn Parser::peek_at(self : Parser, n : Int) -> Token {
  let k = self.i + n
  self.tokens[if k < self.tokens.length() {
    k
  } else {
    self.tokens.length() - 1
  }]
}

///|
fn Parser::prev(self : Parser) -> Token {
  self.tokens[if self.i > 0 { self.i - 1 } else { 0 }]
}

///|
fn Parser::advance(self : Parser) -> Token {
  let t = self.peek()
  if self.i < self.tokens.length() - 1 {
    self.i += 1
  }
  t
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.peek().kind is EndMarker
}

///|
fn Parser::at_op(self : Parser, s : String) -> Bool {
  self.peek().is_op(s)
}

///|
fn Parser::at_name(self : Parser, s : String) -> Bool {
  self.peek().is_name(s)
}

///|
/// Consume the operator `s` if it is next.
fn Parser::eat_op(self : Parser, s : String) -> Bool {
  if self.at_op(s) {
    let _ = self.advance()
    true
  } else {
    false
  }
}

///|
/// Consume the keyword `s` if it is next.
fn Parser::eat_name(self : Parser, s : String) -> Bool {
  if self.at_name(s) {
    let _ = self.advance()
    true
  } else {
    false
  }
}

///|
fn Parser::expect_op(self : Parser, s : String) -> Token raise {
  if self.at_op(s) {
    self.advance()
  } else {
    raise self.error("expected '\{s}'")
  }
}

///|
fn Parser::expect_name(self : Parser, s : String) -> Token raise {
  if self.at_name(s) {
    self.advance()
  } else {
    raise self.error("expected '\{s}'")
  }
}

///|
/// Consume an identifier -- not a reserved word, which is what CPython means
/// by "invalid syntax" at a name position.
fn Parser::expect_identifier(self : Parser) -> Token raise {
  let t = self.peek()
  if t.kind is Name && !@token.is_keyword(t.text) {
    self.advance()
  } else {
    raise self.error("invalid syntax")
  }
}

///|
fn Parser::expect_newline(self : Parser) -> Unit raise {
  if self.peek().kind is Newline {
    let _ = self.advance()
  } else if self.at_end() {
    ()
  } else {
    raise self.error("invalid syntax")
  }
}

///|
fn Parser::error(self : Parser, msg : String) -> @err.PurePyError {
  @err.syntax_error(msg, self.peek().span)
}

///|
fn error_at(msg : String, span : Span) -> @err.PurePyError {
  @err.syntax_error(msg, span)
}

///|
/// A node's extent: from a remembered start to the end of the last token
/// consumed.
fn Parser::span_from(self : Parser, start : Pos) -> Span {
  { start, end: self.prev().span.end, }
}

///|
/// Enter one level of nesting, or refuse.
fn Parser::descend(self : Parser) -> Unit raise {
  self.depth += 1
  if self.depth > max_depth {
    raise self.error("too deeply nested")
  }
}

///|
fn Parser::ascend(self : Parser) -> Unit {
  self.depth -= 1
}

///|
fn Parser::here(self : Parser) -> Pos {
  self.peek().span.start
}

///|
/// A compound statement ends where its LAST inner statement ends, not after
/// the newline and the dedent that closed it. CPython's node stops at the last
/// token of the body, so this is where every `if`, `while`, `for`, `try`,
/// `with`, `def`, `class` and `match` gets its end.
fn body_end(body : Array[Stmt], fallback : Pos) -> Pos {
  if body.is_empty() {
    fallback
  } else {
    body[body.length() - 1].span().end
  }
}

///|
fn span_to(start : Pos, end : Pos) -> Span {
  { start, end, }
}

// ---------------------------------------------------------------------------
// Statements

///|
fn Parser::parse_statements_until_end(self : Parser) -> Array[Stmt] raise {
  let body : Array[Stmt] = []
  while !self.at_end() {
    if self.peek().kind is Newline {
      let _ = self.advance()
      continue
    }
    if self.peek().kind is (Indent | Dedent) {
      raise self.error("unexpected indent")
    }
    for s in self.parse_statement() {
      body.push(s)
    }
  }
  body
}

///|
/// One statement, which may be several: `a = 1; b = 2` is two.
fn Parser::parse_statement(self : Parser) -> Array[Stmt] raise {
  self.descend()
  let out = self.parse_statement_()
  self.ascend()
  out
}

///|
fn Parser::parse_statement_(self : Parser) -> Array[Stmt] raise {
  let t = self.peek()
  if t.kind is Name {
    match t.text {
      "if" => return [self.parse_if()]
      "while" => return [self.parse_while()]
      "for" => return [self.parse_for(is_async=false)]
      "try" => return [self.parse_try()]
      "with" => return [self.parse_with(is_async=false)]
      "def" => return [self.parse_def(is_async=false, decorators=[])]
      "class" => return [self.parse_class(decorators=[])]
      "async" => return [self.parse_async()]
      "match" =>
        if self.starts_match_statement() {
          return [self.parse_match()]
        }
      _ => ()
    }
  }
  if self.at_op("@") {
    return [self.parse_decorated()]
  }
  self.parse_simple_line()
}

///|
/// `match` is a soft keyword: `match x:` is a statement and `match = 1` is an
/// assignment. CPython decides by trying the statement and backtracking; the
/// cheap test that agrees on every program is that the next token can begin
/// an expression and the logical line ends with a colon.
fn Parser::starts_match_statement(self : Parser) -> Bool {
  let next = self.peek_at(1)
  if next.is_op("=") ||
    next.is_op(":") ||
    next.is_op(".") ||
    next.is_op(",") ||
    next.is_op(")") ||
    next.is_op("]") ||
    next.is_op("}") ||
    next.kind is Newline {
    return false
  }
  // Scan to the end of the logical line: a match statement's colon is the last
  // token on it, outside brackets.
  let mut k = self.i + 1
  let mut depth = 0
  let mut last_is_colon = false
  while k < self.tokens.length() {
    let t = self.tokens[k]
    match t.kind {
      Newline | EndMarker => break
      Op("(") | Op("[") | Op("{") => depth += 1
      Op(")") | Op("]") | Op("}") => depth -= 1
      Op("=") => if depth == 0 { return false }
      _ => ()
    }
    last_is_colon = t.is_op(":") && depth == 0
    k += 1
  }
  last_is_colon
}

///|
/// A line of simple statements: one or more, separated by `;`, ended by a
/// newline.
fn Parser::parse_simple_line(self : Parser) -> Array[Stmt] raise {
  let out : Array[Stmt] = [self.parse_simple_statement()]
  while self.eat_op(";") {
    if self.peek().kind is Newline || self.at_end() {
      break
    }
    out.push(self.parse_simple_statement())
  }
  self.expect_newline()
  out
}

///|
fn Parser::parse_simple_statement(self : Parser) -> Stmt raise {
  let start = self.here()
  let t = self.peek()
  if t.kind is Name {
    match t.text {
      "pass" => {
        let _ = self.advance()
        return Pass(span=self.span_from(start))
      }
      "break" => {
        let _ = self.advance()
        return Break(span=self.span_from(start))
      }
      "continue" => {
        let _ = self.advance()
        return Continue(span=self.span_from(start))
      }
      "return" => {
        let _ = self.advance()
        let value = if self.ends_statement() {
          None
        } else {
          Some(self.parse_expr_list(ctx=Load))
        }
        return Return(value~, span=self.span_from(start))
      }
      "raise" => {
        let _ = self.advance()
        if self.ends_statement() {
          return Raise(exc=None, cause=None, span=self.span_from(start))
        }
        let exc = self.parse_expr()
        let cause = if self.eat_name("from") {
          Some(self.parse_expr())
        } else {
          None
        }
        return Raise(exc=Some(exc), cause~, span=self.span_from(start))
      }
      "del" => {
        let _ = self.advance()
        let targets = self.parse_target_list(ctx=Del)
        return Delete(targets~, span=self.span_from(start))
      }
      "assert" => {
        let _ = self.advance()
        let cond = self.parse_expr()
        let msg = if self.eat_op(",") { Some(self.parse_expr()) } else { None }
        return Assert(cond~, msg~, span=self.span_from(start))
      }
      "global" => {
        let _ = self.advance()
        return Global(names=self.parse_name_list(), span=self.span_from(start))
      }
      "nonlocal" => {
        let _ = self.advance()
        return Nonlocal(
          names=self.parse_name_list(),
          span=self.span_from(start),
        )
      }
      "import" => return self.parse_import()
      "from" => return self.parse_from_import()
      _ => ()
    }
  }
  self.parse_expression_statement()
}

///|
fn Parser::ends_statement(self : Parser) -> Bool {
  self.peek().kind is Newline || self.at_op(";") || self.at_end()
}

///|
fn Parser::parse_name_list(self : Parser) -> Array[String] raise {
  let names : Array[String] = [self.expect_identifier().text]
  while self.eat_op(",") {
    names.push(self.expect_identifier().text)
  }
  names
}

///|
/// An expression statement, which may turn out to be an assignment, an
/// augmented assignment or an annotated assignment.
fn Parser::parse_expression_statement(self : Parser) -> Stmt raise {
  let start = self.here()
  let first = self.parse_expr_list(ctx=Load)
  if self.at_op(":") {
    let _ = self.advance()
    let annotation = self.parse_expr()
    let value = if self.eat_op("=") {
      Some(self.parse_expr_list(ctx=Load))
    } else {
      None
    }
    // CPython's `simple` is 1 for a bare name target and 0 when the target was
    // parenthesised or is an attribute or a subscript.
    let simple = first is Name(..)
    return AnnAssign(
      target=set_context(first, Store),
      annotation~,
      value~,
      simple~,
      span=self.span_from(start),
    )
  }
  match self.augmented_operator() {
    Some(op) => {
      let _ = self.advance()
      let value = self.parse_expr_list(ctx=Load)
      return AugAssign(
        target=set_context(first, Store),
        op~,
        value~,
        span=self.span_from(start),
      )
    }
    None => ()
  }
  if self.at_op("=") {
    let targets : Array[Expr] = [set_context(first, Store)]
    let mut value = first
    while self.eat_op("=") {
      value = self.parse_expr_list(ctx=Load)
      targets.push(set_context(value, Store))
    }
    // The last one parsed is the value, not a target.
    let _ = targets.pop()
    return Assign(targets~, value~, span=self.span_from(start))
  }
  ExprStmt(value=first, span=self.span_from(start))
}

///|
fn Parser::augmented_operator(self : Parser) -> @ast.Operator? {
  match self.peek().kind {
    Op("+=") => Some(Add)
    Op("-=") => Some(Sub)
    Op("*=") => Some(Mult)
    Op("@=") => Some(MatMult)
    Op("/=") => Some(Div)
    Op("%=") => Some(Mod)
    Op("**=") => Some(Pow)
    Op("<<=") => Some(LShift)
    Op(">>=") => Some(RShift)
    Op("|=") => Some(BitOr)
    Op("^=") => Some(BitXor)
    Op("&=") => Some(BitAnd)
    Op("//=") => Some(FloorDiv)
    _ => None
  }
}

///|
fn Parser::parse_target_list(
  self : Parser,
  ctx~ : @ast.ExprContext,
) -> Array[Expr] raise {
  let targets : Array[Expr] = [set_context(self.parse_expr(), ctx)]
  while self.eat_op(",") {
    if self.ends_statement() {
      break
    }
    targets.push(set_context(self.parse_expr(), ctx))
  }
  targets
}

// ---------------------------------------------------------------------------
// Imports

///|
fn Parser::parse_import(self : Parser) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("import")
  let names : Array[@ast.Alias] = [self.parse_dotted_alias()]
  while self.eat_op(",") {
    names.push(self.parse_dotted_alias())
  }
  Import(names~, span=self.span_from(start))
}

///|
fn Parser::parse_dotted_alias(self : Parser) -> @ast.Alias raise {
  let start = self.here()
  let name = self.parse_dotted_name()
  let asname = if self.eat_name("as") {
    Some(self.expect_identifier().text)
  } else {
    None
  }
  { name, asname, span: self.span_from(start), }
}

///|
fn Parser::parse_dotted_name(self : Parser) -> String raise {
  let out = StringBuilder()
  out.write_string(self.expect_identifier().text)
  while self.at_op(".") {
    let _ = self.advance()
    out.write_char('.')
    out.write_string(self.expect_identifier().text)
  }
  out.to_string()
}

///|
fn Parser::parse_from_import(self : Parser) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("from")
  let mut level = 0
  while self.at_op(".") || self.at_op("...") {
    level += if self.at_op("...") { 3 } else { 1 }
    let _ = self.advance()
  }
  let module_name = if self.at_name("import") {
    None
  } else {
    Some(self.parse_dotted_name())
  }
  let _ = self.expect_name("import")
  let names : Array[@ast.Alias] = []
  if self.at_op("*") {
    let star = self.advance()
    names.push(({ name: "*", asname: None, span: star.span, } : @ast.Alias))
  } else if self.at_op("(") {
    let _ = self.advance()
    while !self.at_op(")") {
      names.push(self.parse_plain_alias())
      if !self.eat_op(",") {
        break
      }
    }
    let _ = self.expect_op(")")
  } else {
    names.push(self.parse_plain_alias())
    while self.eat_op(",") {
      names.push(self.parse_plain_alias())
    }
  }
  ImportFrom(module_name~, names~, level~, span=self.span_from(start))
}

///|
fn Parser::parse_plain_alias(self : Parser) -> @ast.Alias raise {
  let start = self.here()
  let name = self.expect_identifier().text
  let asname = if self.eat_name("as") {
    Some(self.expect_identifier().text)
  } else {
    None
  }
  { name, asname, span: self.span_from(start), }
}

// ---------------------------------------------------------------------------
// Compound statements

///|
/// `NEWLINE INDENT stmt+ DEDENT`, or simple statements on the same line.
fn Parser::parse_block(self : Parser) -> Array[Stmt] raise {
  if self.peek().kind is Newline {
    let _ = self.advance()
    if !(self.peek().kind is Indent) {
      raise self.error("expected an indented block")
    }
    let _ = self.advance()
    let body : Array[Stmt] = []
    while !(self.peek().kind is Dedent) && !self.at_end() {
      if self.peek().kind is Newline {
        let _ = self.advance()
        continue
      }
      for s in self.parse_statement() {
        body.push(s)
      }
    }
    if self.peek().kind is Dedent {
      let _ = self.advance()
    }
    body
  } else {
    self.parse_simple_line()
  }
}

///|
fn Parser::parse_if(self : Parser) -> Stmt raise {
  let start = self.here()
  let _ = self.advance() // `if` or `elif`
  let cond = self.parse_namedexpr()
  let _ = self.expect_op(":")
  let body = self.parse_block()
  let or_else = if self.at_name("elif") {
    // CPython represents `elif` as a nested `If` in `orelse`, whose position
    // starts at the `elif` keyword.
    [self.parse_if()]
  } else if self.at_name("else") {
    let _ = self.advance()
    let _ = self.expect_op(":")
    self.parse_block()
  } else {
    []
  }
  let last = if or_else.is_empty() { body } else { or_else }
  If(cond~, body~, or_else~, span=span_to(start, body_end(last, start)))
}

///|
fn Parser::parse_while(self : Parser) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("while")
  let cond = self.parse_namedexpr()
  let _ = self.expect_op(":")
  let body = self.parse_block()
  let or_else = self.parse_else()
  let last = if or_else.is_empty() { body } else { or_else }
  While(cond~, body~, or_else~, span=span_to(start, body_end(last, start)))
}

///|
fn Parser::parse_else(self : Parser) -> Array[Stmt] raise {
  if self.at_name("else") {
    let _ = self.advance()
    let _ = self.expect_op(":")
    self.parse_block()
  } else {
    []
  }
}

///|
fn Parser::parse_for(self : Parser, is_async~ : Bool) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("for")
  let target = set_context(self.parse_star_targets(), Store)
  let _ = self.expect_name("in")
  let iter = self.parse_expr_list(ctx=Load)
  let _ = self.expect_op(":")
  let body = self.parse_block()
  let or_else = self.parse_else()
  let last = if or_else.is_empty() { body } else { or_else }
  For(
    target~,
    iter~,
    body~,
    or_else~,
    is_async~,
    span=span_to(start, body_end(last, start)),
  )
}

///|
fn Parser::parse_with(self : Parser, is_async~ : Bool) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("with")
  let items : Array[@ast.WithItem] = []
  // `with (a as x, b as y):` is a parenthesised item list in 3.9+, but
  // `with (a, b):` is a single tuple context manager. Try the parenthesised
  // list and fall back.
  let saved = self.i
  let mut parenthesised = false
  if self.at_op("(") {
    let _ = self.advance()
    let ok = try {
      while !self.at_op(")") {
        items.push(self.parse_with_item())
        if !self.eat_op(",") {
          break
        }
      }
      self.expect_op(")") |> ignore
      self.at_op(":")
    } catch {
      _ => false
    }
    if ok {
      parenthesised = true
    } else {
      self.i = saved
      items.clear()
    }
  }
  if !parenthesised {
    items.push(self.parse_with_item())
    while self.eat_op(",") {
      items.push(self.parse_with_item())
    }
  }
  let _ = self.expect_op(":")
  let body = self.parse_block()
  With(items~, body~, is_async~, span=span_to(start, body_end(body, start)))
}

///|
fn Parser::parse_with_item(self : Parser) -> @ast.WithItem raise {
  let context_expr = self.parse_expr()
  // `with a as x, b as y` binds ONE target after each `as`: the grammar is
  // `expression ['as' star_target]`, singular, so the comma belongs to the
  // item list and not to the target.
  let optional_vars = if self.eat_name("as") {
    Some(set_context(self.parse_star_target(), Store))
  } else {
    None
  }
  { context_expr, optional_vars, }
}

///|
fn Parser::parse_try(self : Parser) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("try")
  let _ = self.expect_op(":")
  let body = self.parse_block()
  let handlers : Array[@ast.ExceptHandler] = []
  let mut is_star = false
  while self.at_name("except") {
    let h_start = self.here()
    let _ = self.advance()
    if self.eat_op("*") {
      is_star = true
    }
    let type_ = if self.at_op(":") { None } else { Some(self.parse_expr()) }
    let name = if self.eat_name("as") {
      Some(self.expect_identifier().text)
    } else {
      None
    }
    let _ = self.expect_op(":")
    let h_body = self.parse_block()
    handlers.push(
      (
        {
          type_,
          name,
          body: h_body,
          span: span_to(h_start, body_end(h_body, h_start)),
        } : @ast.ExceptHandler),
    )
  }
  let or_else = self.parse_else()
  let finalbody = if self.at_name("finally") {
    let _ = self.advance()
    let _ = self.expect_op(":")
    self.parse_block()
  } else {
    []
  }
  if handlers.is_empty() && finalbody.is_empty() {
    raise self.error("expected 'except' or 'finally' block")
  }
  let end = if !finalbody.is_empty() {
    body_end(finalbody, start)
  } else if !or_else.is_empty() {
    body_end(or_else, start)
  } else if !handlers.is_empty() {
    handlers[handlers.length() - 1].span.end
  } else {
    body_end(body, start)
  }
  Try(
    body~,
    handlers~,
    or_else~,
    finalbody~,
    is_star~,
    span=span_to(start, end),
  )
}

///|
/// `async def`, `async for` and `async with`. The `async` keyword is part of
/// the statement's extent, which is why the start is remembered here.
fn Parser::parse_async(self : Parser) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("async")
  let inner = if self.at_name("def") {
    self.parse_def(is_async=true, decorators=[])
  } else if self.at_name("for") {
    self.parse_for(is_async=true)
  } else if self.at_name("with") {
    self.parse_with(is_async=true)
  } else {
    raise self.error("invalid syntax")
  }
  retag_span(inner, span_to(start, inner.span().end))
}

///|
/// A decorated function or class. CPython's node starts at `def` or `class`,
/// not at the first `@`, and the decorators keep their own positions.
fn Parser::parse_decorated(self : Parser) -> Stmt raise {
  let decorators : Array[Expr] = []
  while self.at_op("@") {
    let _ = self.advance()
    decorators.push(self.parse_namedexpr())
    self.expect_newline()
  }
  if self.at_name("class") {
    self.parse_class(decorators~)
  } else if self.at_name("async") {
    let _ = self.advance()
    self.parse_def(is_async=true, decorators~)
  } else if self.at_name("def") {
    self.parse_def(is_async=false, decorators~)
  } else {
    raise self.error("invalid syntax")
  }
}

///|
fn Parser::parse_def(
  self : Parser,
  is_async~ : Bool,
  decorators~ : Array[Expr],
) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("def")
  let name = self.expect_identifier().text
  let _ = self.expect_op("(")
  let args = self.parse_parameters()
  let _ = self.expect_op(")")
  let returns = if self.eat_op("->") { Some(self.parse_expr()) } else { None }
  let _ = self.expect_op(":")
  let body = self.parse_block()
  FunctionDef(
    name~,
    args~,
    body~,
    decorators~,
    returns~,
    is_async~,
    span=span_to(start, body_end(body, start)),
  )
}

///|
fn Parser::parse_class(self : Parser, decorators~ : Array[Expr]) -> Stmt raise {
  let start = self.here()
  let _ = self.expect_name("class")
  let name = self.expect_identifier().text
  let bases : Array[Expr] = []
  let keywords : Array[@ast.Keyword] = []
  if self.eat_op("(") {
    while !self.at_op(")") {
      let arg_start = self.here()
      if self.at_op("**") {
        let _ = self.advance()
        let value = self.parse_expr()
        keywords.push(
          ({ arg: None, value, span: self.span_from(arg_start), } : @ast.Keyword),
        )
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
      } else if self.at_op("*") {
        let _ = self.advance()
        let value = self.parse_expr()
        bases.push(
          @ast.Expr::Starred(value~, ctx=Load, span=self.span_from(arg_start)),
        )
      } else {
        bases.push(self.parse_expr())
      }
      if !self.eat_op(",") {
        break
      }
    }
    let _ = self.expect_op(")")
  }
  let _ = self.expect_op(":")
  let body = self.parse_block()
  ClassDef(
    name~,
    bases~,
    keywords~,
    body~,
    decorators~,
    span=span_to(start, body_end(body, start)),
  )
}

///|
/// Replace a statement's span, for `async` -- which is part of the extent of
/// the statement it precedes.
fn retag_span(s : Stmt, span : Span) -> Stmt {
  match s {
    FunctionDef(name~, args~, body~, decorators~, returns~, is_async~, ..) =>
      FunctionDef(name~, args~, body~, decorators~, returns~, is_async~, span~)
    For(target~, iter~, body~, or_else~, is_async~, ..) =>
      For(target~, iter~, body~, or_else~, is_async~, span~)
    With(items~, body~, is_async~, ..) => With(items~, body~, is_async~, span~)
    other => other
  }
}
