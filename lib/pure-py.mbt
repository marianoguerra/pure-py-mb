///|
/// The façade: the whole of PurePy in six calls.
///
/// A consumer that wants to read Python, decide whether it is PurePy, and
/// evaluate it should need one import and one package's worth of names. The
/// packages beneath are public too -- a code generator wants `ast` and
/// `write` alone, and a language server wants `error` -- but nothing forces a
/// caller to know the layering.
///
/// Every call here answers with a `Diagnostic` rather than raising, except
/// `parse`, where a syntax error is the only thing that can go wrong and a
/// caller almost always wants to stop.
pub fn parse(source : String, name? : String = "<string>") -> @ast.Module raise {
  @parser.parse(@basic.Source::new(source, name~))
}

///|
/// Whether a module is within PurePy's syntax: the sieve of `syntax.py`.
///
/// `None` means yes. A rejection carries exit code 1 for a form PurePy
/// excludes and 2 for one it plans to accept and does not yet.
pub fn sieve(m : @ast.Module) -> @err.Diagnostic? {
  @sieve.result(m)
}

///|
/// Whether a single module is well formed, with only the predefined modules
/// importable -- what `pure-py check FILE` decides.
///
/// The sieve runs first and its verdict is the answer when it rejects. That
/// is not a convenience: the checker is written against the subset the sieve
/// leaves, and handed a `for` loop it has no case to take. Calling
/// `@check.check_single` directly skips this and is the caller's business.
pub fn check(m : @ast.Module, host? : @eval.Host) -> @err.Diagnostic? {
  match @sieve.result(m) {
    Some(d) => Some(d)
    None =>
      @check.check_single(
        m,
        host_members=match host {
          Some(h) => h.member_names()
          None => Map([])
        },
      )
  }
}

///|
/// Whether a whole program is well formed.
///
/// Every module is sieved first, for the reason `check` is. A tree built by
/// `source_tree_from` has been sieved already -- discovery does it, and a
/// module the sieve rejects is a program-level error naming the file -- so
/// this only bites on a tree assembled in memory.
pub fn check_program(
  tree : @program.SourceTree,
  host? : @eval.Host,
) -> @err.Diagnostic? {
  for q in tree.module_names() {
    match tree.get(q) {
      Some(m) =>
        match @sieve.result(m) {
          Some(d) => return Some(d.at_path(tree.path_of(q)))
          None => ()
        }
      None => ()
    }
  }
  @check.check_program(
    tree,
    host_members=match host {
      Some(h) => h.member_names()
      None => Map([])
    },
  )
}

///|
/// Evaluate a program, answering with everything it printed and how it ended.
///
/// The semantics is defined for well-formed programs, so a caller should
/// `check_program` first; this does not, so that a caller studying an
/// undefined operation can reach one.
pub fn run(
  tree : @program.SourceTree,
  argv? : Array[String] = [],
  max_depth? : Int = @eval.default_max_depth,
) -> (String, @eval.RunResult) {
  @eval.run_program(tree, argv~, max_depth~)
}

///|
/// Evaluate a program against a host: the embedding path.
///
/// The host receives output as it happens, supplies `sys.argv`, defines
/// whatever modules the guest may import, and answers calls to the functions
/// in them. `docs/embedding.mbt.md` is the whole of it, with examples.
///
/// A host function may answer later rather than now, in which case the run
/// parks and this returns `Suspended`; `done` is called with the real answer
/// when the host resumes it. A host that always answers on the spot can
/// ignore `done` and read the return value.
pub fn run_with(
  tree : @program.SourceTree,
  host : @eval.Host,
  max_depth? : Int = @eval.default_max_depth,
  done? : (@eval.RunResult) -> Unit = fn(_) {  },
) -> @eval.RunResult {
  @eval.run_with(tree, host, max_depth~, done~)
}

///|
/// Python source rebuilt from a tree, which parses back to the same tree.
pub fn unparse(m : @ast.Module) -> String {
  @write.unparse(m)
}

///|
/// A program built in memory: module name to parsed module, with the entry
/// under `__main__`.
pub fn source_tree(modules : Map[String, @ast.Module]) -> @program.SourceTree {
  @program.SourceTree::of(modules)
}

///|
/// A program discovered from an entry file on disk.
///
/// `sweep` decides whether every `.py` beside the entry belongs to the
/// program -- which is what checking wants -- or only what it imports, which
/// is what running wants.
pub fn source_tree_from(
  entry_path : String,
  sweep? : Bool = true,
) -> @program.SourceTree raise {
  @program.SourceTree::from_entry(
    entry_path,
    predefined=@check.predefined_module_names(),
    sweep~,
  )
}
