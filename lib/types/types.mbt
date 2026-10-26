///|
/// The types of PurePy, and the annotations that spell them.
///
/// A port of the reference's `type_syntax.py`. Two layers, as there: a
/// `TypeExpr` is what an annotation SAYS, with class names unresolved, and a
/// `Type` is what it MEANS once every name has been looked up in the module's
/// context. The checker resolves one into the other (`resolve_type` in
/// `lib/check`), because only it has the context.
pub(all) enum Primitive {
  Object
  Never
  NoneType
  Bool
  Int
  Float
  Str
  Sized
} derive(Eq, Compare, Debug)

///|
/// The name an annotation spells a primitive with, and the one `render`
/// prints.
pub fn Primitive::name(self : Primitive) -> String {
  match self {
    Object => "object"
    Never => "Never"
    NoneType => "None"
    Bool => "bool"
    Int => "int"
    Float => "float"
    Str => "str"
    Sized => "Sized"
  }
}

///|
/// Every primitive, in the reference's declaration order.
pub let primitives : Array[Primitive] = [
  Object,
  Never,
  NoneType,
  Bool,
  Int,
  Float,
  Str,
  Sized,
]

///|
/// The value of a literal type.
///
/// Equality compares the value's Python type as well as the value, as
/// `LiteralType.__eq__` does, since `True == 1` and `1 == 1.0` hold between
/// values of different types and `Literal[True]` is not `Literal[1]`. Separate
/// arms give that for free.
pub(all) enum Lit {
  NoneLit
  Bool(Bool)
  Int(BigInt)
  Float(Double)
  Str(String)
} derive(Eq, Compare, Debug)

///|
/// Python's `repr` of the value, which is what `Literal[...]` prints.
pub fn Lit::repr(self : Lit) -> String {
  match self {
    NoneLit => "None"
    Bool(true) => "True"
    Bool(false) => "False"
    Int(n) => n.to_string()
    Float(d) => @basic.py_float_repr(d)
    Str(s) => @basic.py_repr(s)
  }
}

///|
/// What an annotation says, before its class names are resolved.
pub(all) enum TypeExpr {
  PrimE(Primitive)
  ListE(TypeExpr)
  TupleE(Array[TypeExpr])
  DictE(TypeExpr)
  CallableE(Array[TypeExpr], TypeExpr)
  LitE(Lit)
  /// A name, possibly applied to type arguments: a class, a type parameter
  /// or a type alias, which only the context can tell apart.
  TypeName(Array[String], Array[TypeExpr])
  UnionE(TypeExpr, TypeExpr)
} derive(Eq, Debug)

///|
/// A type. A class is named by its qualified name, which is what identifies
/// it in the class table: two classes of one name in two modules are two
/// classes.
pub(all) enum Type {
  Prim(Primitive)
  List(Type)
  Tuple(Array[Type])
  Dict(Type)
  Callable(Array[Type], Type)
  Literal(Lit)
  /// A type parameter, by name.
  TypeVar(String)
  /// A class, by its qualified name in the class table, applied to its type
  /// arguments.
  Class(String, Array[Type])
  Union(Type, Type)
  /// A function whose last `n` parameters have defaults, under a profile
  /// with `DefaultArguments` (#56): callable with any count from the
  /// required ones to all of them. Never produced under `core`.
  Defaulted(Array[Type], Int32, Type)
  /// A builtin a profile adds -- `sorted`, `abs`, `zip` -- whose calls are
  /// typed by a rule rather than by a signature (`lib/check`'s
  /// `builtin_call_type`). Never produced under `core`.
  Builtin(String)
} derive(Eq, Compare, Debug)

///|
pub let t_object : Type = Prim(Object)

///|
pub let t_never : Type = Prim(Never)

///|
pub let t_none : Type = Prim(NoneType)

///|
pub let t_bool : Type = Prim(Bool)

///|
pub let t_int : Type = Prim(Int)

///|
pub let t_float : Type = Prim(Float)

///|
pub let t_str : Type = Prim(Str)

///|
pub let t_sized : Type = Prim(Sized)

///|
/// The type variables a type mentions.
pub fn fv(tau : Type) -> Array[String] {
  let out : Array[String] = []
  fn go(t : Type) -> Unit {
    match t {
      TypeVar(a) => if !out.contains(a) { out.push(a) }
      List(s) | Dict(s) => go(s)
      Tuple(ss) | Class(_, ss) =>
        for s in ss {
          go(s)
        }
      Callable(ps, r) | Defaulted(ps, _, r) => {
        go(r)
        for p in ps {
          go(p)
        }
      }
      Union(a, b) => {
        go(a)
        go(b)
      }
      _ => ()
    }
  }

  go(tau)
  out
}

///|
/// A type as a message prints it.
pub fn render(tau : Type) -> String {
  match tau {
    Prim(p) => p.name()
    List(s) => "list[\{render(s)}]"
    Tuple(ts) => "tuple[" + ts.map(render).join(", ") + "]"
    Dict(s) => "dict[str, \{render(s)}]"
    Callable(ps, r) =>
      "Callable[[" + ps.map(render).join(", ") + "], \{render(r)}]"
    Literal(v) => "Literal[\{v.repr()}]"
    TypeVar(a) => a
    Class(c, []) => c
    Class(c, ts) => c + "[" + ts.map(render).join(", ") + "]"
    Union(s, t) => "\{render(s)} | \{render(t)}"
    Defaulted(ps, n, r) => {
      let shown = ps.mapi(fn(i, p) {
        if i >= ps.length() - n {
          render(p) + "="
        } else {
          render(p)
        }
      })
      "Callable[[" + shown.join(", ") + "], \{render(r)}]"
    }
    Builtin(name) => "builtin \{name}"
  }
}

///|
/// The type a literal's value belongs to; any other type is its own base.
pub fn base_type(tau : Type) -> Type {
  match tau {
    Literal(v) => lit_base(v)
    _ => tau
  }
}

///|
pub fn lit_base(v : Lit) -> Type {
  match v {
    NoneLit => t_none
    Bool(_) => t_bool
    Int(_) => t_int
    Float(_) => t_float
    Str(_) => t_str
  }
}

///|
/// The literal a constant is, if it is one a literal type can hold.
pub fn lit_of_constant(c : @ast.Constant) -> Lit? {
  match c {
    None => Some(NoneLit)
    Bool(b) => Some(Bool(b))
    Int(n) => Some(Int(n))
    Float(d) => Some(Float(d))
    Str(s) => Some(Str(s))
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Qualified names

///|
/// `a`, `a.b`, `a.b.c` as its parts; `None` for anything else.
pub fn dotted_name(e : @ast.Expr) -> Array[String]? {
  match e {
    Name(id~, ..) => Some([id])
    Attribute(value~, attr~, ..) =>
      match dotted_name(value) {
        Some(q) => Some([..q, attr])
        None => None
      }
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Annotations

///|
/// What an annotation says, or `None` when it is not one PurePy has.
pub fn parse_annotation(e : @ast.Expr) -> TypeExpr? {
  match e {
    Constant(value=None, ..) => Some(PrimE(NoneType))
    Name(id~, ..) => {
      for p in primitives {
        if p.name() == id {
          return Some(PrimE(p))
        }
      }
      Some(TypeName([id], []))
    }
    Attribute(..) =>
      match dotted_name(e) {
        Some(q) => Some(TypeName(q, []))
        None => None
      }
    BinOp(op=BitOr, left~, right~, ..) =>
      match (parse_annotation(left), parse_annotation(right)) {
        (Some(a), Some(b)) => Some(UnionE(a, b))
        _ => None
      }
    Subscript(value~, slice~, ..) => parse_subscript(value, slice)
    _ => None
  }
}

///|
fn parse_subscript(value : @ast.Expr, slice : @ast.Expr) -> TypeExpr? {
  let head = match value {
    Name(id~, ..) => Some(id)
    _ => None
  }
  if head == Some("Literal") {
    return match literal_type(slice) {
      Some(v) => Some(LitE(v))
      None => None
    }
  }
  if head == Some("Callable") {
    return parse_callable(subscript_args(slice))
  }
  guard parse_annotations(subscript_args(slice)) is Some(args) else {
    return None
  }
  match head {
    Some("list") => if args.length() == 1 { Some(ListE(args[0])) } else { None }
    Some("tuple") => Some(TupleE(args))
    Some("dict") =>
      if args.length() == 2 && args[0] == PrimE(Str) {
        Some(DictE(args[1]))
      } else {
        None
      }
    _ =>
      match dotted_name(value) {
        Some(q) => Some(TypeName(q, args))
        None => None
      }
  }
}

///|
/// The literal an expression spells: a constant, or a negated number.
pub fn literal_type(e : @ast.Expr) -> Lit? {
  match e {
    Constant(value~, ..) => lit_of_constant(value)
    UnaryOp(op=USub, operand=Constant(value~, ..), ..) =>
      match value {
        Int(n) => Some(Int(-n))
        Float(d) => Some(Float(-d))
        _ => None
      }
    _ => None
  }
}

///|
fn parse_callable(args : Array[@ast.Expr]) -> TypeExpr? {
  guard args.length() == 2 && args[0] is List(elts~, ..) else { return None }
  match (parse_annotations(elts), parse_annotation(args[1])) {
    (Some(ps), Some(r)) => Some(CallableE(ps, r))
    _ => None
  }
}

///|
fn subscript_args(s : @ast.Expr) -> Array[@ast.Expr] {
  match s {
    Tuple(elts~, ..) => elts
    _ => [s]
  }
}

///|
fn parse_annotations(es : Array[@ast.Expr]) -> Array[TypeExpr]? {
  let out = []
  for e in es {
    match parse_annotation(e) {
      Some(t) => out.push(t)
      None => return None
    }
  }
  Some(out)
}

///|
/// The types `taus` put for the parameters `alphas` in `sigma`.
pub fn substitute(
  taus : ArrayView[Type],
  alphas : ArrayView[String],
  sigma : Type,
) -> Type {
  match sigma {
    TypeVar(a) =>
      match alphas.search(a) {
        Some(i) => taus[i]
        None => sigma
      }
    List(s) => List(substitute(taus, alphas, s))
    Tuple(ss) => Tuple(ss.map(fn(c) { substitute(taus, alphas, c) }))
    Dict(s) => Dict(substitute(taus, alphas, s))
    Callable(ps, r) =>
      Callable(
        ps.map(fn(p) { substitute(taus, alphas, p) }),
        substitute(taus, alphas, r),
      )
    Defaulted(ps, n, r) =>
      Defaulted(
        ps.map(fn(p) { substitute(taus, alphas, p) }),
        n,
        substitute(taus, alphas, r),
      )
    Class(c, ss) => Class(c, ss.map(fn(a) { substitute(taus, alphas, a) }))
    Union(s, t) =>
      Union(substitute(taus, alphas, s), substitute(taus, alphas, t))
    _ => sigma
  }
}

///|
/// A class's fields, generic in its type parameters.
pub(all) struct FieldScheme {
  type_params : Array[String]
  fields : Array[(String, Type)]
} derive(Eq, Debug)

///|
/// The fields at the type arguments `taus`.
pub fn instantiate(
  pi : FieldScheme,
  taus : Array[Type],
) -> Array[(String, Type)] {
  pi.fields.map(fn(f) { (f.0, substitute(taus[:], pi.type_params[:], f.1)) })
}
