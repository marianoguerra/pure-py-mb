///|
/// Identifier characters.
///
/// Python's rule is `XID_Start` and `XID_Continue`. This port approximates it:
/// ASCII letters and `_` start an identifier, and so does any printable
/// non-ASCII code point that is neither whitespace nor a digit. The full XID
/// tables are ~130 KB of data for a language whose entire conformance suite is
/// ASCII, and the approximation errs only on non-ASCII punctuation and
/// symbols, which a Python source cannot contain outside a string anyway.
/// Recorded as decision 7 of the plan.
pub fn is_ident_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c == '_' ||
  (
    c.to_int() >= 0x80 &&
    c.is_printable() &&
    !c.is_whitespace() &&
    !c.is_numeric()
  )
}

///|
pub fn is_ident_continue(c : Char) -> Bool {
  is_ident_start(c) ||
  c.is_ascii_digit() ||
  (c.to_int() >= 0x80 && c.is_numeric())
}

///|
/// A name, unless the letters are a string prefix and a quote follows -- which
/// `at_string_start` has already decided, so by here it is a name.
fn Lexer::scan_name(self : Lexer) -> Unit {
  let start = self.pos()
  let from = self.i
  while !self.at_end() && is_ident_continue(self.peek(0)) {
    self.i += 1
  }
  self.emit(Name, start, self.pos(), self.text(from, self.i))
  self.pending_newline = true
}

// ---------------------------------------------------------------------------
// Operators and delimiters

///|
/// Every operator and delimiter Python 3.12 has, longest first, because the
/// scanner takes the first that matches.
let operators : Array[String] = [
  "**=", "//=", ">>=", "<<=", "...", "!=", "**", "//", ">>", "<<", "<=", ">=", "==",
  "->", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "@=", ":=", "+", "-", "*",
  "/", "%", "@", "&", "|", "^", "~", "<", ">", "(", ")", "[", "]", "{", "}", ",",
  ":", ".", ";", "=",
]

///|
fn Lexer::scan_operator(self : Lexer) -> Unit raise {
  let start = self.pos()
  for op in operators {
    if self.matches(op) {
      self.i += op.char_length()
      match op {
        "(" | "[" | "{" => self.depth += 1
        ")" | "]" | "}" => if self.depth > 0 { self.depth -= 1 }
        _ => ()
      }
      self.emit(Op(op), start, self.pos(), op)
      self.pending_newline = true
      return
    }
  }
  let c = self.peek(0)
  // `<>` was removed in Python 3; CPython reports the same thing for it as for
  // any other character it has no rule for.
  raise fail("invalid character '\{c}' (U+\{hex4(c.to_int())})", start)
}

///|
fn Lexer::matches(self : Lexer, s : String) -> Bool {
  let cs = s.to_array()
  for k, c in cs {
    if self.peek(k) != c {
      return false
    }
  }
  true
}

///|
/// Four uppercase hexadecimal digits, as CPython spells a code point.
fn hex4(n : Int) -> String {
  let digits = "0123456789ABCDEF".to_array()
  let out = StringBuilder()
  let mut started = false
  for shift in [28, 24, 20, 16, 12, 8, 4, 0] {
    let d = (n >> shift) & 0xF
    if d != 0 || started || shift < 16 {
      out.write_char(digits[d])
      started = true
    }
  }
  out.to_string()
}

// ---------------------------------------------------------------------------
// Numbers

///|
/// A numeric literal, kept as its lexeme. The value is computed on demand, so
/// that a token can be reported before it is interpreted.
///
/// CPython's tokenizer rejects a malformed literal here ("invalid decimal
/// literal" for `1__0` and `0_`) but accepts `09`, which the PARSER then
/// rejects for its leading zero. Both are reproduced where they belong.
fn Lexer::scan_number(self : Lexer) -> Unit raise {
  let start = self.pos()
  let from = self.i
  if self.peek(0) == '0' && self.peek(1) is ('x' | 'X' | 'o' | 'O' | 'b' | 'B') {
    let (name, ok) = match self.peek(1) {
      'x' | 'X' => ("hexadecimal", fn(c : Char) { c.is_ascii_hexdigit() })
      'o' | 'O' => ("octal", fn(c : Char) { c >= '0' && c <= '7' })
      _ => ("binary", fn(c : Char) { c == '0' || c == '1' })
    }
    self.i += 2
    self.scan_digits(ok, "invalid \{name} literal", leading_underscore=true)
  } else {
    let decimal = fn(c : Char) { c.is_ascii_digit() }
    if self.peek(0) != '.' {
      self.scan_digits(decimal, "invalid decimal literal")
    }
    if self.peek(0) == '.' {
      self.i += 1
      if self.peek(0).is_ascii_digit() || self.peek(0) == '_' {
        self.scan_digits(decimal, "invalid decimal literal")
      }
    }
    if self.peek(0) is ('e' | 'E') {
      let after = if self.peek(1) is ('+' | '-') { 2 } else { 1 }
      // `1e` is a name after a number, not an exponent; only commit when a
      // digit follows, as CPython does.
      if self.peek(after).is_ascii_digit() {
        self.i += after
        self.scan_digits(decimal, "invalid decimal literal")
      }
    }
  }
  if self.peek(0) is ('j' | 'J') {
    self.i += 1
  }
  // A literal may not run straight into an identifier: `0x1for` is an error in
  // CPython, and so is `1_`, which the digit scanner has already refused.
  if !self.at_end() && is_ident_start(self.peek(0)) {
    raise fail("invalid decimal literal", self.pos())
  }
  self.emit(Number, start, self.pos(), self.text(from, self.i))
  self.pending_newline = true
}

///|
/// A run of digits with single underscores between them. An underscore that
/// does not sit between two digits is CPython's "invalid ... literal", raised
/// at the start of the literal as CPython raises it.
fn Lexer::scan_digits(
  self : Lexer,
  ok : (Char) -> Bool,
  msg : String,
  leading_underscore? : Bool = false,
) -> Unit raise {
  let mut seen = false
  while !self.at_end() {
    let c = self.peek(0)
    if ok(c) {
      seen = true
      self.i += 1
    } else if c == '_' && ok(self.peek(1)) && (seen || leading_underscore) {
      // An underscore has to sit between two digits -- except after a base
      // prefix, where Python allows `0x_ff`. A doubled or trailing underscore
      // falls out of the loop here and is caught as an identifier running into
      // the literal, which is what CPython reports.
      self.i += 1
    } else {
      break
    }
  }
  if !seen {
    raise fail(msg, self.pos_at(self.i + 1))
  }
}

// ---------------------------------------------------------------------------
// Strings

///|
/// The prefixes a string literal may carry, in every case and order Python
/// allows. `u` is the one that cannot combine.
fn string_prefix(s : String) -> Bool {
  match s.to_lower() {
    "" | "r" | "u" | "b" | "f" | "rb" | "br" | "rf" | "fr" => true
    _ => false
  }
}

///|
/// Whether a string literal starts here: a quote, or up to two prefix letters
/// and then a quote.
fn Lexer::at_string_start(self : Lexer) -> Bool {
  let c = self.peek(0)
  if c == '\'' || c == '"' {
    return true
  }
  if !is_ident_start(c) {
    return false
  }
  for n in [1, 2] {
    let q = self.peek(n)
    if q == '\'' || q == '"' {
      return string_prefix(self.text(self.i, self.i + n))
    }
  }
  false
}

///|
/// A string literal, whole. The prefix decides which of the three kinds it is;
/// the sieve rejects two of them by name, so they are distinguished here
/// rather than re-derived from the text later.
fn Lexer::scan_string(self : Lexer) -> Unit raise {
  let start = self.pos()
  let from = self.i
  while self.peek(0) != '\'' && self.peek(0) != '"' {
    self.i += 1
  }
  let prefix = self.text(from, self.i).to_lower()
  let quote = self.peek(0)
  let triple = self.peek(1) == quote && self.peek(2) == quote
  let is_f = prefix.contains("f")
  self.i += if triple { 3 } else { 1 }
  self.scan_string_body(quote, triple, is_f, start)
  let kind : TokenKind = if is_f {
    FString(prefix~)
  } else if prefix.contains("b") {
    Bytes(prefix~)
  } else {
    Str(prefix~)
  }
  let text = self.text(from, self.i)
  if kind is Bytes(..) {
    for c in text {
      if c.to_int() > 0x7F {
        raise fail("bytes can only contain ASCII literal characters", start)
      }
    }
  }
  self.emit(kind, start, self.pos(), text)
  self.pending_newline = true
}

///|
/// Scan to the closing quote.
///
/// A backslash defers the next character whether or not the literal is raw:
/// `r"\""` is one string containing a backslash and a quote, so raw affects
/// what the value MEANS and not where the literal ends.
///
/// In an f-string a `{` that is not `{{` opens an expression, and since 3.12
/// that expression may contain anything, the same quote included. Brace depth
/// is tracked so that `f"{d["k"]}"` ends where Python says it ends.
fn Lexer::scan_string_body(
  self : Lexer,
  quote : Char,
  triple : Bool,
  is_f : Bool,
  start : Pos,
) -> Unit raise {
  let mut braces = 0
  while true {
    if self.at_end() {
      raise fail(
        if triple {
          "unterminated triple-quoted string literal"
        } else {
          "unterminated string literal"
        },
        start,
      )
    }
    let c = self.peek(0)
    if c == '\\' {
      self.i += 1
      if !self.at_end() {
        self.bump()
      }
      continue
    }
    if c == '\n' && !triple && braces == 0 {
      raise fail("unterminated string literal", start)
    }
    if is_f && c == '{' {
      if self.peek(1) == '{' && braces == 0 {
        self.i += 2
        continue
      }
      braces += 1
      self.i += 1
      continue
    }
    if is_f && c == '}' && braces > 0 {
      braces -= 1
      self.i += 1
      continue
    }
    if c == quote && braces == 0 {
      if triple {
        if self.peek(1) == quote && self.peek(2) == quote {
          self.i += 3
          return
        }
      } else {
        self.i += 1
        return
      }
    }
    self.bump()
  }
}
