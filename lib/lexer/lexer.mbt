///|
/// Python 3.12's tokenizer.
///
/// The stream is CPython's `tokenize`, token for token and column for column:
/// `tools/pytokens.py` is the other half of that claim and `tools/conform.py`
/// checks it over every source in the suite. Where the two modules differ --
/// f-strings, which `tokenize` splits and this port keeps whole -- the Python
/// side does the collapsing, and the difference is written down in both.
///
/// The rules that are easy to get wrong, all of them CPython's:
///
///   * INDENT and DEDENT are emitted at the first token of a LOGICAL line and
///     never inside brackets. A blank or comment-only line produces neither
///     NEWLINE nor an indentation change.
///   * Indentation is measured twice: `col` with tabs advancing to the next
///     multiple of eight, and `altcol` with a tab counting as one. When the two
///     disagree about which of two lines is deeper, that is a `TabError`.
///   * A dedent must land ON an existing level, or it is an `IndentationError`.
///   * A file that does not end in a newline still ends its last logical line:
///     NEWLINE with no text, then the dedents, then the end marker.
///   * `match`, `case`, `type` and `_` are NAME here. Softness is the parser's.
using @token {type Token, type TokenKind}

///|
using @basic {type Pos, type Source, type Span}

///|
priv struct Lexer {
  src : Source
  chars : Array[Char]
  tokens : Array[Token]
  /// Code-point index of the next character.
  mut i : Int
  /// 1-based line of `i`.
  mut line : Int
  /// Code-point index at which the current line begins.
  mut line_start : Int
  /// Nesting depth of `()`, `[]` and `{}`. Inside brackets a newline is NL,
  /// indentation is not measured and a backslash is not needed.
  mut depth : Int
  /// True when `i` is at the first character of a physical line that is also
  /// the first physical line of a logical line.
  mut fresh_line : Bool
  /// True when a token other than a comment has been emitted since the last
  /// end of line, so the next newline closes a logical line.
  mut pending_newline : Bool
  /// The indentation stack, in the two units CPython measures.
  indents : Array[Int]
  alt_indents : Array[Int]
}

///|
/// Tokenize a source. Raises on a lexical error, with the message CPython
/// would raise and the position it would report.
pub fn lex(src : Source) -> Array[Token] raise {
  let lx = {
    src,
    chars: src.chars,
    tokens: [],
    i: 0,
    line: 1,
    line_start: 0,
    depth: 0,
    fresh_line: true,
    pending_newline: false,
    indents: [0],
    alt_indents: [0],
  }
  lx.run()
  lx.tokens
}

///|
/// Tokenize a string, for a test or a caller with no file.
pub fn lex_string(
  text : String,
  name? : String = "<string>",
) -> Array[Token] raise {
  lex(Source::new(text, name~))
}

// ---------------------------------------------------------------------------
// Cursor

///|
fn Lexer::at_end(self : Lexer) -> Bool {
  self.i >= self.chars.length()
}

///|
/// The character `n` ahead, or `'\u{0}'` past the end -- which never occurs in
/// a Python source that got this far, and is not a character any rule accepts.
fn Lexer::peek(self : Lexer, n : Int) -> Char {
  let k = self.i + n
  if k < self.chars.length() {
    self.chars[k]
  } else {
    '\u{0}'
  }
}

///|
fn Lexer::pos(self : Lexer) -> Pos {
  {
    line: self.line,
    col: self.i - self.line_start,
    offset: self.src.offset_of(self.i),
  }
}

///|
/// A position on the current line at a given code-point index.
fn Lexer::pos_at(self : Lexer, index : Int) -> Pos {
  {
    line: self.line,
    col: index - self.line_start,
    offset: self.src.offset_of(index),
  }
}

///|
/// A position at column 0 of a line that may not exist -- where the dedents
/// and the end marker of a finished file sit.
fn Lexer::pos_line_start(self : Lexer, line : Int) -> Pos {
  { line, col: 0, offset: self.src.offset_of(self.chars.length()), }
}

///|
/// Advance one character, keeping the line and its start in step.
fn Lexer::bump(self : Lexer) -> Unit {
  if self.chars[self.i] == '\n' {
    self.line += 1
    self.line_start = self.i + 1
  }
  self.i += 1
}

///|
/// The text between two code-point indexes.
fn Lexer::text(self : Lexer, from : Int, to : Int) -> String {
  String::from_array(self.chars[from:to])
}

///|
fn Lexer::emit(
  self : Lexer,
  kind : TokenKind,
  from : Pos,
  to : Pos,
  text : String,
) -> Unit {
  self.tokens.push({ kind, text, span: { start: from, end: to, }, })
}

///|
fn fail(msg : String, at : Pos) -> @err.PurePyError {
  @err.syntax_error(msg, Span::at(at))
}

// ---------------------------------------------------------------------------
// The driver

///|
fn Lexer::run(self : Lexer) -> Unit raise {
  while true {
    if self.fresh_line && self.depth == 0 {
      if self.line_start_work() {
        continue
      }
    } else {
      self.fresh_line = false
    }
    if self.at_end() {
      break
    }
    self.skip_inline_space()
    if self.at_end() {
      break
    }
    let c = self.peek(0)
    if c == '#' {
      self.scan_comment()
    } else if c == '\n' {
      self.scan_end_of_line()
    } else if c == '\\' {
      self.scan_continuation()
    } else if self.at_string_start() {
      self.scan_string()
    } else if c.is_ascii_digit() || (c == '.' && self.peek(1).is_ascii_digit()) {
      self.scan_number()
    } else if is_ident_start(c) {
      self.scan_name()
    } else {
      self.scan_operator()
    }
  }
  self.finish()
}

///|
/// Everything that happens before the first token of a physical line, at
/// bracket depth zero. Returns true when the line produced no logical content
/// and the driver should start over.
fn Lexer::line_start_work(self : Lexer) -> Bool raise {
  let (col, altcol, next) = self.measure_indent()
  let c = if next < self.chars.length() { self.chars[next] } else { '\u{0}' }
  // A blank or comment-only line changes no indentation and closes no logical
  // line. `\u{0}` here is the end of the file, which is neither.
  if c == '\n' || c == '#' || next >= self.chars.length() {
    self.i = next
    if next >= self.chars.length() {
      self.fresh_line = false
      return false
    }
    if c == '#' {
      self.scan_comment()
      // A comment can run to the end of the file with no newline after it.
      // CPython still ends the line: an NL with no text, and then the end
      // marker on the line after.
      if self.at_end() {
        let start = self.pos()
        let end : Pos = {
          line: start.line,
          col: start.col + 1,
          offset: start.offset,
        }
        self.emit(NL, start, end, "")
        self.line += 1
        self.line_start = self.i
        self.fresh_line = false
        return false
      }
    }
    let start = self.pos()
    let end : Pos = {
      line: start.line,
      col: start.col + 1,
      offset: self.src.offset_of(self.i + 1),
    }
    self.bump()
    self.emit(NL, start, end, "\n")
    self.fresh_line = true
    return true
  }
  self.apply_indent(col, altcol, next)
  self.i = next
  self.fresh_line = false
  false
}

///|
/// Measure the run of indentation from `self.i` in CPython's two units, and
/// return the index of the first character that is not indentation.
///
/// A form feed resets both counts, as it does in CPython.
fn Lexer::measure_indent(self : Lexer) -> (Int, Int, Int) {
  let mut col = 0
  let mut altcol = 0
  let mut k = self.i
  while k < self.chars.length() {
    match self.chars[k] {
      ' ' => {
        col += 1
        altcol += 1
      }
      '\t' => {
        col = col / 8 * 8 + 8
        altcol += 1
      }
      '\u{0C}' => {
        col = 0
        altcol = 0
      }
      _ => break
    }
    k += 1
  }
  (col, altcol, k)
}

///|
/// Compare the measured indentation with the stack and emit what the change
/// calls for, at `next` -- which is where CPython puts both tokens.
fn Lexer::apply_indent(
  self : Lexer,
  col : Int,
  altcol : Int,
  next : Int,
) -> Unit raise {
  let top = self.indents[self.indents.length() - 1]
  let alt_top = self.alt_indents[self.alt_indents.length() - 1]
  let tab_error = "inconsistent use of tabs and spaces in indentation"
  if col == top {
    if altcol != alt_top {
      raise fail(tab_error, self.pos_at(next))
    }
  } else if col > top {
    if altcol <= alt_top {
      raise fail(tab_error, self.pos_at(next))
    }
    self.indents.push(col)
    self.alt_indents.push(altcol)
    self.emit(
      Indent,
      self.pos_at(self.i),
      self.pos_at(next),
      self.text(self.i, next),
    )
  } else {
    while self.indents.length() > 1 &&
          col < self.indents[self.indents.length() - 1] {
      let _ = self.indents.pop()
      let _ = self.alt_indents.pop()
      self.emit(Dedent, self.pos_at(next), self.pos_at(next), "")
    }
    if col != self.indents[self.indents.length() - 1] {
      raise fail(
        "unindent does not match any outer indentation level",
        self.pos_at(next),
      )
    }
    if altcol != self.alt_indents[self.alt_indents.length() - 1] {
      raise fail(tab_error, self.pos_at(next))
    }
  }
}

///|
/// Spaces, tabs and form feeds between tokens. Never a newline: that is a
/// token.
fn Lexer::skip_inline_space(self : Lexer) -> Unit {
  while !self.at_end() {
    match self.peek(0) {
      ' ' | '\t' | '\u{0C}' => self.i += 1
      _ => break
    }
  }
}

///|
fn Lexer::scan_comment(self : Lexer) -> Unit {
  let start = self.pos()
  let from = self.i
  while !self.at_end() && self.peek(0) != '\n' {
    self.i += 1
  }
  self.emit(Comment, start, self.pos(), self.text(from, self.i))
}

///|
/// The newline that ends a physical line: NEWLINE when it closes a logical
/// line, NL when it does not.
fn Lexer::scan_end_of_line(self : Lexer) -> Unit {
  let start = self.pos()
  // `tokenize` ends a NEWLINE on the line it began, one column further on --
  // not at column 0 of the next line, which is where the cursor lands.
  let end : Pos = {
    line: start.line,
    col: start.col + 1,
    offset: self.src.offset_of(self.i + 1),
  }
  self.bump()
  if self.depth > 0 || !self.pending_newline {
    self.emit(NL, start, end, "\n")
  } else {
    self.emit(Newline, start, end, "\n")
    self.pending_newline = false
  }
  self.fresh_line = self.depth == 0
}

///|
/// A backslash at the end of a line joins it to the next. Anything else after
/// the backslash is CPython's "unexpected character after line continuation
/// character".
fn Lexer::scan_continuation(self : Lexer) -> Unit raise {
  if self.peek(1) == '\n' {
    self.i += 1
    self.bump()
    self.fresh_line = false
  } else if self.i + 1 >= self.chars.length() {
    raise fail("unexpected EOF while parsing", self.pos())
  } else {
    raise fail(
      "unexpected character after line continuation character",
      self.pos_at(self.i + 1),
    )
  }
}

///|
/// The end of the file: close the last logical line, unwind the indentation
/// stack, and mark the end.
fn Lexer::finish(self : Lexer) -> Unit {
  let mut line = self.line
  if self.pending_newline {
    let start = self.pos()
    let end : Pos = {
      line: start.line,
      col: start.col + 1,
      offset: start.offset,
    }
    self.emit(Newline, start, end, "")
    self.pending_newline = false
    line += 1
  }
  let at = self.pos_line_start(line)
  while self.indents.length() > 1 {
    let _ = self.indents.pop()
    let _ = self.alt_indents.pop()
    self.emit(Dedent, at, at, "")
  }
  self.emit(EndMarker, at, at, "")
}
