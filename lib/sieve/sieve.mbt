///|
/// The sieve: everything PurePy excludes on sight.
///
/// A port of the reference's `syntax.py`, function for function and message
/// for message. Two things about it are load-bearing and easy to lose:
///
///   * **The traversal order is the answer.** A file with two violations
///     reports the first one the walk reaches, and the conformance suite has
///     files that depend on which. So the order of the tests below is the
///     order of the `isinstance` chain in `syntax.py`, not a tidier one.
///   * **Some rejections have no position.** `check_arguments`,
///     `check_generator` and the case-guard test are handed CPython nodes that
///     carry no `lineno` -- `arguments`, `comprehension`, `match_case` -- and
///     the reference prints `path: msg` with no line for them. That is
///     reproduced by giving those diagnostics no span.
///
/// Everything here raises on the first violation, so `check` is `Unit` and
/// the caller catches.
pub fn check_module(
  m : @ast.Module,
  profile? : @profile.Profile = @profile.core,
) -> Unit raise {
  Sieve::{ profile, }.check_top_level(m.body)
}

///|
/// Whether a module passes the sieve, as a diagnostic rather than a raise.
pub fn result(
  m : @ast.Module,
  profile? : @profile.Profile = @profile.core,
) -> @err.Diagnostic? {
  try check_module(m, profile~) catch {
    @err.PurePyError(d) => Some(d)
    _ => None
  } noraise {
    _ => None
  }
}

// ---------------------------------------------------------------------------

///|
/// The sieve's one piece of state: which superset of PurePy it is sieving FOR.
///
/// A struct threaded as a receiver rather than a parameter passed by hand,
/// because the profile is consulted at leaves twenty levels down and the
/// traversal is nine mutually recursive functions. Under `@profile.core` --
/// the default of every entry point above -- it changes nothing: `gate` raises
/// exactly where the `raise not_yet(...)` it replaced raised.
///
/// Three of the nine traversal functions -- `check_classdef`, `check_field`
/// and `check_arguments` -- are still free functions rather than methods,
/// because none of their gates is open yet. Each becomes a method in the
/// commit that opens its first one (`check_field` never will: its rejections
/// are all prohibitions). Which of them takes a `Sieve` is therefore a reading
/// of how far a profile can reach today.
priv struct Sieve {
  profile : @profile.Profile
}

///|
/// A `not_yet` that a profile can open.
///
/// The rejection is byte-identical to the one it replaces and happens at the
/// same point in the same traversal, which is what keeps `core` honest: the
/// order of these tests is `syntax.py`'s and a file with two violations
/// reports the first one the walk reaches. Under a profile that has the
/// feature this returns, and the arm goes on to walk the node the way the
/// sieve walks everything it accepts.
fn Sieve::gate(
  self : Sieve,
  f : @profile.Feature,
  feature : String,
  issue : Int,
  span : @basic.Span,
) -> Unit raise {
  if !self.profile.has(f) {
    raise not_yet(feature, issue, span)
  }
}

///|
/// The same, for the node kinds CPython gives no position.
///
/// `arguments`, `comprehension` and `match_case` carry no `lineno`, and the
/// reference prints `path: msg` with no line for them; the diagnostic has no
/// span for the same reason.
fn Sieve::gate_nowhere(
  self : Sieve,
  f : @profile.Feature,
  feature : String,
  issue : Int,
) -> Unit raise {
  if !self.profile.has(f) {
    raise not_yet_nowhere(feature, issue)
  }
}

///|
/// A form PurePy excludes on purpose, and the one thing no profile can open.
///
/// There is deliberately no `Sieve::gate` for this the way there is for
/// `not_yet`. `for`, `while`, `try`, `raise`, `del`, `+=`, item and attribute
/// assignment are what make the language pure: a value has no cell to write to
/// because nothing can spell a write. A profile may say "not yet, but yes"; it
/// may not say "yes" to these. Two helpers rather than one parameterised one
/// is what makes that readable here rather than a claim someone has to find.
fn prohibited(msg : String, span : @basic.Span) -> @err.PurePyError {
  @err.PurePyError(@err.Diagnostic::new(Prohibited(msg~), span~))
}

///|
/// A rejection with no position, for the three node kinds CPython gives none.
fn prohibited_nowhere(msg : String) -> @err.PurePyError {
  @err.PurePyError(@err.Diagnostic::new(Prohibited(msg~)))
}

///|
fn not_yet(
  feature : String,
  issue : Int,
  span : @basic.Span,
) -> @err.PurePyError {
  @err.PurePyError(
    @err.Diagnostic::new(NotYetSupported(feature~, issue~), span~),
  )
}

///|
fn not_yet_nowhere(feature : String, issue : Int) -> @err.PurePyError {
  @err.PurePyError(@err.Diagnostic::new(NotYetSupported(feature~, issue~)))
}

// ---------------------------------------------------------------------------

///|
/// The module body: a class declaration is allowed here and nowhere else.
fn Sieve::check_top_level(self : Sieve, stmts : Array[@ast.Stmt]) -> Unit raise {
  for s in stmts {
    if s is ClassDef(..) {
      check_classdef(s)
    } else {
      self.check_stmt(s)
    }
  }
}

///|
/// A destructuring target: a nest of names, and nothing else (#54).
///
/// The messages are the ones a bare target gets, because the rule is the same
/// one: `a.b, c = ...` IS attribute assignment, and saying so beats saying the
/// target had an unexpected shape. `*rest` never reaches here -- a starred
/// expression is prohibited outright, so a destructuring target under this
/// profile is always exact in its arity.
fn Sieve::check_target(
  self : Sieve,
  t : @ast.Expr,
  span : @basic.Span,
) -> Unit raise {
  match t {
    Name(..) => ()
    Tuple(elts~, ..) | List(elts~, ..) =>
      for x in elts {
        self.check_target(x, span)
      }
    Subscript(..) => raise prohibited("item assignment prohibited", span)
    Attribute(..) => raise prohibited("attribute assignment prohibited", span)
    Starred(..) => raise prohibited("starred expressions prohibited", span)
    _ => raise prohibited("assignment target must be a name", span)
  }
}

///|
fn Sieve::check_body(self : Sieve, stmts : Array[@ast.Stmt]) -> Unit raise {
  for s in stmts {
    self.check_stmt(s)
  }
}

///|
fn Sieve::check_stmt(self : Sieve, node : @ast.Stmt) -> Unit raise {
  let span = node.span()
  match node {
    Pass(..) => ()
    Assign(targets~, value~, ..) => {
      if targets.length() != 1 {
        raise prohibited("multiple assignment targets", span)
      }
      match targets[0] {
        Subscript(..) => raise prohibited("item assignment prohibited", span)
        Attribute(..) =>
          raise prohibited("attribute assignment prohibited", span)
        Name(..) => ()
        _ => {
          self.gate(
            DestructuringAssignment,
            "destructuring assignment",
            54,
            span,
          )
          self.check_target(targets[0], span)
        }
      }
      self.check_expr(value)
    }
    Return(value~, ..) =>
      match value {
        Some(v) => self.check_expr(v)
        None => ()
      }
    If(cond~, body~, or_else~, ..) => {
      self.check_expr(cond)
      self.check_body(body)
      self.check_body(or_else)
    }
    // `async def` is a different class in CPython and never reaches the
    // `FunctionDef` arm, so its arguments, decorators and annotation are not
    // examined: it is simply "async prohibited".
    FunctionDef(is_async=true, ..) => raise prohibited("async prohibited", span)
    FunctionDef(args~, body~, decorators~, returns~, ..) => {
      self.check_arguments(args)
      if decorators.length() > 0 {
        raise not_yet("decorators", 58, span)
      }
      if returns is Some(_) {
        raise prohibited("return type annotations prohibited", span)
      }
      self.check_body(body)
    }
    ExprStmt(value~, ..) => self.check_expr(value)
    Assert(cond~, msg~, ..) => {
      self.check_expr(cond)
      match msg {
        Some(m) => self.check_expr(m)
        None => ()
      }
    }
    AugAssign(..) =>
      raise prohibited("augmented assignment (+=, etc.) prohibited", span)
    AnnAssign(..) => raise prohibited("annotated assignment prohibited", span)
    Delete(..) => raise prohibited("del prohibited", span)
    For(is_async=false, ..) => raise prohibited("for loops prohibited", span)
    While(..) => raise prohibited("while loops prohibited", span)
    With(is_async=false, ..) =>
      raise prohibited("with statements prohibited", span)
    For(..) | With(..) => raise prohibited("async prohibited", span)
    Raise(..) => raise prohibited("raise prohibited", span)
    // `try/except*` is `TryStar` in CPython, a class of its own that the
    // reference's chain never names, so it falls through to the last line.
    Try(is_star=false, ..) => raise prohibited("try/except prohibited", span)
    Import(names~, ..) => {
      if names.length() != 1 {
        raise not_yet("multi-target import (import a, b)", 53, span)
      }
      if names[0].asname is Some(_) {
        raise not_yet("import-as", 53, span)
      }
    }
    ImportFrom(module_name~, names~, level~, ..) => {
      if level > 0 {
        raise not_yet("relative imports", 53, span)
      }
      if module_name is None {
        raise not_yet("from-import with no module", 53, span)
      }
      for a in names {
        if a.name == "*" {
          raise not_yet("from M import *", 53, span)
        }
        if a.asname is Some(_) {
          raise not_yet("from-import-as", 53, span)
        }
      }
    }
    Global(..) => raise prohibited("global prohibited", span)
    Nonlocal(..) => raise prohibited("nonlocal prohibited", span)
    ClassDef(..) =>
      raise prohibited("class declaration only at module top level", span)
    Match(subject~, cases~, ..) => {
      self.check_expr(subject)
      for c in cases {
        // A `match_case` carries no position in CPython's tree.
        if c.guard_ is Some(_) {
          raise not_yet_nowhere("case guards", 83)
        }
        self.check_pattern(c.pattern)
        self.check_body(c.body)
      }
    }
    Break(..) => raise prohibited("break prohibited", span)
    Continue(..) => raise prohibited("continue prohibited", span)
    _ => raise prohibited("unknown statement type: \{node.kind_name()}", span)
  }
}

///|
fn check_classdef(node : @ast.Stmt) -> Unit raise {
  let span = node.span()
  match node {
    ClassDef(bases~, keywords~, body~, decorators~, ..) => {
      for b in bases {
        if b is Name(id="Enum", ..) {
          raise not_yet("enum classes", 86, span)
        }
      }
      if decorators.length() != 1 {
        raise prohibited(
          "class must have exactly the @dataclass decorator", span,
        )
      }
      if !(decorators[0] is Name(id="dataclass", ..)) {
        raise prohibited(
          "only the @dataclass decorator is supported on classes", span,
        )
      }
      if bases.length() > 1 {
        raise prohibited("multiple inheritance prohibited", span)
      }
      if bases.length() > 0 && !(bases[0] is Name(..)) {
        raise prohibited("base class must be a simple name", span)
      }
      if keywords.length() > 0 {
        raise prohibited("class keyword arguments prohibited", span)
      }
      if body.length() == 1 && body[0] is Pass(..) {
        return
      }
      for s in body {
        check_field(s)
      }
    }
    _ => ()
  }
}

///|
fn check_field(stmt : @ast.Stmt) -> Unit raise {
  let span = stmt.span()
  match stmt {
    AnnAssign(target~, annotation~, value~, ..) => {
      if !(target is Name(..)) {
        raise prohibited("field target must be a simple name", span)
      }
      if value is Some(_) {
        raise prohibited("field default values prohibited", span)
      }
      if !(annotation is Name(id="Any", ..)) {
        raise prohibited("field type annotation must be Any", span)
      }
    }
    _ =>
      raise prohibited(
        "dataclass body may contain only field declarations", span,
      )
  }
}

///|
/// `a`, `a.b`, `a.b.c` -- what a class pattern's head must be.
pub fn is_qualified_name(e : @ast.Expr) -> Bool {
  match e {
    Name(..) => true
    Attribute(value~, ..) => is_qualified_name(value)
    _ => false
  }
}

///|
fn Sieve::check_pattern(self : Sieve, node : @ast.Pattern) -> Unit raise {
  let span = node.span()
  match node {
    MatchValue(value~, ..) => {
      match value {
        // A bool in a pattern is a `MatchSingleton`, so `int` here never
        // means `bool` -- which in Python it otherwise would.
        Constant(value=Int(_) | Float(_) | Str(_), ..) => return
        UnaryOp(op=UAdd | USub, operand~, ..) =>
          if operand is Constant(value=Int(_) | Float(_), ..) {
            return
          }
        Attribute(..) => raise not_yet("attribute value patterns", 86, span)
        _ => ()
      }
      raise not_yet("complex value patterns", 83, span)
    }
    MatchSingleton(..) => ()
    MatchAs(pattern~, ..) =>
      match pattern {
        Some(p) => self.check_pattern(p)
        None => ()
      }
    MatchSequence(patterns~, ..) =>
      for p in patterns {
        if p is MatchStar(..) {
          raise not_yet("star patterns", 84, span)
        }
        self.check_pattern(p)
      }
    MatchClass(cls~, patterns~, kwd_patterns~, ..) => {
      if !is_qualified_name(cls) {
        raise prohibited("class pattern head must be a qualified name", span)
      }
      for p in patterns {
        self.check_pattern(p)
      }
      for p in kwd_patterns {
        self.check_pattern(p)
      }
    }
    MatchMapping(keys~, patterns~, rest~, ..) => {
      if rest is Some(_) {
        raise not_yet("rest capture in dict patterns", 84, span)
      }
      for k in keys {
        if !(k is Constant(value=Str(_), ..)) {
          // The KEY's position, not the pattern's.
          raise prohibited(
            "dict pattern keys must be string literals",
            k.span(),
          )
        }
      }
      for p in patterns {
        self.check_pattern(p)
      }
    }
    MatchOr(..) => raise not_yet("or-patterns", 85, span)
    MatchStar(..) => raise not_yet("star patterns", 84, span)
  }
}

///|
fn Sieve::check_expr(self : Sieve, node : @ast.Expr) -> Unit raise {
  let span = node.span()
  match node {
    Constant(value~, ..) =>
      match value {
        Int(_) | Float(_) | Str(_) | Bool(_) | None => ()
        Bytes(_) | Complex(_) =>
          raise prohibited("\{value.type_name()} literals prohibited", span)
        _ =>
          raise prohibited(
            "prohibited literal type: \{value.type_name()}",
            span,
          )
      }
    Name(..) => ()
    BinOp(left~, op~, right~, ..) => {
      match op {
        Add | Sub | Mult | Div | FloorDiv | Mod | Pow => ()
        _ =>
          raise prohibited("binary operator '\{op.symbol()}' prohibited", span)
      }
      self.check_expr(left)
      self.check_expr(right)
    }
    UnaryOp(op~, operand~, ..) =>
      match op {
        Not | UAdd | USub => self.check_expr(operand)
        _ =>
          raise prohibited("unary operator '\{op.symbol()}' prohibited", span)
      }
    BoolOp(values~, ..) => {
      if values.length() > 2 {
        self.gate(ChainedBoolean, "chained boolean operator", 82, span)
      }
      for v in values {
        self.check_expr(v)
      }
    }
    Compare(left~, ops~, comparators~, ..) => {
      if ops.length() > 1 {
        self.gate(ChainedComparison, "chained comparison", 82, span)
      }
      for op in ops {
        if op is (Is | IsNot) {
          self.gate(Identity, "identity operator (is/is not)", 81, span)
          // `1 is 1` cannot be given an answer and never will be: a PurePy
          // value has no identity, and `None` is the whole of the exception.
          // Where an operand is a literal that is not `None`, that is visible
          // HERE -- no types needed, just the token -- so it is refused before
          // the program runs rather than left to stop halfway through it.
          //
          // `prohibited` and not `not_yet`: this is not waiting on anything.
          // Which also means no profile lifts it, which is correct.
          for operand in [left, ..comparators] {
            if operand is Constant(value~, ..) && !(value is None) {
              raise prohibited(
                "identity against a literal: PurePy values have no identity apart from None",
                operand.span(),
              )
            }
          }
        }
      }
      self.check_expr(left)
      for c in comparators {
        self.check_expr(c)
      }
    }
    Call(func~, args~, keywords~, ..) => {
      self.check_expr(func)
      for a in args {
        self.check_expr(a)
      }
      for k in keywords {
        self.check_expr(k.value)
      }
    }
    IfExp(cond~, body~, or_else~, ..) => {
      self.check_expr(cond)
      self.check_expr(body)
      self.check_expr(or_else)
    }
    Lambda(args~, body~, ..) => {
      self.check_arguments(args)
      self.check_expr(body)
    }
    List(elts~, ..) | Tuple(elts~, ..) =>
      for e in elts {
        self.check_expr(e)
      }
    Dict(keys~, values~, ..) => {
      for k in keys {
        match k {
          Some(e) => self.check_expr(e)
          None => ()
        }
      }
      for v in values {
        self.check_expr(v)
      }
    }
    Set(..) => raise not_yet("set literals", 147, span)
    Attribute(value~, ..) => self.check_expr(value)
    Subscript(value~, slice~, ..) => {
      self.check_expr(value)
      self.check_expr(slice)
    }
    ListComp(elt~, generators~, ..) => {
      self.check_expr(elt)
      for g in generators {
        self.check_generator(g)
      }
    }
    DictComp(key~, value~, generators~, ..) => {
      self.check_expr(key)
      self.check_expr(value)
      for g in generators {
        self.check_generator(g)
      }
    }
    SetComp(..) => raise not_yet("set comprehensions", 147, span)
    Slice(lower~, upper~, step~, ..) => {
      self.gate(Slicing, "slicing", 59, span)
      for b in [lower, upper, step] {
        match b {
          Some(x) => self.check_expr(x)
          None => ()
        }
      }
    }
    GeneratorExp(..) =>
      raise prohibited("generator expressions prohibited", span)
    NamedExpr(..) => raise prohibited("walrus operator (:=) prohibited", span)
    Starred(..) => raise prohibited("starred expressions prohibited", span)
    Await(..) => raise prohibited("async prohibited", span)
    Yield(..) | YieldFrom(..) => raise prohibited("yield prohibited", span)
    JoinedStr(..) => raise not_yet("f-strings", 55, span)
  }
}

///|
/// A comprehension clause. The node carries no position in CPython's tree, so
/// neither rejection here has one.
fn Sieve::check_generator(
  self : Sieve,
  node : @ast.Comprehension,
) -> Unit raise {
  if node.is_async {
    raise prohibited_nowhere("async comprehensions prohibited")
  }
  if !(node.target is Name(..)) {
    raise not_yet_nowhere("destructuring in comprehensions", 54)
  }
  self.check_expr(node.iter)
  for i in node.ifs {
    self.check_expr(i)
  }
}

///|
/// A parameter list. `arguments` carries no position either.
fn Sieve::check_arguments(self : Sieve, node : @ast.Arguments) -> Unit raise {
  if node.vararg is Some(_) {
    raise not_yet_nowhere("*args", 57)
  }
  if node.kwarg is Some(_) {
    raise not_yet_nowhere("**kwargs", 57)
  }
  if node.kwonlyargs.length() > 0 {
    raise prohibited_nowhere("keyword-only arguments prohibited")
  }
  if node.defaults.length() > 0 || node.kw_defaults.length() > 0 {
    self.gate_nowhere(DefaultArguments, "default arguments", 56)
    // A default has to be a LITERAL. Python evaluates one once, when the
    // `def` runs, and that is observable for anything with an effect or a
    // free name; there is nowhere in this evaluator to put a once, because
    // calling one function of a mutual region rebuilds the whole region. A
    // literal has no effect and reads no name, so when it is evaluated cannot
    // be seen and the question does not arise. Anything else is still #56.
    for d in node.defaults {
      match d {
        Constant(value~, ..) =>
          if value is (Bytes(_) | Complex(_) | Ellipsis) {
            // Already prohibited as literals in their own right; refused here
            // too so the message names the same thing wherever it is written.
            raise prohibited(
              "\{value.type_name()} literals prohibited",
              d.span(),
            )
          }
        _ =>
          raise not_yet(
            "a default argument that is not a literal",
            56,
            d.span(),
          )
      }
    }
  }
  if node.posonlyargs.length() > 0 {
    raise prohibited_nowhere("positional-only arguments prohibited")
  }
}
