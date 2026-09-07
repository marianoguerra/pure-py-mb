///|
/// The value of a string or bytes literal: the characters it stands for, with
/// the escapes decoded.
///
/// Raw literals keep every backslash. A non-raw literal decodes Python's
/// escapes, and an escape Python does not know keeps its backslash -- Python
/// 3.12 warns about that and does not fail, so neither does this.
///
/// `\N{NAME}` needs the Unicode name table, which this port does not carry.
/// The three names the corpus uses are recognised; any other raises, and the
/// gap is written down rather than silently wrong.
pub fn Token::str_value(self : Token) -> String raise {
  let (prefix, raw) = match self.kind {
    Str(prefix~) => (prefix, prefix.contains("r"))
    Bytes(prefix~) => (prefix, prefix.contains("r"))
    FString(prefix~) => (prefix, prefix.contains("r"))
    _ => raise @err.syntax_error("not a string literal", self.span)
  }
  let body = strip_quotes(self.text, prefix.length(), self)
  if raw {
    return body
  }
  decode_escapes(body, self)
}

///|
/// The text between the quotes: drop the prefix, then one or three quotes at
/// each end.
fn strip_quotes(text : String, prefix_len : Int, tok : Token) -> String raise {
  let cs = text.to_array()
  if cs.length() < prefix_len + 2 {
    raise @err.syntax_error("malformed string literal", tok.span)
  }
  let q = cs[prefix_len]
  let triple = cs.length() >= prefix_len + 6 &&
    cs[prefix_len + 1] == q &&
    cs[prefix_len + 2] == q
  let n = if triple { 3 } else { 1 }
  String::from_array(cs[prefix_len + n:cs.length() - n])
}

///|
/// Python's escape sequences.
///
/// `\newline` disappears; `\0` through `\777` are octal; `\xHH` is exactly two
/// hexadecimal digits and fewer is an error; `\uHHHH` and `\UHHHHHHHH` are
/// exactly four and eight. An unknown escape keeps its backslash.
fn decode_escapes(s : String, tok : Token) -> String raise {
  if !s.contains("\\") {
    return s
  }
  let cs = s.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    if c != '\\' || i + 1 >= cs.length() {
      out.write_char(c)
      i += 1
      continue
    }
    let e = cs[i + 1]
    i += 2
    match e {
      '\n' => ()
      '\\' => out.write_char('\\')
      '\'' => out.write_char('\'')
      '"' => out.write_char('"')
      'a' => out.write_char('\u{07}')
      'b' => out.write_char('\u{08}')
      'f' => out.write_char('\u{0C}')
      'n' => out.write_char('\n')
      'r' => out.write_char('\r')
      't' => out.write_char('\t')
      'v' => out.write_char('\u{0B}')
      '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' => {
        let mut n = e.to_int() - '0'.to_int()
        let mut k = 1
        while k < 3 && i < cs.length() && cs[i] >= '0' && cs[i] <= '7' {
          n = n * 8 + (cs[i].to_int() - '0'.to_int())
          i += 1
          k += 1
        }
        out.write_char(n.unsafe_to_char())
      }
      'x' => {
        let (n, next) = hex_escape(cs, i, 2, tok, "\\x")
        out.write_char(n.unsafe_to_char())
        i = next
      }
      'u' => {
        let (n, next) = hex_escape(cs, i, 4, tok, "\\u")
        out.write_char(n.unsafe_to_char())
        i = next
      }
      'U' => {
        let (n, next) = hex_escape(cs, i, 8, tok, "\\U")
        out.write_char(n.unsafe_to_char())
        i = next
      }
      'N' => {
        let (name, next) = named_escape(cs, i, tok)
        out.write_string(unicode_named(name, tok))
        i = next
      }
      // Not an escape Python knows: the backslash stays.
      _ => {
        out.write_char('\\')
        out.write_char(e)
      }
    }
  }
  out.to_string()
}

///|
/// Exactly `width` hexadecimal digits, as Python demands.
fn hex_escape(
  cs : Array[Char],
  from : Int,
  width : Int,
  tok : Token,
  what : String,
) -> (Int, Int) raise {
  let mut n = 0
  for k = 0; k < width; k = k + 1 {
    let i = from + k
    if i >= cs.length() || !cs[i].is_ascii_hexdigit() {
      raise @err.syntax_error(
        "truncated \{what}XX escape".replace(old="XX", new="X".repeat(width)),
        tok.span,
      )
    }
    n = n * 16 + hex_value(cs[i])
  }
  (n, from + width)
}

///|
fn hex_value(c : Char) -> Int {
  if c.is_ascii_digit() {
    c.to_int() - '0'.to_int()
  } else {
    c.to_ascii_lowercase().to_int() - 'a'.to_int() + 10
  }
}

///|
/// `\N{LATIN SMALL LETTER A}`: the name between the braces.
fn named_escape(
  cs : Array[Char],
  from : Int,
  tok : Token,
) -> (String, Int) raise {
  if from >= cs.length() || cs[from] != '{' {
    raise @err.syntax_error("malformed \\N character escape", tok.span)
  }
  let mut i = from + 1
  let name = StringBuilder()
  while i < cs.length() && cs[i] != '}' {
    name.write_char(cs[i])
    i += 1
  }
  if i >= cs.length() {
    raise @err.syntax_error("malformed \\N character escape", tok.span)
  }
  (name.to_string(), i + 1)
}

///|
/// The Unicode names this port knows.
///
/// The full table is ~2 MB and PurePy's conformance suite contains no `\N`
/// escape at all; the handful below are what the tokenizer corpus uses. An
/// unknown name raises rather than guessing, so the gap is visible.
fn unicode_named(name : String, tok : Token) -> String raise {
  match name {
    "BULLET" => "\u{2022}"
    "NULL" => "\u{0000}"
    "SNAKE" => "\u{1F40D}"
    "GREEK SMALL LETTER PI" => "\u{03C0}"
    "LATIN SMALL LETTER E WITH ACUTE" => "\u{00E9}"
    _ =>
      raise @err.syntax_error(
        "unknown unicode character name '\{name}' (this port carries no name table)",
        tok.span,
      )
  }
}

///|
/// The bytes a bytes literal stands for. Every code point is ASCII -- the
/// tokenizer refused the literal otherwise -- but an escape can name any byte.
pub fn Token::bytes_value(self : Token) -> Bytes raise {
  let text = self.str_value()
  let out = Array::new()
  for c in text {
    let n = c.to_int()
    if n > 0xFF {
      raise @err.syntax_error(
        "bytes can only contain ASCII literal characters",
        self.span,
      )
    }
    out.push(n.to_byte())
  }
  Bytes::from_array(out)
}
