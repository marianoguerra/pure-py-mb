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
/// actually produces.
fn generated() -> @ast.Module {
  @ast.module_of([
    @ast.Stmt::dataclass("Nil", []),
    @ast.Stmt::dataclass("Cons", ["head", "tail"]),
    @ast.Stmt::def_("total", ["xs"], [
      @ast.Stmt::match_(@ast.Expr::name("xs"), [
        @ast.case_(@ast.Pattern::constr("Nil", []), [
          @ast.Stmt::return_(value=@ast.Expr::int(0)),
        ]),
        @ast.case_(
          @ast.Pattern::constr("Cons", [
            @ast.Pattern::capture("h"),
            @ast.Pattern::capture("t"),
          ]),
          [
            @ast.Stmt::return_(
              value=@ast.Expr::binop(
                @ast.Expr::name("h"),
                Add,
                @ast.Expr::call(@ast.Expr::name("total"), [@ast.Expr::name("t")]),
              ),
            ),
          ],
        ),
        @ast.case_(@ast.Pattern::wildcard(), [
          @ast.Stmt::return_(value=@ast.Expr::int(0)),
        ]),
      ]),
    ]),
    @ast.Stmt::def_("even", ["n"], [
      @ast.Stmt::if_(
        @ast.Expr::compare(@ast.Expr::name("n"), Eq, @ast.Expr::int(0)),
        [@ast.Stmt::return_(value=@ast.Expr::bool(true))],
      ),
      @ast.Stmt::return_(
        value=@ast.Expr::call(@ast.Expr::name("odd"), [
          @ast.Expr::binop(@ast.Expr::name("n"), Sub, @ast.Expr::int(1)),
        ]),
      ),
    ]),
    @ast.Stmt::def_("odd", ["n"], [
      @ast.Stmt::if_(
        @ast.Expr::compare(@ast.Expr::name("n"), Eq, @ast.Expr::int(0)),
        [@ast.Stmt::return_(value=@ast.Expr::bool(false))],
      ),
      @ast.Stmt::return_(
        value=@ast.Expr::call(@ast.Expr::name("even"), [
          @ast.Expr::binop(@ast.Expr::name("n"), Sub, @ast.Expr::int(1)),
        ]),
      ),
    ]),
    @ast.Stmt::assign(
      "xs",
      @ast.Expr::call(@ast.Expr::name("Cons"), [
        @ast.Expr::int(1),
        @ast.Expr::call(@ast.Expr::name("Cons"), [
          @ast.Expr::int(2),
          @ast.Expr::call(@ast.Expr::name("Nil"), []),
        ]),
      ]),
    ),
    @ast.Stmt::expr_stmt(
      @ast.Expr::call(@ast.Expr::name("print"), [
        @ast.Expr::call(@ast.Expr::name("total"), [@ast.Expr::name("xs")]),
        @ast.Expr::call(@ast.Expr::name("even"), [@ast.Expr::int(4)]),
      ]),
    ),
  ])
}
