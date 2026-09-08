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
///   * **`bool` is not a number.** `True + 1`, `True < 2` and `-False` are
///     UNDEFINED, even though Python accepts all three. Undefined and not
///     `TypeError`: a termination kind is "named after the exception the same
///     program raises under Python in the same circumstances"
///     (`operational-semantics.tex`), and Python raises nothing for `True + 1`
///     -- it says 2. This is the same rule that makes `True == 1` undefined,
///     and the conformance suite has a test for that.
///   * **An integer and a float compare exactly**, not by converting the
///     integer, so a large integer is not made equal to the double nearest it.
///
/// `+` and `*` are tried over sequences first, because they are not
/// arithmetic there. The spec's arithmetic table is a `\todo` reading
/// "Arithmetic, as in Python ... aborts TypeError where an operand is not a
/// number", and the two halves disagree about `"a" + "b"`: the sentence was
/// written for `1 + "a"`, which the conformance suite tests and which IS a
/// TypeError in Python. Concatenation is not, and CPython is the oracle for
/// what `run` prints, so "as in Python" is the half that decides.
pub fn binop(op : @ast.Operator, a : Value, b : Value) -> Outcome {
  match seq_binop(op, a, b) {
    Some(o) => o
    Option::None =>
      match (as_number(a), as_number(b)) {
        (Some(x), Some(y)) => arith(op, x, y)
        // A bool reaching an operator is the one case where Python has an
        // answer and this does not, so it is undefined rather than an abort.
        _ if bool_has_answer(op, a, b) => Stuck(no_rule_for_bool(op.symbol()))
        // Everything left -- `1 + "a"`, `"a" - "b"`, `None + None`, and
        // `True + None` with it -- is a TypeError under Python too.
        _ => Aborts(TypeError)
      }
  }
}

///|
fn is_bool(v : Value) -> Bool {
  v is Bool(_)
}

///|
/// Whether Python answers this because it reads a bool as an int.
///
/// Asked by substituting: put an integer where each bool is and see whether
/// the operands become a pair this file HAS a rule for. That is exactly what
/// Python does -- `bool` is a subclass of `int` there -- so the substitution
/// answers the question without a second table to keep in step. `True + 1`
/// becomes `1 + 1` and is undefined; `True + None` becomes `1 + None`, which
/// has no rule here for the same reason Python raises TypeError, and so it
/// keeps aborting.
fn bool_has_answer(op : @ast.Operator, a : Value, b : Value) -> Bool {
  if !(is_bool(a) || is_bool(b)) {
    return false
  }
  let one : Value = Int(1N)
  let a = if is_bool(a) { one } else { a }
  let b = if is_bool(b) { one } else { b }
  if seq_binop(op, a, b) is Some(_) {
    return true
  }
  as_number(a) is Some(_) && as_number(b) is Some(_)
}

///|
fn no_rule_for_bool(symbol : String) -> String {
  "'" + symbol + "' on a bool: PurePy does not make a bool a number"
}

///|
/// `+` and `*` over sequences: concatenation and repetition. `None` where the
/// pair is not one of them, which sends the operands back to arithmetic and,
/// failing that, to `TypeError` -- so `1 + "a"`, `"a" - "b"` and `[1] + (2,)`
/// all keep the answer Python gives them.
///
/// The two operands of `+` must be the same kind: a list and a tuple do not
/// concatenate in Python either. For `*` a `bool` is not a count, for the
/// same reason it is not a number; `True * 2` stays undefined.
fn seq_binop(op : @ast.Operator, a : Value, b : Value) -> Outcome? {
  match op {
    Add =>
      match (a, b) {
        (Str(x), Str(y)) => Some(Val(Str(x + y)))
        (List(x), List(y)) => Some(Val(List(concat(x, y))))
        (Tuple(x), Tuple(y)) => Some(Val(Tuple(concat(x, y))))
        _ => Option::None
      }
    // `%` on a string is printf-style formatting in Python, not arithmetic
    // and not an error: `"%d" % 3` is `"3"`. PurePy models no formatting, so
    // the semantics has no rule -- and saying so is the honest answer, where
    // `Aborts(TypeError)` would be a claim about CPython that is false.
    Mod =>
      match a {
        Str(_) =>
          Some(Stuck("'%' on a string: PurePy has no string formatting"))
        _ => Option::None
      }
    Mult =>
      match (a, b) {
        (Str(s), Int(n)) | (Int(n), Str(s)) =>
          Some(
            match repeat_count(n) {
              Some(k) => {
                let out = StringBuilder()
                for _ in 0..<k {
                  out.write_string(s)
                }
                Val(Str(out.to_string()))
              }
              Option::None => too_long
            },
          )
        (List(xs), Int(n)) | (Int(n), List(xs)) =>
          Some(
            match repeat_count(n) {
              Some(k) => Val(List(repeat(xs, k)))
              Option::None => too_long
            },
          )
        (Tuple(xs), Int(n)) | (Int(n), Tuple(xs)) =>
          Some(
            match repeat_count(n) {
              Some(k) => Val(Tuple(repeat(xs, k)))
              Option::None => too_long
            },
          )
        _ => Option::None
      }
    _ => Option::None
  }
}

///|
/// Python raises `OverflowError` where a repetition count does not fit an
/// index, and that is not a termination kind, so it has no rule here.
let too_long : Outcome = Stuck("a repetition count too large to build")

///|
/// A repetition count as a length: Python treats every non-positive count as
/// zero, and `None` where the count is too large to be one.
fn repeat_count(n : BigInt) -> Int? {
  if n <= 0N {
    Some(0)
  } else if n > BigInt::from_int(@int.MAX_VALUE) {
    Option::None
  } else {
    Some(n.to_int())
  }
}

///|
fn concat(x : Array[Value], y : Array[Value]) -> Array[Value] {
  let out : Array[Value] = []
  for v in x {
    out.push(v)
  }
  for v in y {
    out.push(v)
  }
  out
}

///|
fn repeat(xs : Array[Value], k : Int) -> Array[Value] {
  let out : Array[Value] = []
  for _ in 0..<k {
    for v in xs {
      out.push(v)
    }
  }
  out
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
  let r = if r != 0.0 && (r < 0.0) != (y < 0.0) { r + y } else { r }
  // A ZERO remainder takes the sign of the divisor too, which the correction
  // above cannot do because it is guarded on a non-zero: `4.0 % -2.0` is
  // -0.0 in Python, and `repr` tells the two zeroes apart.
  if r == 0.0 {
    if y < 0.0 {
      -0.0
    } else {
      0.0
    }
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
    // `-False` is 0 in Python, so a bool here is undefined for the reason
    // `True + 1` is: there is no exception to name.
    UAdd =>
      match v {
        Int(_) | Float(_) => Val(v)
        Bool(_) => Stuck(no_rule_for_bool("+"))
        _ => Aborts(TypeError)
      }
    USub =>
      match v {
        Int(n) => Val(Int(-n))
        Float(d) => Val(Float(-d))
        Bool(_) => Stuck(no_rule_for_bool("-"))
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
    // Every ordering against a nan is False in Python -- `nan < 1.0` and
    // `nan >= nan` alike -- which the `==` and `!=` rules above say in their
    // own way. `order` cannot: it answers with a three-way comparison, and a
    // nan has no place in one. So the case is taken before it is asked.
    Lt | LtE | Gt | GtE if numeric_nan(a, b) => Val(Bool(false))
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
    // `is` asks whether two expressions denote the SAME object, and a PurePy
    // value has no identity to ask about: nothing is mutable, so no program
    // can tell two equal values apart, and there is no rule that could answer
    // `[1] is [1]` without inventing one.
    //
    // `None` is the exception, and it is the reason `is` is worth having at
    // all. Python's `None` is a singleton, `x is None` is how Python spells
    // the question, and here it is total: a value either is `None` or is not.
    // Everything else stays undefined rather than guessing -- `True is True`
    // and `1 is 1` are True in CPython only because it interns them, which is
    // an implementation's answer and not a language's.
    Is | IsNot => {
      let identical = match (a, b) {
        (None, None) => Some(true)
        (None, _) | (_, None) => Some(false)
        _ => Option::None
      }
      match identical {
        Some(r) => Val(Bool(if op is Is { r } else { !r }))
        None =>
          Stuck(
            "'" +
            op.symbol() +
            "' between " +
            a.kind_name() +
            " and " +
            b.kind_name() +
            ": PurePy values have no identity apart from None",
          )
      }
    }
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
/// Two numbers, at least one of them a nan. `nan < "a"` is NOT one: Python
/// raises TypeError there, and an unordered pair of kinds stays undefined
/// whatever the numbers in it are doing.
fn numeric_nan(a : Value, b : Value) -> Bool {
  fn is_num(v : Value) -> Bool {
    v is (Int(_) | Float(_))
  }

  fn is_nan(v : Value) -> Bool {
    match v {
      Float(d) => d.is_nan()
      _ => false
    }
  }

  is_num(a) && is_num(b) && (is_nan(a) || is_nan(b))
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
