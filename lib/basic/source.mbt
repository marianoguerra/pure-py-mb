///|
/// A source file: its name, its text, and the three indexes everything else
/// needs to talk about a position in it.
///
/// The text is Python's, after what Python calls universal newlines: `\r\n`
/// and a lone `\r` become `\n`. That is done here, once, so that no lexer rule
/// has to think about it -- and it is done to the SOURCE only. A string literal
/// that spells `\r` still means a carriage return.
///
/// A leading byte-order mark is dropped, as CPython's tokenizer drops it.
pub(all) struct Source {
  name : String
  /// The normalised text.
  text : String
  /// Its code points. The lexer indexes this, not `text`: Python counts
  /// characters and MoonBit's `String` counts UTF-16 code units.
  chars : Array[Char]
  /// `offsets[i]` is the UTF-16 offset of `chars[i]`; one longer than `chars`,
  /// so `offsets[chars.length()]` is the length of `text`.
  offsets : Array[Int]
  /// `line_starts[n]` is the code-point index at which line `n + 1` begins.
  line_starts : Array[Int]
}

///|
pub fn Source::new(text : String, name? : String = "<string>") -> Source {
  let normalised = normalise_newlines(text)
  let chars = normalised.to_array()
  let offsets = Array::make(chars.length() + 1, 0)
  let mut off = 0
  for i, c in chars {
    offsets[i] = off
    off += if c.to_int() >= 0x10000 { 2 } else { 1 }
  }
  offsets[chars.length()] = off
  let line_starts = [0]
  for i, c in chars {
    if c == '\n' {
      line_starts.push(i + 1)
    }
  }
  { name, text: normalised, chars, offsets, line_starts, }
}

///|
/// `\r\n` and a lone `\r` become `\n`; a leading U+FEFF is dropped.
fn normalise_newlines(text : String) -> String {
  let text = if text.has_prefix("\u{FEFF}") {
    text[1:].to_owned()
  } else {
    text
  }
  if !text.contains("\r") {
    return text
  }
  let out = StringBuilder()
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\r' {
      out.write_char('\n')
      if i + 1 < chars.length() && chars[i + 1] == '\n' {
        i += 1
      }
    } else {
      out.write_char(c)
    }
    i += 1
  }
  out.to_string()
}

///|
/// How many code points the source has. One past the last is where the
/// tokenizer's end marker sits.
pub fn Source::length(self : Source) -> Int {
  self.chars.length()
}

///|
pub fn Source::line_count(self : Source) -> Int {
  self.line_starts.length()
}

///|
/// The text of a 1-based line, without its newline. Out of range gives "".
pub fn Source::line_text(self : Source, line : Int) -> String {
  if line < 1 || line > self.line_starts.length() {
    return ""
  }
  let start = self.line_starts[line - 1]
  let mut end = start
  while end < self.chars.length() && self.chars[end] != '\n' {
    end += 1
  }
  String::from_array(self.chars[start:end])
}

///|
/// The UTF-16 offset of a code-point index.
pub fn Source::offset_of(self : Source, index : Int) -> Int {
  if index <= 0 {
    0
  } else if index >= self.offsets.length() {
    self.offsets[self.offsets.length() - 1]
  } else {
    self.offsets[index]
  }
}

///|
/// The code-point index of a UTF-16 offset: the inverse of `offset_of`.
///
/// A `Pos` carries both, and everything that walks the source walks code
/// points, so a caller handed a `Pos` from somewhere else needs the way back.
/// A binary search rather than a scan, because `offsets` is sorted by
/// construction -- it is a running total.
pub fn Source::index_of_offset(self : Source, offset : Int) -> Int {
  let mut lo = 0
  let mut hi = self.offsets.length() - 1
  while lo < hi {
    let mid = (lo + hi) / 2
    if self.offsets[mid] < offset {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// The text a span covers.
pub fn Source::slice(self : Source, span : Span) -> String {
  self.text[span.start.offset:span.end.offset].to_owned()
}

///|
/// The column CPython's `ast` would report for this position: UTF-8 BYTES from
/// the start of the line, not code points.
///
/// The reference checker prints `node.col_offset`, so every message in its
/// format goes through here. Nothing else in this port converts.
pub fn Source::byte_col(self : Source, pos : Pos) -> Int {
  let start = if pos.line >= 1 && pos.line <= self.line_starts.length() {
    self.line_starts[pos.line - 1]
  } else {
    return pos.col
  }
  let mut bytes = 0
  for k = 0; k < pos.col; k = k + 1 {
    let i = start + k
    if i >= self.chars.length() {
      break
    }
    bytes += utf8_length(self.chars[i])
  }
  bytes
}

///|
/// How many bytes a code point takes in UTF-8.
fn utf8_length(c : Char) -> Int {
  let n = c.to_int()
  if n < 0x80 {
    1
  } else if n < 0x800 {
    2
  } else if n < 0x10000 {
    3
  } else {
    4
  }
}
