///|
/// Paths, as `pathlib` prints them -- which is what the reference's messages
/// contain.
test "pathlib's parent and join" {
  assert_eq(@program.parent("main.py"), ".")
  assert_eq(@program.parent("a/b/main.py"), "a/b")
  assert_eq(@program.parent("/main.py"), "/")
  assert_eq(@program.join(".", "helper.py"), "helper.py")
  assert_eq(@program.join("a/b", "c.py"), "a/b/c.py")
  assert_eq(@program.join("a/", "c.py"), "a/c.py")
  assert_eq(@program.stem("a/b/main.py"), "main")
  assert_eq(@program.stem("main"), "main")
  assert_eq(@program.name_of("a/b/main.py"), "main.py")
}

///|
test "a name and all of its proper prefixes" {
  assert_eq(@program.proper_prefixes("a.b.c"), ["a", "a.b"])
  assert_eq(@program.proper_prefixes("a"), [])
  assert_eq(@program.with_proper_prefixes(["x.y.a", "x.z"]), [
    "x", "x.y", "x.y.a", "x.z",
  ])
}

///|
test "a source tree can be built in memory" {
  let modules : Map[String, @ast.Module] = Map([])
  modules["__main__"] = { body: [], span: @basic.nowhere, }
  modules["lib"] = { body: [], span: @basic.nowhere, }
  let tree = @program.SourceTree::of(modules)
  assert_eq(tree.module_names().length(), 2)
  assert_true(tree.get("lib") is Some(_))
  assert_true(tree.get("nowhere") is None)
  assert_eq(tree.path_of("lib"), "lib")
}
