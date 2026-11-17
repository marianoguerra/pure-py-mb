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

///|
/// `from import x` names no module and has no dots: CPython refuses it at
/// the `import`, and accepting it let a tree with neither through to a
/// checker that aborts on one (the fuzzer found it).
test "a from-import names a module or a level" {
  for source in ["from import b\n", "from  import b\n"] {
    try @parser.parse_string(source) |> ignore catch {
      @err.PurePyError(d) => {
        assert_eq(d.message(), "invalid syntax", msg=source)
        assert_eq(
          d.span.unwrap().start.col,
          source.find("import").unwrap(),
          msg=source,
        )
      }
      e => fail("unexpected \{e}")
    } noraise {
      _ => fail("expected a syntax error: \{source}")
    }
  }
  assert_true(
    @parser.parse_string("from . import b\n").body[0]
    is ImportFrom(level=1, module_name=None, ..),
  )
}
