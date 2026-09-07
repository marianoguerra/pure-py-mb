///|
/// The operators: `⊙̂(v, v')` and `⊖̂(v)`.
///
/// Arithmetic is Python's, with three things this port has to supply that
/// MoonBit does not:
///
///   * **`//` and `%` floor.** MoonBit's `/` and `%` on `BigInt` and `Int64`
///     truncate toward zero; Python's floor toward negative infinity, so the
///     remainder takes the sign of the DIVISOR: `-7 // 2` is `-4` and
///     `7 % -2` is `-1`.
///   * **`bool` is not a number.** `True + 1` and `True < 2` are undefined,
///     even though Python accepts both. That is the same rule that makes
///     `True == 1` undefined, and the conformance suite has a test for it.
///   * **An integer and a float compare exactly**, not by converting the
///     integer, so a large integer is not made equal to the double nearest it.
///
/// The spec leaves arithmetic as "as in Python" with one sentence added:
/// TypeError where an operand is not a number. So `"a" + "b"` aborts here
/// rather than concatenating. Nothing in the conformance suite reaches it,
/// and the decision is written down rather than guessed at each call site.
pub fn binop(op : @ast.Operator, a : Value, b : Value) -> Outcome {
  match (as_number(a), as_number(b)) {
    (Some(x), Some(y)) => arith(op, x, y)
    _ => Aborts(TypeError)
  }
}

///|
/// A number, as one of the two things arithmetic works on. A `bool` is not
/// one, which is the point.
priv enum Num {
  I(BigInt)
  F(Double)
}

///|
fn as_number(v : Value) -> Num? {
  match v {
    Int(n) => Some(I(n))
    Float(d) => Some(F(d))
    _ => None
  }
}

///|
/// A BigInt as a double, correctly rounded -- which is what Python's
/// `float(n)` gives. MoonBit's `BigInt` has no conversion, so it goes through
/// the decimal text, which `parse_double` rounds correctly.
pub fn big_to_double(n : BigInt) -> Double {
  @string.parse_double(n.to_string()) catch {
    // Out of a double's range: Python raises OverflowError, which is not a
    // termination kind, so the caller treats it as undefined.
    _ => if n < 0N { @double.neg_infinity } else { @double.infinity }
  }
}

///|
fn to_double(x : Num) -> Double {
  match x {
    I(n) => big_to_double(n)
    F(d) => d
  }
}

///|
fn arith(op : @ast.Operator, a : Num, b : Num) -> Outcome {
  match (a, b) {
    (I(x), I(y)) => int_arith(op, x, y)
    _ => float_arith(op, to_double(a), to_double(b))
  }
}

///|
fn int_arith(op : @ast.Operator, x : BigInt, y : BigInt) -> Outcome {
  match op {
    Add => Val(Int(x + y))
    Sub => Val(Int(x - y))
    Mult => Val(Int(x * y))
    Div =>
      if y == 0N {
        Aborts(ZeroDivisionError)
      } else {
        Val(Float(big_to_double(x) / big_to_double(y)))
      }
    FloorDiv =>
      if y == 0N {
        Aborts(ZeroDivisionError)
      } else {
        Val(Int(floor_div(x, y)))
      }
    Mod =>
      if y == 0N {
        Aborts(ZeroDivisionError)
      } else {
        Val(Int(floor_mod(x, y)))
      }
    Pow =>
      if y < 0N {
        // A negative exponent gives a float, and `0 ** -1` divides by zero.
        if x == 0N {
          Aborts(ZeroDivisionError)
        } else {
          Val(Float(@math.pow(big_to_double(x), big_to_double(y))))
        }
      } else {
        Val(Int(x.pow(y)))
      }
    _ => Stuck("binary operator '" + op.symbol() + "'")
  }
}

///|
/// Python's `//` on integers: floor, not truncation.
pub fn floor_div(x : BigInt, y : BigInt) -> BigInt {
  let q = x / y
  // MoonBit truncates toward zero. When the signs differ and the division was
  // not exact, the floor is one lower.
  if x % y != 0N && (x < 0N) != (y < 0N) {
    q - 1N
  } else {
    q
  }
}

///|
/// Python's `%` on integers: the remainder takes the sign of the divisor.
pub fn floor_mod(x : BigInt, y : BigInt) -> BigInt {
  let r = x % y
  if r != 0N && (r < 0N) != (y < 0N) {
    r + y
  } else {
    r
  }
}

///|
fn float_arith(op : @ast.Operator, x : Double, y : Double) -> Outcome {
  match op {
    Add => Val(Float(x + y))
    Sub => Val(Float(x - y))
    Mult => Val(Float(x * y))
    Div => if y == 0.0 { Aborts(ZeroDivisionError) } else { Val(Float(x / y)) }
    FloorDiv =>
      if y == 0.0 {
        Aborts(ZeroDivisionError)
      } else {
        Val(Float((x / y).floor()))
      }
    Mod =>
      if y == 0.0 {
        Aborts(ZeroDivisionError)
      } else {
        Val(Float(float_mod(x, y)))
      }
    Pow =>
      // A negative base with a fractional exponent is a complex number in
      // mathematics and a ValueError in Python; neither is a termination
      // kind, so it has no rule here.
      if x < 0.0 && y != y.floor() {
        Stuck("a negative number raised to a fractional power")
      } else {
        Val(Float(@math.pow(x, y)))
      }
    _ => Stuck("binary operator '" + op.symbol() + "'")
  }
}

///|
/// Python's `%` on floats: the result takes the sign of the divisor.
pub fn float_mod(x : Double, y : Double) -> Double {
  let r = x - (x / y).floor() * y
  // The subtraction can land exactly on the divisor through rounding; Python
  // never returns a remainder equal to the divisor.
  if r != 0.0 && (r < 0.0) != (y < 0.0) {
    r + y
  } else {
    r
  }
}

// ---------------------------------------------------------------------------

///|
/// `not`, unary `+` and unary `-`.
pub fn unop(op : @ast.UnaryOp, v : Value) -> Outcome {
  match op {
    Not =>
      match v {
        Bool(b) => Val(Bool(!b))
        // Truthiness is Python's, not PurePy's: `not 1` has no rule.
        _ => Stuck("'not' applied to " + v.kind_name())
      }
    UAdd =>
      match v {
        Int(_) | Float(_) => Val(v)
        _ => Aborts(TypeError)
      }
    USub =>
      match v {
        Int(n) => Val(Int(-n))
        Float(d) => Val(Float(-d))
        _ => Aborts(TypeError)
      }
    Invert => Stuck("unary operator '~'")
  }
}

// ---------------------------------------------------------------------------

///|
/// `==`, `!=`, `in`, `not in` and the four orderings.
pub fn compare(op : @ast.CmpOp, a : Value, b : Value) -> Outcome {
  match op {
    // The `==` operator has a rule where `eq` has none: two nans compare
    // False rather than being undefined.
    Eq =>
      if both_nan(a, b) {
        Val(Bool(false))
      } else {
        match eq(a, b) {
          Some(r) => Val(Bool(r))
          None => Stuck("== between " + a.kind_name() + " and " + b.kind_name())
        }
      }
    NotEq =>
      if both_nan(a, b) {
        Val(Bool(true))
      } else {
        match eq(a, b) {
          Some(r) => Val(Bool(!r))
          None => Stuck("!= between " + a.kind_name() + " and " + b.kind_name())
        }
      }
    In =>
      match contains(b, a) {
        Some(r) => Val(Bool(r))
        None => Stuck("'in' over " + b.kind_name())
      }
    NotIn =>
      match contains(b, a) {
        Some(r) => Val(Bool(!r))
        None => Stuck("'not in' over " + b.kind_name())
      }
    Lt | LtE | Gt | GtE =>
      match order(a, b) {
        Some(c) =>
          Val(
            Bool(
              match op {
                Lt => c < 0
                LtE => c <= 0
                Gt => c > 0
                _ => c >= 0
              },
            ),
          )
        None =>
          Stuck(
            "'" +
            op.symbol() +
            "' between " +
            a.kind_name() +
            " and " +
            b.kind_name(),
          )
      }
    // The sieve rejects `is` and `is not` as not yet supported (#81).
    Is | IsNot => Stuck("identity operator '" + op.symbol() + "'")
  }
}

///|
fn both_nan(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Float(x), Float(y)) => x.is_nan() && y.is_nan()
    _ => false
  }
}

///|
/// Three-way comparison, `None` where the two values have no order.
///
/// Numbers with numbers, strings by code point, lists with lists and tuples
/// with tuples lexicographically. A `nan` anywhere makes the pair unordered,
/// which is how Python's comparisons all come out False.
pub fn order(a : Value, b : Value) -> Int? {
  match (a, b) {
    (Int(x), Int(y)) => Some(x.compare(y))
    (Float(x), Float(y)) =>
      if x.is_nan() || y.is_nan() {
        None
      } else if x < y {
        Some(-1)
      } else if x > y {
        Some(1)
      } else {
        Some(0)
      }
    (Int(x), Float(y)) => int_float_order(x, y)
    (Float(x), Int(y)) =>
      match int_float_order(y, x) {
        Some(c) => Some(-c)
        None => None
      }
    (Str(x), Str(y)) => Some(@basic.lexical_compare(x, y))
    (List(xs), List(ys)) | (Tuple(xs), Tuple(ys)) => order_elems(xs, ys)
    _ => None
  }
}

///|
/// An integer against a float, exactly.
fn int_float_order(n : BigInt, d : Double) -> Int? {
  if d.is_nan() {
    return None
  }
  if d.is_pos_inf() {
    return Some(-1)
  }
  if d.is_neg_inf() {
    return Some(1)
  }
  let f = d.floor()
  match exact_integer(f) {
    None => None
    Some(m) => {
      let c = n.compare(m)
      if c != 0 {
        Some(c)
      } else if d > f {
        // The integer equals the floor, and the float has a fraction above it.
        Some(-1)
      } else {
        Some(0)
      }
    }
  }
}

///|
/// Lexicographic order over two sequences, as Python compares them: the first
/// unequal pair decides, and otherwise the shorter is smaller.
fn order_elems(xs : Array[Value], ys : Array[Value]) -> Int? {
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i in 0..<n {
    match eq(xs[i], ys[i]) {
      None => return None
      Some(true) => ()
      Some(false) =>
        return match order(xs[i], ys[i]) {
          Some(c) => Some(c)
          None => None
        }
    }
  }
  if xs.length() == ys.length() {
    Some(0)
  } else if xs.length() < ys.length() {
    Some(-1)
  } else {
    Some(1)
  }
}
