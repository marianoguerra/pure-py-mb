///|
/// Program well-formedness: the entry module checked against everything the
/// source tree contains.
///
/// A port of the reference's `walk_program`. The whole of it is one rule that
/// the module checker does not have: a rejection is attributed to the FILE it
/// came from, so a program whose `helper.py` is ill formed says so.
pub fn check_program(tree : @program.SourceTree) -> @err.Diagnostic? {
  let program = Program::new(tree.modules_map())
  try check_module(program, "__main__") |> ignore catch {
    @err.PurePyError(d) =>
      match d.kind {
        // A module-level rejection carries the path of the module that
        // raised it, and loses its position: `check_program.py` prints the
        // message alone. A program-level one is already a whole sentence.
        IllFormed(_) => {
          let q = match d.in_module {
            Some(q) => q
            None => "__main__"
          }
          Some(d.at_path(tree.path_of(q)))
        }
        _ => Some(d)
      }
    e => Some(@err.Diagnostic::new(Program(msg="\{e}")))
  } noraise {
    _ => None
  }
}

///|
/// Discover a program from its entry file and check it.
pub fn check_entry(entry_path : String) -> @err.Diagnostic? {
  let tree = @program.SourceTree::from_entry(
    entry_path,
    predefined=@context.predefined_modules,
  ) catch {
    @err.PurePyError(d) => return Some(d)
    e => return Some(@err.Diagnostic::new(Program(msg="\{e}")))
  }
  check_program(tree)
}
