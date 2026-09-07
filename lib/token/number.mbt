///|
/// The value of a numeric literal.
///
/// A token keeps its lexeme and nothing else, so that it can be reported
/// before it is interpreted; this is where the lexeme becomes a number. Python
/// has three kinds and PurePy's sieve rejects the third, so the third is still
/// recognised here -- "complex literals prohibited" needs to know one when it
/// sees one.
pub(all) enum NumberValue {
  Int(BigInt)
  Float(Double)
  Imaginary(Double)
} derive(Eq, Debug)

///|
/// Interpret a NUMBER token.
///
/// The one rejection that belongs here rather than in the tokenizer is the
/// leading zero: CPython tokenizes `09` happily and its PARSER refuses it,
/// with the message reproduced below.
pub fn Token::number_value(self : Token) -> NumberValue raise {
  let text = self.text
  let imaginary = text.has_suffix("j") || text.has_suffix("J")
  let body = if imaginary { text[:text.length() - 1].to_owned() } else { text }
  let digits = strip_underscores(body)
  if imaginary {
    return Imaginary(to_double(digits, self))
  }
  if digits.length() > 1 && (digits.has_prefix("0x") || digits.has_prefix("0X")) {
    return Int(BigInt::from_string(digits[2:].to_owned(), radix=16))
  }
  if digits.has_prefix("0o") || digits.has_prefix("0O") {
    return Int(BigInt::from_string(digits[2:].to_owned(), radix=8))
  }
  if digits.has_prefix("0b") || digits.has_prefix("0B") {
    return Int(BigInt::from_string(digits[2:].to_owned(), radix=2))
  }
  if digits.contains(".") || digits.contains("e") || digits.contains("E") {
    return Float(to_double(digits, self))
  }
  if digits.length() > 1 && digits.has_prefix("0") && !all_zeros(digits) {
    raise @err.syntax_error(
      "leading zeros in decimal integer literals are not permitted; use an 0o prefix for octal integers",
      self.span,
    )
  }
  Int(BigInt::from_string(digits))
}

///|
/// The integer a NUMBER token stands for, for a caller that has already
/// established it is one.
pub fn Token::int_value(self : Token) -> BigInt raise {
  match self.number_value() {
    Int(n) => n
    Float(_) | Imaginary(_) =>
      raise @err.syntax_error("not an integer literal", self.span)
  }
}

///|
/// Underscores are grouping and mean nothing to the value.
fn strip_underscores(s : String) -> String {
  if !s.contains("_") {
    return s
  }
  let out = StringBuilder()
  for c in s {
    if c != '_' {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn all_zeros(s : String) -> Bool {
  for c in s {
    if c != '0' {
      return false
    }
  }
  true
}

///|
/// Python writes `1.`, `.5` and `1.e5`; MoonBit's `parse_double` wants a digit
/// on both sides of the point, so one is supplied.
fn to_double(s : String, tok : Token) -> Double raise {
  let padded = pad_point(s)
  @string.parse_double(padded) catch {
    _ =>
      // A literal too large for a double is an infinity in Python, not an
      // error: `1e400` is `inf`, and the suite has one. Anything else really
      // is malformed.
      if overflows(padded) {
        @double.infinity
      } else {
        raise @err.syntax_error("invalid numeric literal", tok.span)
      }
  }
}

///|
/// Whether a literal `parse_double` refused is one whose magnitude is simply
/// too large: digits and a point, with an exponent that is not negative.
fn overflows(s : String) -> Bool {
  let mut seen_e = false
  for c in s {
    if c == 'e' || c == 'E' {
      seen_e = true
    } else if c == '-' && seen_e {
      return false
    } else if !(c.is_ascii_digit() || c == '.' || c == '+') {
      return false
    }
  }
  true
}

///|
fn pad_point(s : String) -> String {
  let out = StringBuilder()
  let cs = s.to_array()
  for i, c in cs {
    if c == '.' {
      if i == 0 {
        out.write_char('0')
      }
      out.write_char('.')
      if i + 1 >= cs.length() || !cs[i + 1].is_ascii_digit() {
        out.write_char('0')
      }
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}
