///|
/// The token dump the CLI prints and the oracle compares: `L:C-L:C KIND text`.
fn dump(source : String) -> String raise {
  let out = StringBuilder()
  for t in @lexer.lex_string(source) {
    out.write_string(
      "\{t.span.to_display()} \{t.kind.name()} \{@basic.py_repr(t.text)}\n",
    )
  }
  out.to_string()
}

///|
test "a statement, an indented block, a comment and a blank line" {
  inspect(
    dump("x = 1\nif x:\n    y = \"a\"  # hi\n\nprint(y)\n"),
    content=(
      #|1:0-1:1 NAME 'x'
      #|1:2-1:3 OP '='
      #|1:4-1:5 NUMBER '1'
      #|1:5-1:6 NEWLINE '\n'
      #|2:0-2:2 NAME 'if'
      #|2:3-2:4 NAME 'x'
      #|2:4-2:5 OP ':'
      #|2:5-2:6 NEWLINE '\n'
      #|3:0-3:4 INDENT '    '
      #|3:4-3:5 NAME 'y'
      #|3:6-3:7 OP '='
      #|3:8-3:11 STRING '"a"'
      #|3:13-3:17 COMMENT '# hi'
      #|3:17-3:18 NEWLINE '\n'
      #|4:0-4:1 NL '\n'
      #|5:0-5:0 DEDENT ''
      #|5:0-5:5 NAME 'print'
      #|5:5-5:6 OP '('
      #|5:6-5:7 NAME 'y'
      #|5:7-5:8 OP ')'
      #|5:8-5:9 NEWLINE '\n'
      #|6:0-6:0 ENDMARKER ''
      #|
    ),
  )
}

///|
test "a file that does not end in a newline still ends its logical line" {
  inspect(
    dump("if x:\n    if y:\n        z = 1"),
    content=(
      #|1:0-1:2 NAME 'if'
      #|1:3-1:4 NAME 'x'
      #|1:4-1:5 OP ':'
      #|1:5-1:6 NEWLINE '\n'
      #|2:0-2:4 INDENT '    '
      #|2:4-2:6 NAME 'if'
      #|2:7-2:8 NAME 'y'
      #|2:8-2:9 OP ':'
      #|2:9-2:10 NEWLINE '\n'
      #|3:0-3:8 INDENT '        '
      #|3:8-3:9 NAME 'z'
      #|3:10-3:11 OP '='
      #|3:12-3:13 NUMBER '1'
      #|3:13-3:14 NEWLINE ''
      #|4:0-4:0 DEDENT ''
      #|4:0-4:0 DEDENT ''
      #|4:0-4:0 ENDMARKER ''
      #|
    ),
  )
}

///|
test "inside brackets a newline is NL; outside it needs a backslash" {
  inspect(
    dump("a = (1,\n  2)\nb = 3 \\\n  + 4\n"),
    content=(
      #|1:0-1:1 NAME 'a'
      #|1:2-1:3 OP '='
      #|1:4-1:5 OP '('
      #|1:5-1:6 NUMBER '1'
      #|1:6-1:7 OP ','
      #|1:7-1:8 NL '\n'
      #|2:2-2:3 NUMBER '2'
      #|2:3-2:4 OP ')'
      #|2:4-2:5 NEWLINE '\n'
      #|3:0-3:1 NAME 'b'
      #|3:2-3:3 OP '='
      #|3:4-3:5 NUMBER '3'
      #|4:2-4:3 OP '+'
      #|4:4-4:5 NUMBER '4'
      #|4:5-4:6 NEWLINE '\n'
      #|5:0-5:0 ENDMARKER ''
      #|
    ),
  )
}

///|
test "an empty file is one end marker" {
  inspect(dump(""), content="1:0-1:0 ENDMARKER ''\n")
}

///|
test "blank and comment-only lines change no indentation" {
  inspect(
    dump("\n\n# c\n"),
    content=(
      #|1:0-1:1 NL '\n'
      #|2:0-2:1 NL '\n'
      #|3:0-3:3 COMMENT '# c'
      #|3:3-3:4 NL '\n'
      #|4:0-4:0 ENDMARKER ''
      #|
    ),
  )
}

///|
test "a dedent must land on a level that exists" {
  try @lexer.lex_string("if a:\n        b = 1\n    c = 2\n") |> ignore catch {
    @err.PurePyError(d) => {
      assert_eq(
        d.message(),
        "unindent does not match any outer indentation level",
      )
      assert_eq(d.span.unwrap().start.line, 3)
    }
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected an IndentationError")
  }
}

///|
test "tabs and spaces that disagree about depth" {
  try @lexer.lex_string("if a:\n\tb = 1\n        c = 2\n") |> ignore catch {
    @err.PurePyError(d) =>
      assert_eq(
        d.message(),
        "inconsistent use of tabs and spaces in indentation",
      )
    e => fail("unexpected \{e}")
  } noraise {
    _ => fail("expected a TabError")
  }
}

///|
/// A comment that runs to the end of the file with no newline after it. There
/// is no newline token to emit and nothing left to advance over; found by
/// `tools/fuzz.py`.
test "a comment-only line at the end of the file" {
  inspect(
    dump("# just a comment"),
    content=(
      #|1:0-1:16 COMMENT '# just a comment'
      #|1:16-1:17 NL ''
      #|2:0-2:0 ENDMARKER ''
      #|
    ),
  )
  inspect(
    dump("x = 1\n# trailing"),
    content=(
      #|1:0-1:1 NAME 'x'
      #|1:2-1:3 OP '='
      #|1:4-1:5 NUMBER '1'
      #|1:5-1:6 NEWLINE '\n'
      #|2:0-2:10 COMMENT '# trailing'
      #|2:10-2:11 NL ''
      #|3:0-3:0 ENDMARKER ''
      #|
    ),
  )
}
