///|
/// Random PurePy programs, for the properties in `prop_test.mbt`.
///
/// Everything here is SEEDED: a failure names the seed that produced it, and
/// re-running with that seed produces the same tree. A generator that cannot
/// be replayed is a generator whose failures cannot be fixed.
///
/// The trees stay inside PurePy on purpose. A generator that produced `for`
/// loops would test the sieve, which the conformance suite already does; what
/// is worth testing here is the round trip through the printer and the parser
/// on trees no corpus happens to contain.
pub struct Gen {
  state : @splitmix.RandomState
  /// How much more structure the generator may build. Every recursive step
  /// spends one, so a tree is finite by construction.
  mut budget : Int
}

///|
pub fn Gen::new(seed : UInt64, budget? : Int = 24) -> Gen {
  { state: @splitmix.new(seed~), budget, }
}

///|
/// A number in `[0, n)`.
pub fn Gen::below(self : Gen, n : Int) -> Int {
  let v = self.state.next_uint().reinterpret_as_int()
  let x = if v < 0 { -(v + 1) } else { v }
  x % n
}

///|
pub fn Gen::pick(self : Gen, options : Array[String]) -> String {
  options[self.below(options.length())]
}

///|
/// The names a generated program uses. A small pool, so that the same name is
/// bound and used often enough for the round trip to exercise scoping.
let names : Array[String] = ["a", "b", "c", "d"]

// ---------------------------------------------------------------------------

///|
/// A module: a few statements, each of which may define, assign, branch or
/// match.
pub fn Gen::whole_module(self : Gen) -> @ast.Module {
  let body : Array[@ast.Stmt] = []
  let n = 1 + self.below(4)
  for _ in 0..<n {
    body.push(self.stmt(top_level=true))
  }
  @ast.module_of(body)
}

///|
pub fn Gen::stmt(self : Gen, top_level? : Bool = false) -> @ast.Stmt {
  if self.budget <= 0 {
    return @ast.Stmt::assign(self.pick(names), self.atom())
  }
  self.budget -= 1
  // A class declaration is legal at the module's top level and nowhere
  // else, so the generator does not build one anywhere else.
  match self.below(if top_level { 7 } else { 6 }) {
    0 => @ast.Stmt::pass()
    1 => @ast.Stmt::assign(self.pick(names), self.expr())
    2 => @ast.Stmt::expr_stmt(self.expr())
    3 =>
      @ast.Stmt::if_(
        self.expr(),
        [self.stmt()],
        or_else=if self.below(2) == 0 { [] } else { [self.stmt()] },
      )
    4 =>
      @ast.Stmt::def_(self.pick(names), [self.pick(names)], [
        @ast.Stmt::return_(value=self.expr()),
      ])
    5 =>
      @ast.Stmt::match_(self.expr(), [
        @ast.case_(self.pattern(), [self.stmt()]),
        @ast.case_(@ast.Pattern::wildcard(), [@ast.Stmt::pass()]),
      ])
    _ => @ast.Stmt::dataclass(self.pick(names), [self.pick(names)])
  }
}

///|
pub fn Gen::expr(self : Gen) -> @ast.Expr {
  if self.budget <= 0 {
    return self.atom()
  }
  self.budget -= 1
  match self.below(10) {
    0 | 1 => self.atom()
    2 =>
      @ast.Expr::binop(
        self.expr(),
        [@ast.Operator::Add, Sub, Mult, Div, FloorDiv, Mod, Pow][self.below(7)],
        self.expr(),
      )
    3 =>
      @ast.Expr::compare(
        self.expr(),
        [@ast.CmpOp::Eq, NotEq, Lt, LtE, Gt, GtE, In, NotIn][self.below(8)],
        self.expr(),
      )
    4 =>
      @ast.Expr::bool_op(if self.below(2) == 0 { And } else { Or }, [
        self.expr(),
        self.expr(),
      ])
    5 => @ast.Expr::not_(self.expr())
    6 => @ast.Expr::neg(self.expr())
    7 => @ast.Expr::if_exp(self.expr(), self.expr(), self.expr())
    8 => @ast.Expr::list([self.expr(), self.expr()])
    _ => @ast.Expr::call(@ast.Expr::name(self.pick(names)), [self.expr()])
  }
}

///|
pub fn Gen::atom(self : Gen) -> @ast.Expr {
  match self.below(8) {
    // Never a NEGATIVE integer literal: Python has no such thing, so `-1` is
    // a negation of `1` and a tree that holds one prints as source that reads
    // back as the negation. CPython's own unparser has the same asymmetry.
    0 => @ast.Expr::int(self.below(1000))
    1 => @ast.Expr::float(self.below(1000).to_double() / 8.0)
    2 => @ast.Expr::str(self.pick(["", "a", "it's", "\"q\"", "line\nbreak"]))
    3 => @ast.Expr::bool(self.below(2) == 0)
    4 => @ast.Expr::none()
    5 => @ast.Expr::tuple([@ast.Expr::int(self.below(10))])
    6 => @ast.Expr::dict([(@ast.Expr::str("k"), @ast.Expr::int(1))])
    _ => @ast.Expr::name(self.pick(names))
  }
}

///|
pub fn Gen::pattern(self : Gen) -> @ast.Pattern {
  if self.budget <= 0 {
    return @ast.Pattern::capture(self.pick(names))
  }
  self.budget -= 1
  match self.below(6) {
    0 => @ast.Pattern::capture(self.pick(names))
    1 => @ast.Pattern::wildcard()
    2 => @ast.Pattern::literal(Int(BigInt::from_int(self.below(10))))
    3 => @ast.Pattern::literal(Str(self.pick(["a", "b"])))
    4 => @ast.Pattern::sequence(List, [self.pattern()])
    _ => @ast.Pattern::sequence(Tuple, [self.pattern(), self.pattern()])
  }
}
