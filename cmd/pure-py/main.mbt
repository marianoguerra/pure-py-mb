///|
/// The `pure-py` command line tool.
///
/// It is the thing the conformance harness drives, so its exit codes are part
/// of the specification (`implementation-plan.md` §2.1) and not a convenience:
///
///   0  accepted, or a run that finished
///   1  a prohibited form, or a Python syntax error, or an abort
///   2  a form that is planned and not yet supported
///   3  an ill-formed module
///   4  an ill-formed program
///   5  an operation the semantics leaves undefined
fn main {
  let args = @env.args()[1:].to_owned()
  match args {
    [] | ["-h"] | ["--help"] => println(usage)
    ["--version"] => println("pure-py 0.1.0")
    ["tokens", path] => @sys.exit(cmd_tokens(path))
    ["dump", path] => @sys.exit(cmd_dump(path, pos=false))
    ["unparse", path] => @sys.exit(cmd_unparse(path))
    ["parse", .. paths] => @sys.exit(cmd_parse(paths))
    ["check", .. paths] => @sys.exit(cmd_check(paths))
    ["dump", path, "--pos"] | ["dump", "--pos", path] =>
      @sys.exit(cmd_dump(path, pos=true))
    [cmd, ..] => {
      println("pure-py: unknown command '\{cmd}'")
      println(usage)
      @sys.exit(2)
    }
  }
}

///|
let usage : String =
  #|usage: pure-py <command> [options] FILE...
  #|
  #|  tokens FILE           one token per line
  #|  dump FILE [--pos]     the abstract syntax tree
  #|  unparse FILE          Python source regenerated from the tree
  #|  parse FILE...         reject what PurePy excludes syntactically
  #|  check FILE...         decide module well-formedness
  #|  check-program MAIN    decide program well-formedness
  #|  run MAIN [ARGS...]    evaluate a program

///|
/// Read a source file, or report why not and stop.
fn read_source(path : String) -> @basic.Source {
  try @fs.read_file_to_string(path) catch {
    _ => {
      println("pure-py: cannot read \{path}")
      @sys.exit(1)
      panic()
    }
  } noraise {
    text => @basic.Source::new(text, name=path)
  }
}

///|
/// `tokens FILE`: one token per line, `L:C-L:C KIND text`, the format
/// `tools/pytokens.py` prints for CPython's `tokenize`.
fn cmd_tokens(path : String) -> Int {
  let src = read_source(path)
  try @lexer.lex(src) catch {
    @err.PurePyError(d) => {
      println("!error \{d.short(path, source=src)}")
      1
    }
    e => {
      println("!error \{e}")
      1
    }
  } noraise {
    tokens => {
      let out = StringBuilder()
      for t in tokens {
        out.write_string(
          "\{t.span.to_display()} \{t.kind.name()} \{@basic.py_repr(t.text)}\n",
        )
      }
      write_stdout(out.to_string())
      0
    }
  }
}

///|
/// `dump FILE [--pos]`: the tree, in the format `tools/pyast_dump.py` prints
/// for CPython's.
fn cmd_dump(path : String, pos~ : Bool) -> Int {
  let src = read_source(path)
  try @parser.parse(src) catch {
    @err.PurePyError(d) => {
      println("!error \{d.short(path, source=src)}")
      1
    }
    e => {
      println("!error \{e}")
      1
    }
  } noraise {
    m => {
      write_stdout(@ast.dump(m, pos~))
      0
    }
  }
}

///|
/// `unparse FILE`: the source rebuilt from the tree.
fn cmd_unparse(path : String) -> Int {
  let src = read_source(path)
  try @parser.parse(src) catch {
    @err.PurePyError(d) => {
      println("!error \{d.short(path, source=src)}")
      1
    }
    e => {
      println("!error \{e}")
      1
    }
  } noraise {
    m => {
      write_stdout(@write.unparse(m))
      0
    }
  }
}

///|
/// `parse FILE...`: what the sieve says about each file.
///
/// The format and the exit codes are `syntax.py`'s: `FILE: ok`, or
/// `FILE:line:col: message` with the column in UTF-8 BYTES, which is what
/// CPython's `col_offset` counts and what the reference therefore prints.
/// Several files in one invocation, and the LAST non-zero code wins.
fn cmd_parse(paths : ArrayView[String]) -> Int {
  let mut code = 0
  for path in paths {
    let src = read_source(path)
    let d = try @parser.parse(src) catch {
      @err.PurePyError(d) => Some(d.as_parse_error())
      e => Some(@err.Diagnostic::new(PythonSyntax(msg="parse error: \{e}")))
    } noraise {
      m => @sieve.result(m)
    }
    match d {
      None => println("\{path}: ok")
      Some(diag) => {
        println(diag.short(path, source=src))
        code = diag.exit_code()
      }
    }
  }
  code
}

///|
/// `check FILE...`: module well-formedness.
///
/// The sieve runs first, and its verdict is this command's when it rejects --
/// `check_module.py` does not run it and walks a node it has no case for
/// instead, so the reference's own runner never calls check on a file parse
/// rejected. The golden records the sieve's answer for those files.
fn cmd_check(paths : ArrayView[String]) -> Int {
  let mut code = 0
  for path in paths {
    let src = read_source(path)
    let d = try @parser.parse(src) catch {
      @err.PurePyError(d) => Some(d.as_parse_error())
      e => Some(@err.Diagnostic::new(PythonSyntax(msg="parse error: \{e}")))
    } noraise {
      m =>
        match @sieve.result(m) {
          Some(d) => Some(d)
          None => @check.check_single(m)
        }
    }
    match d {
      None => println("\{path}: ok")
      Some(diag) => {
        println(diag.short(path, source=src))
        code = diag.exit_code()
      }
    }
  }
  code
}

///|
/// Write to standard output with no newline of our own.
///
/// MoonBit's core offers `println` and nothing else, so the last newline of
/// the text is the one `println` adds. Every buffer this tool writes either is
/// empty or ends in a newline -- a token dump does, and so does the output of
/// a PurePy program, whose only output primitive is `print` -- so nothing is
/// lost. A buffer that does not end in one is printed with a newline added,
/// and that case is unreachable rather than tolerated.
fn write_stdout(text : String) -> Unit {
  if text.is_empty() {
    return
  }
  if text.has_suffix("\n") {
    println(text[:text.length() - 1])
  } else {
    println(text)
  }
}
