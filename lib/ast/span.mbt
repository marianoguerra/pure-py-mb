///|
/// Where a statement is.
pub fn Stmt::span(self : Stmt) -> @basic.Span {
  match self {
    FunctionDef(span~, ..)
    | ClassDef(span~, ..)
    | Return(span~, ..)
    | Delete(span~, ..)
    | Assign(span~, ..)
    | AugAssign(span~, ..)
    | AnnAssign(span~, ..)
    | For(span~, ..)
    | While(span~, ..)
    | If(span~, ..)
    | With(span~, ..)
    | Match(span~, ..)
    | Raise(span~, ..)
    | Try(span~, ..)
    | Assert(span~, ..)
    | Import(span~, ..)
    | ImportFrom(span~, ..)
    | Global(span~, ..)
    | Nonlocal(span~, ..)
    | ExprStmt(span~, ..)
    | Pass(span~)
    | Break(span~)
    | Continue(span~) => span
  }
}

///|
/// Where an expression is.
pub fn Expr::span(self : Expr) -> @basic.Span {
  match self {
    BoolOp(span~, ..)
    | NamedExpr(span~, ..)
    | BinOp(span~, ..)
    | UnaryOp(span~, ..)
    | Lambda(span~, ..)
    | IfExp(span~, ..)
    | Dict(span~, ..)
    | Set(span~, ..)
    | ListComp(span~, ..)
    | SetComp(span~, ..)
    | DictComp(span~, ..)
    | GeneratorExp(span~, ..)
    | Await(span~, ..)
    | Yield(span~, ..)
    | YieldFrom(span~, ..)
    | Compare(span~, ..)
    | Call(span~, ..)
    | JoinedStr(span~, ..)
    | Constant(span~, ..)
    | Attribute(span~, ..)
    | Subscript(span~, ..)
    | Starred(span~, ..)
    | Name(span~, ..)
    | List(span~, ..)
    | Tuple(span~, ..)
    | Slice(span~, ..) => span
  }
}

///|
/// Where a pattern is.
pub fn Pattern::span(self : Pattern) -> @basic.Span {
  match self {
    MatchValue(span~, ..)
    | MatchSingleton(span~, ..)
    | MatchSequence(span~, ..)
    | MatchMapping(span~, ..)
    | MatchClass(span~, ..)
    | MatchStar(span~, ..)
    | MatchAs(span~, ..)
    | MatchOr(span~, ..) => span
  }
}

///|
/// The name CPython's `ast` gives this node's class -- what the sieve's
/// "unknown statement type: {T}" and "unknown expression type: {T}" print.
pub fn Stmt::kind_name(self : Stmt) -> String {
  match self {
    FunctionDef(is_async=true, ..) => "AsyncFunctionDef"
    FunctionDef(..) => "FunctionDef"
    ClassDef(..) => "ClassDef"
    Return(..) => "Return"
    Delete(..) => "Delete"
    Assign(..) => "Assign"
    AugAssign(..) => "AugAssign"
    AnnAssign(..) => "AnnAssign"
    For(is_async=true, ..) => "AsyncFor"
    For(..) => "For"
    While(..) => "While"
    If(..) => "If"
    With(is_async=true, ..) => "AsyncWith"
    With(..) => "With"
    Match(..) => "Match"
    Raise(..) => "Raise"
    Try(is_star=true, ..) => "TryStar"
    Try(..) => "Try"
    Assert(..) => "Assert"
    Import(..) => "Import"
    ImportFrom(..) => "ImportFrom"
    Global(..) => "Global"
    Nonlocal(..) => "Nonlocal"
    ExprStmt(..) => "Expr"
    Pass(_) => "Pass"
    Break(_) => "Break"
    Continue(_) => "Continue"
  }
}

///|
pub fn Expr::kind_name(self : Expr) -> String {
  match self {
    BoolOp(..) => "BoolOp"
    NamedExpr(..) => "NamedExpr"
    BinOp(..) => "BinOp"
    UnaryOp(..) => "UnaryOp"
    Lambda(..) => "Lambda"
    IfExp(..) => "IfExp"
    Dict(..) => "Dict"
    Set(..) => "Set"
    ListComp(..) => "ListComp"
    SetComp(..) => "SetComp"
    DictComp(..) => "DictComp"
    GeneratorExp(..) => "GeneratorExp"
    Await(..) => "Await"
    Yield(..) => "Yield"
    YieldFrom(..) => "YieldFrom"
    Compare(..) => "Compare"
    Call(..) => "Call"
    JoinedStr(..) => "JoinedStr"
    Constant(..) => "Constant"
    Attribute(..) => "Attribute"
    Subscript(..) => "Subscript"
    Starred(..) => "Starred"
    Name(..) => "Name"
    List(..) => "List"
    Tuple(..) => "Tuple"
    Slice(..) => "Slice"
  }
}

///|
pub fn Pattern::kind_name(self : Pattern) -> String {
  match self {
    MatchValue(..) => "MatchValue"
    MatchSingleton(..) => "MatchSingleton"
    MatchSequence(..) => "MatchSequence"
    MatchMapping(..) => "MatchMapping"
    MatchClass(..) => "MatchClass"
    MatchStar(..) => "MatchStar"
    MatchAs(..) => "MatchAs"
    MatchOr(..) => "MatchOr"
  }
}

///|
/// The name CPython's `ast` gives a constant's type -- what the sieve's
/// "prohibited literal type: {T}" prints.
pub fn Constant::type_name(self : Constant) -> String {
  match self {
    Int(_) => "int"
    Float(_) => "float"
    Complex(_) => "complex"
    Str(_) => "str"
    Bytes(_) => "bytes"
    Bool(_) => "bool"
    None => "NoneType"
    Ellipsis => "ellipsis"
  }
}

///|
/// The symbol a binary operator is written with -- what the sieve's
/// "binary operator '{sym}' prohibited" prints.
pub fn Operator::symbol(self : Operator) -> String {
  match self {
    Add => "+"
    Sub => "-"
    Mult => "*"
    MatMult => "@"
    Div => "/"
    Mod => "%"
    Pow => "**"
    LShift => "<<"
    RShift => ">>"
    BitOr => "|"
    BitXor => "^"
    BitAnd => "&"
    FloorDiv => "//"
  }
}

///|
pub fn UnaryOp::symbol(self : UnaryOp) -> String {
  match self {
    Invert => "~"
    Not => "not"
    UAdd => "+"
    USub => "-"
  }
}

///|
pub fn CmpOp::symbol(self : CmpOp) -> String {
  match self {
    Eq => "=="
    NotEq => "!="
    Lt => "<"
    LtE => "<="
    Gt => ">"
    GtE => ">="
    Is => "is"
    IsNot => "is not"
    In => "in"
    NotIn => "not in"
  }
}

///|
pub fn BoolOp::symbol(self : BoolOp) -> String {
  match self {
    And => "and"
    Or => "or"
  }
}

///|
/// The name of the class CPython's `ast` uses for an operator, which is what
/// its `dump` prints.
pub fn Operator::name(self : Operator) -> String {
  match self {
    Add => "Add"
    Sub => "Sub"
    Mult => "Mult"
    MatMult => "MatMult"
    Div => "Div"
    Mod => "Mod"
    Pow => "Pow"
    LShift => "LShift"
    RShift => "RShift"
    BitOr => "BitOr"
    BitXor => "BitXor"
    BitAnd => "BitAnd"
    FloorDiv => "FloorDiv"
  }
}

///|
pub fn UnaryOp::name(self : UnaryOp) -> String {
  match self {
    Invert => "Invert"
    Not => "Not"
    UAdd => "UAdd"
    USub => "USub"
  }
}

///|
pub fn CmpOp::name(self : CmpOp) -> String {
  match self {
    Eq => "Eq"
    NotEq => "NotEq"
    Lt => "Lt"
    LtE => "LtE"
    Gt => "Gt"
    GtE => "GtE"
    Is => "Is"
    IsNot => "IsNot"
    In => "In"
    NotIn => "NotIn"
  }
}

///|
pub fn BoolOp::name(self : BoolOp) -> String {
  match self {
    And => "And"
    Or => "Or"
  }
}

///|
pub fn ExprContext::name(self : ExprContext) -> String {
  match self {
    Load => "Load"
    Store => "Store"
    Del => "Del"
  }
}

///|
pub fn SeqKind::name(self : SeqKind) -> String {
  match self {
    List => "List"
    Tuple => "Tuple"
  }
}
