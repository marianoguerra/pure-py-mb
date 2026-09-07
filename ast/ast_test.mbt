///|
/// The plan's own example: a tree built by hand, and its dump.
test "print(\"Hello, World!\") built and dumped" {
  let m = @ast.module_of([
    @ast.Stmt::expr_stmt(
      @ast.Expr::call(@ast.Expr::name("print"), [
        @ast.Expr::str("Hello, World!"),
      ]),
    ),
  ])
  inspect(
    @ast.dump(m),
    content=(
      #|Module
      #|  body:
      #|    Expr
      #|      value:
      #|        Call
      #|          func:
      #|            Name id=print ctx=Load
      #|          args:
      #|            Constant value='Hello, World!'
      #|          keywords:
      #|
    ),
  )
}

///|
/// A dataclass, a mutual region and a match: the shapes a code generator
/// actually produces, and the ones `test/embed` will print.
test "a dataclass builds the only class form PurePy accepts" {
  let m = @ast.module_of([
    @ast.Stmt::dataclass("Point", ["x", "y"]),
    @ast.Stmt::dataclass("Point3", ["z"], base="Point"),
  ])
  inspect(
    @ast.dump(m),
    content=(
      #|Module
      #|  body:
      #|    ClassDef name=Point
      #|      bases:
      #|      keywords:
      #|      body:
      #|        AnnAssign simple=True
      #|          target:
      #|            Name id=x ctx=Store
      #|          annotation:
      #|            Name id=Any ctx=Load
      #|          value: -
      #|        AnnAssign simple=True
      #|          target:
      #|            Name id=y ctx=Store
      #|          annotation:
      #|            Name id=Any ctx=Load
      #|          value: -
      #|      decorator_list:
      #|        Name id=dataclass ctx=Load
      #|    ClassDef name=Point3
      #|      bases:
      #|        Name id=Point ctx=Load
      #|      keywords:
      #|      body:
      #|        AnnAssign simple=True
      #|          target:
      #|            Name id=z ctx=Store
      #|          annotation:
      #|            Name id=Any ctx=Load
      #|          value: -
      #|      decorator_list:
      #|        Name id=dataclass ctx=Load
      #|
    ),
  )
}

///|
test "constants print the way Python's repr prints them" {
  assert_eq(@ast.Constant::Int(42N).to_literal(), "42")
  assert_eq(@ast.Constant::Float(1.0).to_literal(), "1.0")
  assert_eq(@ast.Constant::Float(1.0e16).to_literal(), "1e+16")
  assert_eq(@ast.Constant::Complex(3.0).to_literal(), "3.0j")
  assert_eq(@ast.Constant::Str("it's").to_literal(), "\"it's\"")
  assert_eq(@ast.Constant::Bytes(b"a\x00").to_literal(), "b'a\\x00'")
  assert_eq(@ast.Constant::Bool(true).to_literal(), "True")
  assert_eq(@ast.Constant::None.to_literal(), "None")
  assert_eq(@ast.Constant::Ellipsis.to_literal(), "Ellipsis")
}
