///|
/// A position in a Python source file.
///
/// Three numbers in three units, and keeping them apart is the first thing
/// this port has to get right, because Python itself does not:
///
///   * `line` is 1-based, as everything that reports a Python position is.
///   * `col` counts CODE POINTS from the start of the line, 0-based. This is
///     what the `tokenize` module reports and what a person means by a column.
///     CPython's `ast` nodes carry `col_offset`, which counts UTF-8 BYTES; the
///     reference checker prints that number, so a message in its format is
///     rendered through `Source::byte_col` and nothing else converts.
///   * `offset` counts UTF-16 code units from the start of the source, 0-based.
///     It exists to slice a MoonBit `String` and to hand a span to
///     `error-report`, and it is never reported.
pub(all) struct Pos {
  line : Int
  col : Int
  offset : Int
} derive(Eq, Compare, Debug)

///|
/// The position before the first character.
pub let origin : Pos = { line: 1, col: 0, offset: 0, }

///|
/// `line:col`, in the format the reference's messages use.
pub fn Pos::to_display(self : Pos) -> String {
  "\{self.line}:\{self.col}"
}

///|
/// A half-open range of a source file.
pub(all) struct Span {
  start : Pos
  end : Pos
} derive(Eq, Debug)

///|
/// The empty span at `p`, for something with no extent -- an unexpected end of
/// input, or a token the parser wanted and did not get.
pub fn Span::at(p : Pos) -> Span {
  { start: p, end: p, }
}

///|
/// A span standing for "nowhere": what the builders of `ast` give a node that
/// a code generator made up rather than read.
pub let nowhere : Span = { start: origin, end: origin, }

///|
/// The smallest span covering both.
pub fn Span::merge(self : Span, other : Span) -> Span {
  let start = if self.start.offset <= other.start.offset {
    self.start
  } else {
    other.start
  }
  let end = if self.end.offset >= other.end.offset {
    self.end
  } else {
    other.end
  }
  { start, end, }
}

///|
/// Length in UTF-16 code units -- the unit `error-report` spans are in.
pub fn Span::units(self : Span) -> Int {
  self.end.offset - self.start.offset
}

///|
/// `l:c-l:c`, for a token dump.
pub fn Span::to_display(self : Span) -> String {
  "\{self.start.to_display()}-\{self.end.to_display()}"
}
