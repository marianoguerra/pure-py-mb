///|
/// The checker's table of predefined names and the evaluator's environment are
/// the same table, under every profile there is.
///
/// They cannot BE one. `@context.predefined_members` answers with names and
/// lives where the checker can reach it; `Interp::predefined` answers with
/// `Value`s and needs `lib/value`, which imports `lib/context`. A shared table
/// holding values could only live at or above `lib/value`, and `lib/check`
/// does not import `lib/value` at all -- deliberately, since what a builtin IS
/// is the evaluator's business.
///
/// So this is what keeps them from drifting. Add a builtin to one side and
/// forget the other, and a `from builtins import sorted` type-checks and then
/// is not there -- or is there and cannot be named. Neither is a failure any
/// existing test would catch, because both halves look right on their own.
test "the checker's names and the evaluator's values are one table" {
  let tree = @program.SourceTree::of(Map([]))
  for profile in [@profile.core, @profile.pending(), @profile.builtins()] {
    let interp = Interp::new(tree, profile~)
    for q in @context.predefined_modules {
      let want = match @context.predefined_members(q, profile~) {
        Some(ms) => ms
        None => {
          fail("no members for the predefined module '" + q + "'")
          []
        }
      }
      let env = match interp.predefined(q) {
        Some(env) => env
        None => {
          fail("no environment for the predefined module '" + q + "'")
          @value.empty_env()
        }
      }
      let got : Array[String] = []
      env.each(fn(k, _) { if k != "__name__" { got.push(k) } })
      @basic.sort_names(got)
      let sorted_want = want.copy()
      @basic.sort_names(sorted_want)
      assert_eq(got, sorted_want, msg=q)
    }
  }
}

///|
/// A profile only ever ADDS a name, and never takes one away or moves one.
///
/// The order matters and is not cosmetic: `check_submodule_clash` walks a
/// module's own members and reports the first clash it reaches, so a profile
/// that reordered `builtins` would reorder a diagnostic the reference decides.
test "a profile leaves the core names where they were" {
  let core_names = @context.predefined_members("builtins").unwrap()
  assert_eq(core_names, ["print", "len", "range"])
  let with_extras = @context.predefined_members(
    "builtins",
    profile=@profile.builtins(),
  ).unwrap()
  assert_eq(with_extras[:core_names.length()].to_owned(), core_names)
  assert_eq(
    with_extras[core_names.length():].to_owned(),
    @context.extra_builtin_names,
  )
}
