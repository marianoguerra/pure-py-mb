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
    ["--version"] => println("pure-py 0.2.0")
    ["tokens", path] => @sys.exit(cmd_tokens(path))
    ["dump", path] => @sys.exit(cmd_dump(path, pos=false))
    ["unparse", path] => @sys.exit(cmd_unparse(path))
    ["parse", .. paths] => @sys.exit(cmd_parse(paths))
    ["check", .. rest] => {
      let (format, color, paths) = parse_error_options(rest)
      @sys.exit(cmd_check(paths, format~, color~))
    }
    ["check-program", path] => @sys.exit(cmd_check_program(path))
    ["run", path, .. rest] => @sys.exit(cmd_run(path, rest))
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
fn cmd_check(
  paths : Array[String],
  format~ : @render.Format,
  color~ : @style.ColorMode,
) -> Int {
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
      None => if format is Short { println("\{path}: ok") }
      Some(diag) => {
        if format is Short {
          println(diag.short(path, source=src))
        } else {
          println(render_diagnostic(diag, path, src, format~, color~))
        }
        code = diag.exit_code()
      }
    }
  }
  code
}

///|
/// Render a rejection with its source, through `error-report`.
fn render_diagnostic(
  d : @err.Diagnostic,
  path : String,
  src : @basic.Source,
  format~ : @render.Format,
  color~ : @style.ColorMode,
) -> String {
  let sources = @report.Sources::new()
  let id = sources.add(path, src.text)
  let config = { ..@render.default_config, format, color, }
  @render.render_string(d.to_report(id), sources, config, is_tty=false)
}

///|
/// `--error-format short|human|json` and `--color auto|always|never`.
///
/// `short` is the reference's own format and the default, because the
/// conformance harness compares against the reference; the other two are for
/// people.
fn parse_error_options(
  args : ArrayView[String],
) -> (@render.Format, @style.ColorMode, Array[String]) {
  let mut format = @render.Format::Short
  let mut color = @style.ColorMode::Auto
  let paths : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--error-format" && i + 1 < args.length() {
      format = match args[i + 1] {
        "human" | "rich" => Rich
        "compact" => Compact
        "json" => Json
        _ => Short
      }
      i += 2
    } else if a == "--color" && i + 1 < args.length() {
      color = match args[i + 1] {
        "always" => Always
        "never" => Never
        _ => Auto
      }
      i += 2
    } else {
      paths.push(a)
      i += 1
    }
  }
  (format, color, paths)
}

///|
/// `check-program MAIN`: discover the program from its entry file and decide
/// whether the whole of it is well formed.
///
/// The format is `check_program.py`'s: `MAIN: ok`, or the message alone --
/// which for a module-level rejection carries the offending file's path and
/// no line, because that is what the reference prints.
fn cmd_check_program(path : String) -> Int {
  match @check.check_entry(path) {
    None => {
      println("\{path}: ok")
      0
    }
    Some(d) => {
      println(d.message())
      d.exit_code()
    }
  }
}

///|
/// `run MAIN [ARGS...]`: evaluate a program.
///
/// `sys.argv` is `[MAIN, ARGS...]`, so `argv[0]` is the path as it was
/// given, exactly as Python has it.
///
/// Output is buffered and flushed before an abort message, so a program that
/// prints and then fails shows both in the order Python shows them.
fn cmd_run(path : String, args : ArrayView[String]) -> Int {
  let argv = [path]
  for a in args {
    argv.push(a)
  }
  let tree = @program.SourceTree::from_entry(
    path,
    predefined=@check.predefined_module_names(),
    sweep=false,
  ) catch {
    @err.PurePyError(d) => {
      println(d.message())
      return d.exit_code()
    }
    e => {
      println("pure-py: \{e}")
      return 1
    }
  }
  // A program that is not well formed does not run. The conformance harness
  // never asks for one, but a person might, and the semantics is defined for
  // well-formed programs only.
  match @check.check_program(tree) {
    Some(d) => {
      println(d.message())
      return d.exit_code()
    }
    None => ()
  }
  let (output, result) = @eval.run_program(tree, argv~)
  write_stdout(output)
  match result {
    Finished => 0
    // `sys.exit(n)` leaves with status n and prints nothing.
    Terminated(SystemExit(n), _) => n.to_int()
    Terminated(k, site) => {
      // Python's traceback ends with the exception's name and message, and
      // that last line is what the suite's `.exception.expected` holds. The
      // frame line between them is Python's shape too, and it is a line and
      // not a column because that is what CPython prints; the column is in
      // the `Site` for a caller that wants it.
      let frame = match site {
        Some(s) =>
          "  File \"\{tree.path_of(s.in_module)}\", line \{s.span.start.line}\n"
        None => ""
      }
      write_stderr("Traceback (most recent call last):\n" + frame + k.to_text())
      1
    }
    // An operation the semantics leaves undefined. Chapter 1 allows an
    // implementation to abort or to produce Python's answer; this one aborts,
    // so that the suite's dynamically excluded tests are checked.
    Undefined(op) => {
      write_stderr("stuck: " + op)
      5
    }
    // `run_program` builds the host itself, and that host answers no foreign
    // call, so a run started here cannot park. The arm exists because the
    // type allows what this caller does not.
    Suspended => {
      write_stderr("stuck: a host call suspended in a run that has no host")
      5
    }
  }
}

///|
/// Write a line to standard error.
///
/// MoonBit's core offers no standard error, so this writes to `/dev/stderr`,
/// which every POSIX system provides. A system that does not have it falls
/// back to standard output: the message is then in the wrong stream, but it
/// is not lost, and the conformance harness compares the two together.
fn write_stderr(text : String) -> Unit {
  // One call per run: `write_string_to_file` opens for TRUNCATION, so two
  // calls would leave only the second when standard error is a file.
  @fs.write_string_to_file("/dev/stderr", text + "\n") catch {
    _ => println(text)
  }
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
