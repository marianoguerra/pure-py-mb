///|
/// The `pure-py` command line tool: `tokens`, `dump`, `unparse`, `parse`,
/// `check`, `check-program` and `run` (see `implementation-plan.md` §2.1).
///
/// Filled in phase by phase; today it knows only its own usage.
fn main {
  let args = @env.args()
  match args[1:].to_owned() {
    [] | ["-h"] | ["--help"] => println(usage)
    ["--version"] => println("pure-py 0.1.0")
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
