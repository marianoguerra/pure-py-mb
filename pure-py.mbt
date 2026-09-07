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
pub fn check(m : @ast.Module) -> @err.Diagnostic? {
  @check.check_single(m)
}

///|
/// Whether a whole program is well formed.
pub fn check_program(tree : @program.SourceTree) -> @err.Diagnostic? {
  @check.check_program(tree)
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
) -> (String, @eval.RunResult) {
  @eval.run_program(tree, argv~)
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
