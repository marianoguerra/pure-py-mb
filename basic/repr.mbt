///|
/// Python's `repr` of a string.
///
/// It lives here, below everything, because three consumers need the same
/// escaping: the token dump, the AST dump and the runtime's `repr` of a value.
/// One implementation, one set of rules:
///
///   * The quote is `'`, unless the string contains a `'` and no `"`.
///   * `\\`, `\n`, `\r`, `\t` and the chosen quote are escaped by name; the
///     OTHER quote never is.
///   * A code point Python calls unprintable becomes `\xNN`, `\uNNNN` or
///     `\UNNNNNNNN`, by size.
///
/// Printability is exact below U+0100 -- the control ranges, U+007F, the C1
/// block, U+00A0 and U+00AD -- and everything above is treated as printable.
/// That is decision 8 of the plan: the exact answer is the Unicode general
/// category tables, the conformance suite is ASCII, and the difference shows
/// only on a format character or an unassigned code point in a string that a
/// program prints back out.
pub fn py_repr(s : String) -> String {
  let has_single = s.contains_char('\'')
  let has_double = s.contains_char('"')
  let quote = if has_single && !has_double { '"' } else { '\'' }
  let out = StringBuilder()
  out.write_char(quote)
  for c in s {
    match c {
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if c == quote {
          out.write_char('\\')
          out.write_char(c)
        } else if is_printable(c) {
          out.write_char(c)
        } else {
          out.write_string(escape_code_point(c.to_int()))
        }
    }
  }
  out.write_char(quote)
  out.to_string()
}

///|
/// Python's `str.isprintable`, exactly below U+0100 and optimistically above.
pub fn is_printable(c : Char) -> Bool {
  let n = c.to_int()
  if n < 0x20 {
    false
  } else if n < 0x7F {
    true
  } else if n <= 0xA0 {
    // U+007F and the C1 controls, and U+00A0 (a separator, which `isprintable`
    // excludes even though it is not a control).
    false
  } else if n == 0xAD {
    false
  } else {
    true
  }
}

///|
/// `\xNN`, `\uNNNN` or `\UNNNNNNNN`, by size, lowercase as Python writes them.
pub fn escape_code_point(n : Int) -> String {
  if n < 0x100 {
    "\\x" + hex_digits(n, 2)
  } else if n < 0x10000 {
    "\\u" + hex_digits(n, 4)
  } else {
    "\\U" + hex_digits(n, 8)
  }
}

///|
/// `n` in lowercase hexadecimal, zero-padded to `width`.
pub fn hex_digits(n : Int, width : Int) -> String {
  let digits = "0123456789abcdef".to_array()
  let out = StringBuilder()
  for k = width - 1; k >= 0; k = k - 1 {
    out.write_char(digits[(n >> (k * 4)) & 0xF])
  }
  out.to_string()
}
