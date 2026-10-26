///|
/// A code generator: it builds a PurePy program with the `ast` builders and
/// prints it with `write`, and links nothing else.
///
/// This is a consumer, not a test of what it prints. What it is FOR is
/// `tools/embed-smoke.sh`, which reads the `-i` flags off the real compile
/// command and checks that neither the tokenizer, the parser, the checker nor
/// the evaluator is among them. A tree and a printer should cost a tree and a
/// printer.
fn main {
  println(@write.unparse(generated()))
}

///|
/// A dataclass, a mutual region and a match -- the three shapes a generator
/// actually produces -- with the annotations PurePy requires.
fn generated() -> @ast.Module {
  let int_ = @ast.Expr::name("int")
  let bool_ = @ast.Expr::name("bool")
  @ast.module_of([
    @ast.Stmt::from_import("dataclasses", ["dataclass"]),
    @ast.Stmt::dataclass("Point", [("x", int_), ("y", int_)]),
    @ast.Stmt::def_(
      "total",
      [("p", @ast.Expr::name("Point"))],
      [
        @ast.Stmt::match_(@ast.Expr::name("p"), [
          @ast.case_(
            @ast.Pattern::constr("Point", [
              @ast.Pattern::capture("h"),
              @ast.Pattern::capture("t"),
            ]),
            [
              @ast.Stmt::return_(
                value=@ast.Expr::binop(
                  @ast.Expr::name("h"),
                  Add,
                  @ast.Expr::name("t"),
                ),
              ),
            ],
          ),
        ]),
      ],
      returns=int_,
    ),
    @ast.Stmt::def_(
      "even",
      [("n", int_)],
      [
        @ast.Stmt::if_(
          @ast.Expr::compare(@ast.Expr::name("n"), Eq, @ast.Expr::int(0)),
          [@ast.Stmt::return_(value=@ast.Expr::bool(true))],
        ),
        @ast.Stmt::return_(
          value=@ast.Expr::call(@ast.Expr::name("odd"), [
            @ast.Expr::binop(@ast.Expr::name("n"), Sub, @ast.Expr::int(1)),
          ]),
        ),
      ],
      returns=bool_,
    ),
    @ast.Stmt::def_(
      "odd",
      [("n", int_)],
      [
        @ast.Stmt::if_(
          @ast.Expr::compare(@ast.Expr::name("n"), Eq, @ast.Expr::int(0)),
          [@ast.Stmt::return_(value=@ast.Expr::bool(false))],
        ),
        @ast.Stmt::return_(
          value=@ast.Expr::call(@ast.Expr::name("even"), [
            @ast.Expr::binop(@ast.Expr::name("n"), Sub, @ast.Expr::int(1)),
          ]),
        ),
      ],
      returns=bool_,
    ),
    @ast.Stmt::ann_assign(
      "p",
      @ast.Expr::name("Point"),
      @ast.Expr::call(@ast.Expr::name("Point"), [
        @ast.Expr::int(1),
        @ast.Expr::int(2),
      ]),
    ),
    @ast.Stmt::expr_stmt(
      @ast.Expr::call(@ast.Expr::name("print"), [
        @ast.Expr::list([
          @ast.Expr::call(@ast.Expr::name("total"), [@ast.Expr::name("p")]),
          @ast.Expr::call(@ast.Expr::name("even"), [@ast.Expr::int(4)]),
        ]),
      ]),
    ),
  ])
}
