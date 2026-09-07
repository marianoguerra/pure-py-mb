///|
/// Python's `repr` of a float.
///
/// MoonBit's `Double::to_string` already produces the shortest digits that
/// round-trip, and agrees with CPython on the digits for every value tested.
/// What it does not agree on is the LAYOUT, in six ways: `1` for `1.0`,
/// `10000000000000000` for `1e16`, `0` for `-0.0`, `Infinity`, `NaN`, and
/// `2.5e-7` where Python writes `2.5e-07`. So the digits are taken from
/// MoonBit and laid out again here, by CPython's rules
/// (`Python/pystrtod.c`, `format_float_short` with mode `r`):
///
///   * `nan`, `inf`, `-inf`, and `-0.0` with its sign from the bit pattern.
///   * With the value written as `0.D × 10^decpt`: exponent notation when
///     `decpt <= -4 || decpt > 16`, and positional otherwise. That is why
///     `1e15` prints in full and `1e16` does not.
///   * Positional always carries a point and at least one digit after it.
///   * The exponent always carries a sign and at least two digits.
///
/// The same layout is what `str()` produces: Python 3 has one float format.
pub fn py_float_repr(d : Double) -> String {
  if d != d {
    return "nan"
  }
  if d == @double.infinity {
    return "inf"
  }
  if d == @double.neg_infinity {
    return "-inf"
  }
  let text = d.to_string()
  let signed_text = text.has_prefix("-")
  // The sign of a zero is in the bit pattern, not in the digits: MoonBit
  // renders negative zero as `0`, and Python writes `-0.0`.
  let negative = signed_text || (d == 0.0 && d.reinterpret_as_uint64() != 0UL)
  let body = if signed_text { text[1:].to_owned() } else { text }
  let (digits, exp10) = decompose(body)
  let out = StringBuilder()
  if negative {
    out.write_char('-')
  }
  if digits == "0" {
    out.write_string("0.0")
    return out.to_string()
  }
  // `exp10` is the power of ten the first digit stands for; CPython's `decpt`
  // is one more than that.
  let decpt = exp10 + 1
  if decpt <= -4 || decpt > 16 {
    write_exponential(out, digits, exp10)
  } else {
    write_positional(out, digits, exp10)
  }
  out.to_string()
}

///|
/// The significant digits, and the power of ten the first one stands for.
///
/// `body` is MoonBit's rendering of a non-negative finite double, in any of
/// the forms it produces: `3.14`, `0.000001`, `100000000000000000000`,
/// `1e+100`.
fn decompose(body : String) -> (String, Int) {
  let mut mant = body
  let mut exp = 0
  match find_char(body, 'e') {
    Some(i) => {
      mant = body[:i].to_owned()
      exp = parse_signed_int(body[i + 1:].to_owned())
    }
    None => ()
  }
  let point = match find_char(mant, '.') {
    Some(i) => i
    None => mant.length()
  }
  let all = StringBuilder()
  for c in mant {
    if c != '.' {
      all.write_char(c)
    }
  }
  let mut digits = all.to_string()
  let mut before = point
  // Leading zeros are not significant, and each one moves the point.
  let mut lead = 0
  while lead < digits.length() - 1 && digits.get_char(lead) is Some('0') {
    lead = lead + 1
    before = before - 1
  }
  digits = digits[lead:].to_owned()
  // Trailing zeros are not significant either.
  let mut last = digits.length()
  while last > 1 && digits.get_char(last - 1) is Some('0') {
    last = last - 1
  }
  digits = digits[:last].to_owned()
  if digits == "0" {
    return ("0", 0)
  }
  (digits, before - 1 + exp)
}

///|
fn find_char(s : String, c : Char) -> Int? {
  for i in 0..<s.length() {
    if s.get_char(i) is Some(x) && x == c {
      return Some(i)
    }
  }
  None
}

///|
fn parse_signed_int(s : String) -> Int {
  let mut i = 0
  let mut neg = false
  if s.get_char(0) is Some('-') {
    neg = true
    i = 1
  } else if s.get_char(0) is Some('+') {
    i = 1
  }
  let mut v = 0
  while i < s.length() {
    match s.get_char(i) {
      Some(c) if c >= '0' && c <= '9' => v = v * 10 + (c.to_int() - 48)
      _ => break
    }
    i = i + 1
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// `1.0`, `10.0`, `0.0001` -- always with a point and a digit after it.
fn write_positional(out : StringBuilder, digits : String, exp10 : Int) -> Unit {
  if exp10 >= 0 {
    let int_len = exp10 + 1
    for i in 0..<int_len {
      if i < digits.length() {
        out.write_char(digits.get_char(i).unwrap())
      } else {
        out.write_char('0')
      }
    }
    out.write_char('.')
    if digits.length() > int_len {
      out.write_string(digits[int_len:].to_owned())
    } else {
      out.write_char('0')
    }
  } else {
    out.write_string("0.")
    for _ in 0..<(-exp10 - 1) {
      out.write_char('0')
    }
    out.write_string(digits)
  }
}

///|
/// `1e+16`, `2.5e-07` -- a point only when there is more than one digit, a
/// sign always, and at least two exponent digits.
fn write_exponential(out : StringBuilder, digits : String, exp10 : Int) -> Unit {
  out.write_char(digits.get_char(0).unwrap())
  if digits.length() > 1 {
    out.write_char('.')
    out.write_string(digits[1:].to_owned())
  }
  out.write_char('e')
  if exp10 >= 0 {
    out.write_char('+')
  } else {
    out.write_char('-')
  }
  let mag = if exp10 < 0 { -exp10 } else { exp10 }
  let text = mag.to_string()
  if text.length() < 2 {
    out.write_char('0')
  }
  out.write_string(text)
}
