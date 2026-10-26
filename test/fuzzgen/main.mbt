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
/// The types a generated expression is drawn at. PurePy is typed, and a
/// generator that drew any expression anywhere would have the checker discard
/// nearly everything it made; drawing each one AT a type is what keeps the
/// sample mostly programs that run.
priv enum Ty {
  TInt
  TFloat
  TStr
  TBool
  TList
  TP
} derive(Eq)

///|
/// The names a generated program may use, each at one type for the whole
/// program. Small, so that the same name is bound and read often enough for
/// scoping to be exercised, and bound in the prelude so that a reference to
/// one is not automatically ill formed.
let pool : Array[(String, Ty)] = [
  ("a", TInt),
  ("b", TStr),
  ("c", TBool),
  ("d", TFloat),
]

///|
fn Ty::annotation(self : Ty) -> @ast.Expr {
  match self {
    TInt => @ast.Expr::name("int")
    TFloat => @ast.Expr::name("float")
    TStr => @ast.Expr::name("str")
    TBool => @ast.Expr::name("bool")
    TList =>
      @ast.Expr::subscript(@ast.Expr::name("list"), @ast.Expr::name("int"))
    TP => @ast.Expr::name("P")
  }
}

///|
/// A seeded cursor over the random state, with a budget so recursion ends.
struct Draw {
  state : @splitmix.RandomState
  mut budget : Int32
  /// The names bound so far, each at its type. A PurePy variable is declared
  /// once and assigned once, so every statement that binds binds a FRESH name.
  vars : Array[(String, Ty)]
  mut fresh : Int32
}

///|
fn Draw::fresh_name(self : Draw) -> String {
  self.fresh += 1
  "v\{self.fresh}"
}

///|
fn Draw::below(self : Draw, n : Int32) -> Int32 {
  let v = self.state.next_uint().reinterpret_as_int()
  let x = if v < 0 { -(v + 1) } else { v }
  x % n
}

///|
fn Draw::pick(self : Draw, options : Array[String]) -> String {
  options[self.below(options.length())]
}

///|
fn Draw::ty(self : Draw) -> Ty {
  [TInt, TFloat, TStr, TBool, TList, TP][self.below(6)]
}

// ---------------------------------------------------------------------------
// The shape of a generated module

///|
/// A dataclass, a function, the name pool bound, and then the statements
/// worth varying -- ending in the prints that make the module comparable at
/// all.
fn Draw::program(self : Draw) -> Program {
  let int_ = @ast.Expr::name("int")
  let body : Array[@ast.Stmt] = [
    @ast.Stmt::from_import("dataclasses", ["dataclass"]),
    @ast.Stmt::dataclass("P", [("x", int_), ("y", int_)]),
    // A function whose body cannot call anything, so a generated program
    // always terminates.
    @ast.Stmt::def_(
      "f",
      [("n", int_)],
      [@ast.Stmt::return_(value=self.simple_expr())],
      returns=int_,
    ),
  ]
  // The pool, bound to literals, so a later reference is well formed.
  for v in pool {
    body.push(self.bind(v.0, v.1, self.literal(v.1)))
    self.vars.push(v)
  }
  for _ in 0..<(1 + self.below(3)) {
    body.append(self.stmts())
  }
  for _ in 0..<(1 + self.below(2)) {
    body.push(@ast.Stmt::expr_stmt(self.print_of(self.expr(self.ty()))))
  }
  { tree: @ast.module_of(body), }
}

///|
/// `x: T = e`, which keeps a pool name at its one type.
fn Draw::bind(self : Draw, x : String, t : Ty, e : @ast.Expr) -> @ast.Stmt {
  ignore(self)
  @ast.Stmt::ann_assign(x, t.annotation(), e)
}

///|
fn Draw::print_of(self : Draw, e : @ast.Expr) -> @ast.Expr {
  ignore(self)
  @ast.Expr::call(@ast.Expr::name("print"), [e])
}

///|
/// A fresh name bound to an expression of a type, and then in scope.
fn Draw::bind_fresh(self : Draw, t : Ty, e : @ast.Expr) -> @ast.Stmt {
  let x = self.fresh_name()
  let s = self.bind(x, t, e)
  self.vars.push((x, t))
  s
}

///|
/// Statements, some of them a declaration and its assignment, which is why
/// one draw may give several.
fn Draw::stmts(self : Draw) -> Array[@ast.Stmt] {
  if self.budget <= 0 {
    let t = self.ty()
    return [self.bind_fresh(t, self.literal(t))]
  }
  self.budget -= 1
  match self.below(6) {
    0 | 1 => {
      let t = self.ty()
      [self.bind_fresh(t, self.expr(t))]
    }
    2 => {
      // Declared before the `if`, assigned once on each path, so it is
      // definitely assigned after it.
      let t = self.ty()
      let x = self.fresh_name()
      let decl = @ast.Stmt::declaration(x, t.annotation())
      let s = @ast.Stmt::if_(
        self.expr(TBool),
        [@ast.Stmt::assign(x, self.expr(t))],
        or_else=[@ast.Stmt::assign(x, self.expr(t))],
      )
      self.vars.push((x, t))
      [decl, s]
    }
    3 => {
      let t = [TInt, TStr, TP][self.below(3)]
      [
        @ast.Stmt::match_(self.expr(t), [
          @ast.case_(self.pattern(t), [
            @ast.Stmt::expr_stmt(self.print_of(@ast.Expr::str("m"))),
          ]),
          @ast.case_(@ast.Pattern::wildcard(), [@ast.Stmt::pass()]),
        ]),
      ]
    }
    4 => [@ast.Stmt::expr_stmt(self.print_of(self.expr(self.ty())))]
    _ => [@ast.Stmt::pass()]
  }
}

///|
/// A literal of a type.
fn Draw::literal(self : Draw, t : Ty) -> @ast.Expr {
  match t {
    // Never a negative literal: Python has none, so `-1` is a negation.
    TInt => @ast.Expr::int(self.below(100))
    TFloat => @ast.Expr::float(self.below(200).to_double() / 8.0)
    TStr => @ast.Expr::str(self.pick(["", "a", "it's", "line\nbreak"]))
    TBool => @ast.Expr::bool(self.below(2) == 0)
    TList =>
      @ast.Expr::list([
        @ast.Expr::int(self.below(10)),
        @ast.Expr::int(self.below(10)),
      ])
    TP =>
      @ast.Expr::call(@ast.Expr::name("P"), [
        @ast.Expr::int(self.below(10)),
        @ast.Expr::int(self.below(10)),
      ])
  }
}

///|
/// A leaf of a type: a literal, or a name bound at it.
fn Draw::atom(self : Draw, t : Ty) -> @ast.Expr {
  if self.below(2) == 0 {
    let named = self.vars.filter(fn(v) { v.1 == t })
    if !named.is_empty() {
      return @ast.Expr::name(named[self.below(named.length())].0)
    }
  }
  self.literal(t)
}

///|
/// An expression of a type, over the pool, `f`, `P` and the literals.
fn Draw::expr(self : Draw, t : Ty) -> @ast.Expr {
  if self.budget <= 0 {
    return self.atom(t)
  }
  self.budget -= 1
  // A conditional expression is at every type.
  if self.below(10) == 0 {
    return @ast.Expr::if_exp(self.expr(TBool), self.expr(t), self.expr(t))
  }
  match t {
    TInt =>
      match self.below(9) {
        0 | 1 => self.atom(TInt)
        2 =>
          @ast.Expr::binop(
            self.expr(TInt),
            [@ast.Operator::Add, Sub, Mult, FloorDiv, Mod][self.below(5)],
            self.expr(TInt),
          )
        // `int ** int` is an int only at a literal exponent.
        3 =>
          @ast.Expr::binop(self.expr(TInt), Pow, @ast.Expr::int(self.below(4)))
        4 => @ast.Expr::neg(self.expr(TInt))
        5 =>
          @ast.Expr::call(@ast.Expr::name("len"), [
            self.expr(if self.below(2) == 0 { TStr } else { TList }),
          ])
        6 => @ast.Expr::call(@ast.Expr::name("f"), [self.expr(TInt)])
        7 => @ast.Expr::attribute(self.expr(TP), self.pick(["x", "y"]))
        _ =>
          @ast.Expr::subscript(self.expr(TList), @ast.Expr::int(self.below(3)))
      }
    TFloat =>
      match self.below(5) {
        0 | 1 => self.atom(TFloat)
        2 =>
          @ast.Expr::binop(
            self.expr(TFloat),
            [@ast.Operator::Add, Sub, Mult, FloorDiv, Mod][self.below(5)],
            self.expr(if self.below(2) == 0 { TInt } else { TFloat }),
          )
        3 => @ast.Expr::binop(self.expr(TInt), Div, self.expr(TInt))
        _ => @ast.Expr::neg(self.expr(TFloat))
      }
    TStr =>
      match self.below(5) {
        0 | 1 => self.atom(TStr)
        2 => @ast.Expr::binop(self.expr(TStr), Add, self.expr(TStr))
        3 =>
          @ast.Expr::binop(self.expr(TStr), Mult, @ast.Expr::int(self.below(3)))
        _ =>
          @ast.Expr::subscript(self.expr(TStr), @ast.Expr::int(self.below(3)))
      }
    TBool =>
      match self.below(8) {
        0 | 1 => self.atom(TBool)
        2 =>
          @ast.Expr::compare(
            self.expr(TInt),
            [@ast.CmpOp::Eq, NotEq, Lt, LtE, Gt, GtE][self.below(6)],
            self.expr(if self.below(2) == 0 { TInt } else { TFloat }),
          )
        3 =>
          @ast.Expr::compare(
            self.expr(TStr),
            [@ast.CmpOp::Eq, NotEq, Lt, LtE, In, NotIn][self.below(6)],
            self.expr(TStr),
          )
        4 =>
          @ast.Expr::compare(
            self.expr(TInt),
            [@ast.CmpOp::In, NotIn][self.below(2)],
            self.expr(TList),
          )
        5 => @ast.Expr::not_(self.expr(TBool))
        6 =>
          @ast.Expr::bool_op(if self.below(2) == 0 { And } else { Or }, [
            self.expr(TBool),
            self.expr(TBool),
          ])
        _ =>
          @ast.Expr::compare(
            self.expr(TP),
            [@ast.CmpOp::Eq, NotEq][self.below(2)],
            self.expr(TP),
          )
      }
    TList =>
      match self.below(4) {
        0 => self.atom(TList)
        1 => @ast.Expr::list([self.expr(TInt), self.expr(TInt)])
        2 => @ast.Expr::binop(self.expr(TList), Add, self.expr(TList))
        _ =>
          @ast.Expr::list_comp(
            @ast.Expr::binop(@ast.Expr::name("i"), Mult, self.expr(TInt)),
            "i",
            self.expr(TList),
          )
      }
    TP =>
      if self.below(3) == 0 {
        self.atom(TP)
      } else {
        @ast.Expr::call(@ast.Expr::name("P"), [self.expr(TInt), self.expr(TInt)])
      }
  }
}

///|
/// What `f`'s body may hold: no call, so no recursion and no divergence.
fn Draw::simple_expr(self : Draw) -> @ast.Expr {
  match self.below(3) {
    0 => @ast.Expr::name("n")
    1 =>
      @ast.Expr::binop(
        @ast.Expr::name("n"),
        [@ast.Operator::Add, Sub, Mult][self.below(3)],
        @ast.Expr::int(1 + self.below(9)),
      )
    _ => @ast.Expr::neg(@ast.Expr::name("n"))
  }
}

///|
/// A first case for a subject of the type. Never a bare capture or a
/// wildcard, which would leave the second case -- the wildcard -- unreachable.
fn Draw::pattern(self : Draw, t : Ty) -> @ast.Pattern {
  match t {
    TInt => @ast.Pattern::literal(Int(BigInt::from_int(self.below(10))))
    TStr => @ast.Pattern::literal(Str(self.pick(["a", "b", ""])))
    _ =>
      @ast.Pattern::constr("P", [
        if self.below(2) == 0 {
          @ast.Pattern::literal(Int(BigInt::from_int(self.below(10))))
        } else {
          @ast.Pattern::capture(self.fresh_name())
        },
        @ast.Pattern::literal(Int(BigInt::from_int(self.below(10)))),
      ])
  }
}

// ---------------------------------------------------------------------------
// quickcheck

///|
impl @quickcheck.Arbitrary for Program with fn arbitrary(size, state) {
  // `size` is quickcheck's growth parameter: an early sample is small, a late
  // one is deep. It becomes the recursion budget directly.
  Draw::{ state, budget: 4 + size, vars: [], fresh: 0, }.program()
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
    AnnAssign(target=Name(id~, ..), annotation~, value=Some(value), ..) =>
      for e in expr_shrinks(value) {
        out.push(@ast.Stmt::ann_assign(id, annotation, e))
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
/// The import, the dataclass and `f`: the statements every generated module
/// opens with and no shrink may remove.
const PRELUDE : Int32 = 3

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
      let state = @splitmix.RandomState(seed~)
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
