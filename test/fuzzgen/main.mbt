// A generator of random PurePy programs, for the differential in
// `tools/diffrun.py`.
//
// The oracle for `run` is CPython, and the conformance suite is 136 programs
// somebody wrote by hand. This is the other half: programs nobody wrote,
// checked against the same oracle. It only GENERATES -- comparing needs
// Python, so the driver is a script and this is a binary it calls.
//
// Three things make a generated program worth comparing:
//
//   * **It prints.** A program with no output compares equal to every other
//     silent program, so every generated module ends in `print`.
//   * **The checker decides whether it counts.** The generator does not try to
//     be correct; it tries to be varied. `pure-py check` is the gate, and a
//     module it rejects is discarded by the driver. That is the validator
//     doing the work a hand-written generator would otherwise have to.
//   * **It can be shrunk.** A divergence in a forty line random program is a
//     bug report nobody can act on. `shrink` takes a program back to its tree
//     and prints the simpler trees, and the driver walks them with the oracle
//     in the loop, which is what makes a counterexample small enough to read.

///|
/// A generated module. The newtype is what `Arbitrary` and `Shrink` attach to.
struct Program {
  tree : @ast.Module
}

///|
/// The names a generated program may use. Small, so that the same name is
/// bound and read often enough for scoping to be exercised, and bound in the
/// prelude so that a reference to one is not automatically ill formed.
let names : Array[String] = ["a", "b", "c"]

///|
/// A seeded cursor over the random state, with a budget so recursion ends.
struct Draw {
  state : @splitmix.RandomState
  mut budget : Int
}

///|
fn Draw::below(self : Draw, n : Int) -> Int {
  let v = self.state.next_uint().reinterpret_as_int()
  let x = if v < 0 { -(v + 1) } else { v }
  x % n
}

///|
fn Draw::pick(self : Draw, options : Array[String]) -> String {
  options[self.below(options.length())]
}

// ---------------------------------------------------------------------------
// The shape of a generated module

///|
/// `from typing import Any`, a dataclass, a function, the name pool bound, and
/// then the statements worth varying -- ending in the prints that make the
/// module comparable at all.
fn Draw::program(self : Draw) -> Program {
  let body : Array[@ast.Stmt] = [
    @ast.Stmt::from_import("dataclasses", ["dataclass"]),
    @ast.Stmt::from_import("typing", ["Any"]),
    @ast.Stmt::dataclass("P", ["x", "y"]),
    // A function whose body cannot call anything, so a generated program
    // always terminates.
    @ast.Stmt::def_("f", ["n"], [@ast.Stmt::return_(value=self.simple_expr())]),
  ]
  // The pool, bound to literals, so a later reference is well formed.
  for name in names {
    body.push(@ast.Stmt::assign(name, self.atom(pool=false)))
  }
  for _ in 0..<(1 + self.below(3)) {
    body.push(self.stmt())
  }
  for _ in 0..<(1 + self.below(2)) {
    body.push(@ast.Stmt::expr_stmt(self.print_of(self.expr())))
  }
  { tree: @ast.module_of(body), }
}

///|
fn Draw::print_of(self : Draw, e : @ast.Expr) -> @ast.Expr {
  ignore(self)
  @ast.Expr::call(@ast.Expr::name("print"), [e])
}

///|
fn Draw::stmt(self : Draw) -> @ast.Stmt {
  if self.budget <= 0 {
    return @ast.Stmt::assign(self.pick(names), self.atom())
  }
  self.budget -= 1
  match self.below(6) {
    0 | 1 => @ast.Stmt::assign(self.pick(names), self.expr())
    2 =>
      @ast.Stmt::if_(
        self.condition(),
        [@ast.Stmt::assign(self.pick(names), self.expr())],
        or_else=[@ast.Stmt::assign(self.pick(names), self.expr())],
      )
    3 =>
      @ast.Stmt::match_(self.expr(), [
        @ast.case_(self.pattern(), [
          @ast.Stmt::expr_stmt(self.print_of(@ast.Expr::str("m"))),
        ]),
        @ast.case_(@ast.Pattern::wildcard(), [@ast.Stmt::pass()]),
      ])
    4 => @ast.Stmt::expr_stmt(self.print_of(self.expr()))
    _ => @ast.Stmt::pass()
  }
}

///|
/// An expression over the name pool, `f`, `P` and the literals.
fn Draw::expr(self : Draw) -> @ast.Expr {
  if self.budget <= 0 {
    return self.atom()
  }
  self.budget -= 1
  match self.below(12) {
    0 | 1 | 2 => self.atom()
    3 =>
      @ast.Expr::binop(
        self.expr(),
        [@ast.Operator::Add, Sub, Mult, FloorDiv, Mod, Pow][self.below(6)],
        self.expr(),
      )
    4 =>
      @ast.Expr::compare(
        self.expr(),
        [@ast.CmpOp::Eq, NotEq, Lt, LtE, Gt, GtE, In, NotIn][self.below(8)],
        self.expr(),
      )
    5 =>
      @ast.Expr::bool_op(if self.below(2) == 0 { And } else { Or }, [
        self.expr(),
        self.expr(),
      ])
    6 => @ast.Expr::not_(self.expr())
    7 => @ast.Expr::neg(self.expr())
    8 => @ast.Expr::if_exp(self.condition(), self.expr(), self.expr())
    9 => @ast.Expr::list([self.expr(), self.expr()])
    10 =>
      // A constructor call and a field read: the object cases the operators
      // and the printer both have to handle.
      if self.below(2) == 0 {
        @ast.Expr::call(@ast.Expr::name("P"), [self.expr(), self.expr()])
      } else {
        @ast.Expr::attribute(
          @ast.Expr::call(@ast.Expr::name("P"), [self.expr(), self.expr()]),
          self.pick(["x", "y"]),
        )
      }
    _ => @ast.Expr::call(@ast.Expr::name("f"), [self.expr()])
  }
}

///|
/// A condition that has a good chance of being a `bool`.
///
/// PurePy has no truthiness: `if 1:` is not false, it is undefined, and a
/// generator that reaches for any expression spends most of its output there.
/// Biasing towards comparisons is what makes the sample mostly programs that
/// RUN -- and `expr` is still reachable, so the undefined case stays covered.
fn Draw::condition(self : Draw) -> @ast.Expr {
  match self.below(5) {
    0 => @ast.Expr::bool(self.below(2) == 0)
    1 | 2 =>
      @ast.Expr::compare(
        self.expr(),
        [@ast.CmpOp::Eq, NotEq, Lt, LtE, Gt, GtE][self.below(6)],
        self.expr(),
      )
    3 => @ast.Expr::not_(self.condition())
    _ => self.expr()
  }
}

///|
/// What `f`'s body may hold: no call, so no recursion and no divergence.
fn Draw::simple_expr(self : Draw) -> @ast.Expr {
  match self.below(4) {
    0 => @ast.Expr::name("n")
    1 =>
      @ast.Expr::binop(
        @ast.Expr::name("n"),
        [@ast.Operator::Add, Sub, Mult][self.below(3)],
        @ast.Expr::int(1 + self.below(9)),
      )
    2 => @ast.Expr::list([@ast.Expr::name("n")])
    _ =>
      @ast.Expr::compare(
        @ast.Expr::name("n"),
        Eq,
        @ast.Expr::int(self.below(3)),
      )
  }
}

///|
fn Draw::atom(self : Draw, pool? : Bool = true) -> @ast.Expr {
  let n = if pool { 9 } else { 7 }
  match self.below(n) {
    // Never a negative literal: Python has none, so `-1` is a negation.
    0 => @ast.Expr::int(self.below(100))
    1 => @ast.Expr::float(self.below(200).to_double() / 8.0)
    2 => @ast.Expr::str(self.pick(["", "a", "it's", "line\nbreak"]))
    3 => @ast.Expr::bool(self.below(2) == 0)
    4 => @ast.Expr::none()
    5 => @ast.Expr::tuple([@ast.Expr::int(self.below(10))])
    6 =>
      @ast.Expr::dict([(@ast.Expr::str("k"), @ast.Expr::int(self.below(10)))])
    _ => @ast.Expr::name(self.pick(names))
  }
}

///|
fn Draw::pattern(self : Draw) -> @ast.Pattern {
  if self.budget <= 0 {
    return @ast.Pattern::capture(self.pick(names))
  }
  self.budget -= 1
  match self.below(7) {
    0 => @ast.Pattern::capture(self.pick(names))
    1 => @ast.Pattern::wildcard()
    2 => @ast.Pattern::literal(Int(BigInt::from_int(self.below(10))))
    3 => @ast.Pattern::literal(Str(self.pick(["a", "b"])))
    4 => @ast.Pattern::sequence(List, [self.pattern()])
    5 => @ast.Pattern::constr("P", [self.pattern(), self.pattern()])
    _ => @ast.Pattern::sequence(Tuple, [self.pattern(), self.pattern()])
  }
}

// ---------------------------------------------------------------------------
// quickcheck

///|
impl @quickcheck.Arbitrary for Program with fn arbitrary(size, state) {
  // `size` is quickcheck's growth parameter: an early sample is small, a late
  // one is deep. It becomes the recursion budget directly.
  Draw::{ state, budget: 4 + size, }.program()
}

///|
/// The simpler programs to try when this one has diverged.
///
/// Two moves, coarse first. DROPPING a statement is what cuts a generated
/// module down to the one line that matters; the prelude is never dropped,
/// because without it nothing else is well formed and the checker would
/// discard every candidate rather than any of them getting tested. Then
/// SIMPLIFYING an expression -- replacing a compound with one of its own
/// parts -- is what turns that line from `f(not True) * (b if a else 3)` into
/// `False * 3`. The driver re-runs the oracle over every candidate, so a
/// shrink can only ever produce a program that still diverges.
impl @quickcheck.Shrink for Program with fn shrink(self) {
  let body = self.tree.body
  let out : Array[Program] = []
  for i in PRELUDE..<body.length() {
    let kept : Array[@ast.Stmt] = []
    for j in 0..<body.length() {
      if j != i {
        kept.push(body[j])
      }
    }
    // A module with nothing left to print says nothing, and a silent program
    // matches every other silent program.
    if kept.length() > PRELUDE {
      out.push({ tree: @ast.module_of(kept), })
    }
  }
  for i in PRELUDE..<body.length() {
    for simpler in stmt_shrinks(body[i]) {
      let kept : Array[@ast.Stmt] = []
      for j in 0..<body.length() {
        kept.push(if j == i { simpler } else { body[j] })
      }
      out.push({ tree: @ast.module_of(kept), })
    }
  }
  out.iter()
}

///|
/// The statement with one of its expressions made simpler.
fn stmt_shrinks(s : @ast.Stmt) -> Array[@ast.Stmt] {
  let out : Array[@ast.Stmt] = []
  match s {
    Assign(targets~, value~, ..) =>
      if targets.length() == 1 {
        match targets[0] {
          Name(id~, ..) =>
            for e in expr_shrinks(value) {
              out.push(@ast.Stmt::assign(id, e))
            }
          _ => ()
        }
      }
    ExprStmt(value~, ..) =>
      // A `print(e)` shrinks by shrinking what it prints, not by losing the
      // print: a program that stops printing stops being comparable.
      match value {
        Call(func~, args~, ..) =>
          if args.length() == 1 {
            for e in expr_shrinks(args[0]) {
              out.push(@ast.Stmt::expr_stmt(@ast.Expr::call(func, [e])))
            }
          }
        _ => ()
      }
    _ => ()
  }
  out
}

///|
/// An expression replaced by a part of itself, and a compound literal by a
/// smaller one. Only one level: the driver iterates to a fixpoint.
fn expr_shrinks(e : @ast.Expr) -> Array[@ast.Expr] {
  match e {
    BinOp(left~, right~, ..) => [left, right]
    Compare(left~, comparators~, ..) =>
      if comparators.length() == 1 {
        [left, comparators[0]]
      } else {
        [left]
      }
    BoolOp(values~, ..) => values
    UnaryOp(operand~, ..) => [operand]
    IfExp(cond~, body~, or_else~, ..) => [body, or_else, cond]
    Call(args~, ..) => args
    List(elts~, ..) | Tuple(elts~, ..) => elts
    Attribute(value~, ..) => [value]
    _ => []
  }
}

///|
/// The imports, the dataclass and `f`: the statements every generated module
/// opens with and no shrink may remove.
const PRELUDE : Int = 4

// ---------------------------------------------------------------------------

///|
/// The unparser ends a module with a newline; `println` would add a second.
fn print_source(text : String) -> Unit {
  println(text.trim_end(chars="\n").to_owned())
}

///|
/// `fuzzgen gen SEED COUNT` prints COUNT programs; `fuzzgen shrink SOURCE`
/// prints the shrink candidates of the program in SOURCE. Both separate
/// programs with a line the driver splits on.
///
/// The program comes in as an ARGUMENT rather than a path, so this binary
/// touches neither the filesystem nor the process: `moonbitlang/x` belongs to
/// `lib/program` and the CLI, and `tools/boundary-check.sh` holds everyone
/// else to it. The driver has the source in hand anyway.
fn main {
  let sep = "# ---8<---"
  match @env.args()[1:].to_owned() {
    ["gen", seed, count] => {
      let seed = @string.parse_uint64(seed) catch { _ => 1UL }
      let count = @string.parse_int(count) catch { _ => 10 }
      let state = @splitmix.new(seed~)
      for i in 0..<count {
        // The size grows with the index, the way quickcheck's own driver
        // grows it: small programs first, so a shallow bug is found shallow.
        let p : Program = @quickcheck.Arbitrary::arbitrary(i % 12, state)
        println(sep)
        print_source(@write.unparse(p.tree))
      }
    }
    ["shrink", source] => {
      // A source this cannot parse has no candidates, which is the same
      // answer as a program that cannot be shrunk any further.
      let tree = @purepy.parse(source, name="shrunk") catch { _ => return }
      for cand in @quickcheck.Shrink::shrink(Program::{ tree, }) {
        println(sep)
        print_source(@write.unparse(cand.tree))
      }
    }
    _ => println("usage: fuzzgen gen SEED COUNT | fuzzgen shrink SOURCE")
  }
}
