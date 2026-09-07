///|
/// CPython's `ast` reports `col_offset` in UTF-8 bytes; `tokenize` and this
/// port report code points. The conversion is the only place the difference is
/// allowed to show, so it is the thing to test.
test "byte_col converts code points to UTF-8 bytes" {
  let src = @basic.Source::new("x = 'é' + 'a'\ny = 1\n")
  // Column 0 is column 0 in both units, whatever precedes it.
  assert_eq(src.byte_col({ line: 1, col: 0, offset: 0, }), 0)
  // Up to the `é` the two agree: eight ASCII characters.
  assert_eq(src.byte_col({ line: 1, col: 5, offset: 5, }), 5)
  // After it they do not: `é` is one code point and two bytes.
  assert_eq(src.byte_col({ line: 1, col: 6, offset: 6, }), 7)
  assert_eq(src.byte_col({ line: 1, col: 10, offset: 10, }), 11)
  // A line with nothing but ASCII is unaffected.
  assert_eq(src.byte_col({ line: 2, col: 4, offset: 18, }), 4)
}

///|
test "byte_col over an astral character" {
  // U+1F40D is one code point, four UTF-8 bytes and two UTF-16 code units.
  let src = @basic.Source::new("s = '🐍' + 'x'\n")
  assert_eq(src.byte_col({ line: 1, col: 5, offset: 5, }), 5)
  assert_eq(src.byte_col({ line: 1, col: 6, offset: 7, }), 9)
  assert_eq(src.length(), 14)
  // The UTF-16 offset of the character after the snake is one past two units.
  assert_eq(src.offset_of(6), 7)
  assert_eq(src.offset_of(src.length()), 15)
}

///|
test "universal newlines, and only in the source" {
  let src = @basic.Source::new("a = 1\r\nb = 2\rc = 3\n")
  assert_eq(src.text, "a = 1\nb = 2\nc = 3\n")
  assert_eq(src.line_count(), 4)
  assert_eq(src.line_text(2), "b = 2")
  assert_eq(src.line_text(4), "")
}

///|
test "a byte-order mark is not part of the first token" {
  let src = @basic.Source::new("\u{FEFF}x = 1\n")
  assert_eq(src.line_text(1), "x = 1")
}

///|
test "spans merge and measure in UTF-16 code units" {
  let a : @basic.Span = {
    start: { line: 1, col: 0, offset: 0, },
    end: { line: 1, col: 1, offset: 1, },
  }
  let b : @basic.Span = {
    start: { line: 1, col: 4, offset: 4, },
    end: { line: 2, col: 2, offset: 9, },
  }
  assert_eq(a.merge(b), { start: a.start, end: b.end, })
  assert_eq(b.merge(a), { start: a.start, end: b.end, })
  assert_eq(a.merge(b).units(), 9)
  assert_eq(@basic.Span::at(b.start).units(), 0)
  assert_eq(a.merge(b).to_display(), "1:0-2:2")
}

///|
test "slice returns the text a span covers" {
  let src = @basic.Source::new("print('hi')\n")
  let span : @basic.Span = {
    start: { line: 1, col: 6, offset: 6, },
    end: { line: 1, col: 10, offset: 10, },
  }
  assert_eq(src.slice(span), "'hi'")
}
