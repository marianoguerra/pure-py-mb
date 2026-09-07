///|
fn round(source : String) -> String {
  @write.unparse(@ast.module_of([])) |> ignore
  source
}

///|
test "a tree built by hand prints as Python" {
  let m = @ast.module_of([
    @ast.Stmt::dataclass("Point", ["x", "y"]),
    @ast.Stmt::def_("mag", ["p"], [
      @ast.Stmt::return_(
        value=@ast.Expr::binop(
          @ast.Expr::attribute(@ast.Expr::name("p"), "x"),
          Add,
          @ast.Expr::attribute(@ast.Expr::name("p"), "y"),
        ),
      ),
    ]),
    @ast.Stmt::expr_stmt(
      @ast.Expr::call(@ast.Expr::name("print"), [
        @ast.Expr::call(@ast.Expr::name("mag"), [
          @ast.Expr::call(@ast.Expr::name("Point"), [
            @ast.Expr::int(1),
            @ast.Expr::int(2),
          ]),
        ]),
      ]),
    ),
  ])
  inspect(
    @write.unparse(m),
    content=(
      #|@dataclass
      #|class Point:
      #|    x: Any
      #|    y: Any
      #|def mag(p):
      #|    return p.x + p.y
      #|print(mag(Point(1, 2)))
      #|
    ),
  )
  assert_eq(round("x"), "x")
}

///|
test "a match statement prints with its patterns" {
  let m = @ast.module_of([
    @ast.Stmt::match_(@ast.Expr::name("v"), [
      @ast.case_(@ast.Pattern::literal(Int(0N)), [
        @ast.Stmt::return_(value=@ast.Expr::str("zero")),
      ]),
      @ast.case_(
        @ast.Pattern::constr("Point", [
          @ast.Pattern::capture("a"),
          @ast.Pattern::wildcard(),
        ]),
        [@ast.Stmt::return_(value=@ast.Expr::name("a"))],
      ),
      @ast.case_(@ast.Pattern::sequence(List, [@ast.Pattern::capture("h")]), [
        @ast.Stmt::return_(value=@ast.Expr::name("h")),
      ]),
      @ast.case_(@ast.Pattern::wildcard(), [@ast.Stmt::pass()]),
    ]),
  ])
  inspect(
    @write.unparse(m),
    content=(
      #|match v:
      #|    case 0:
      #|        return 'zero'
      #|    case Point(a, _):
      #|        return a
      #|    case [h]:
      #|        return h
      #|    case _:
      #|        pass
      #|
    ),
  )
}
