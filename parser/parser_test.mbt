///|
fn dump_of(source : String) -> String raise {
  @ast.dump(@parser.parse_string(source))
}

///|
test "the simplest statements" {
  inspect(
    dump_of("pass\nx = 1; y = 2\n"),
    content=(
      #|Module
      #|  body:
      #|    Pass
      #|    Assign
      #|      targets:
      #|        Name id=x ctx=Store
      #|      value:
      #|        Constant value=1
      #|    Assign
      #|      targets:
      #|        Name id=y ctx=Store
      #|      value:
      #|        Constant value=2
      #|
    ),
  )
}

///|
test "power binds tighter than unary minus on its left" {
  inspect(
    dump_of("x = -2 ** 2\n"),
    content=(
      #|Module
      #|  body:
      #|    Assign
      #|      targets:
      #|        Name id=x ctx=Store
      #|      value:
      #|        UnaryOp op=USub
      #|          operand:
      #|            BinOp op=Pow
      #|              left:
      #|                Constant value=2
      #|              right:
      #|                Constant value=2
      #|
    ),
  )
}

///|
test "a stray dedent is a syntax error with a position" {
  try @parser.parse_string("if a:\n    b = 1\n  c = 2\n") |> ignore catch {
    @err.PurePyError(d) => assert_eq(d.span.unwrap().start.line, 3)
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected a syntax error")
  }
}
