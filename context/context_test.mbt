///|
/// The algebra of Figure 2.2 and Definition 3.1, and the class table.
fn vars(entries : Array[(String, @context.Status)]) -> @context.VarContext {
  @context.vars_of(entries)
}

///|
fn text(d : @context.VarContext) -> String {
  let parts : Array[String] = []
  d.each(fn(k, v) { parts.push("\{k}=" + (if v is TT { "tt" } else { "ff" })) })
  "{" + parts.join(", ") + "}"
}

///|
test "merging two branches: tt only where both say tt" {
  let a = vars([("x", TT), ("y", TT)])
  let b = vars([("x", TT), ("y", FF), ("z", TT)])
  assert_eq(text(@context.merge_delta(a, b)), "{x=tt, y=ff, z=ff}")
  // A name assigned on one side only is present and not definitely assigned.
  assert_eq(text(@context.merge_delta(vars([("x", TT)]), vars([]))), "{x=ff}")
  assert_eq(text(@context.merge_delta(vars([]), vars([]))), "{}")
}

///|
test "a branch that returns contributes nothing to the merge" {
  let assigns = @context.ResultType::Assigns(vars([("x", TT)]))
  assert_eq(@context.merge_results([Returns, Returns]), Returns)
  assert_eq(@context.merge_results([assigns, Returns]), assigns)
  // Two branches, one of which returns: the other's delta stands as it is.
  assert_eq(@context.merge_results([Returns, assigns]), assigns)
  // Both assign, one only sometimes.
  match @context.merge_results([assigns, @context.assigns_empty()]) {
    Assigns(d) => assert_eq(text(d), "{x=ff}")
    Returns => fail("expected an assignment")
  }
}

///|
test "sequencing: once anything returns, the sequence returns" {
  let a = @context.ResultType::Assigns(vars([("x", TT)]))
  let b = @context.ResultType::Assigns(vars([("x", FF), ("y", TT)]))
  assert_eq(@context.override_results(Returns, a), Returns)
  assert_eq(@context.override_results(a, Returns), Returns)
  match @context.override_results(a, b) {
    // The later binding wins outright: this is override, not merge.
    Assigns(d) => assert_eq(text(d), "{x=ff, y=tt}")
    Returns => fail("expected an assignment")
  }
  // The empty delta is the unit.
  assert_eq(@context.override_results(a, @context.assigns_empty()), a)
  assert_eq(@context.override_results(@context.assigns_empty(), a), a)
}

///|
test "extending prefers a loaded module to a stub of the same module" {
  let members = @context.context_of([("x", Var(TT))])
  let loaded = @context.Entry::ModuleLoaded("m", members)
  let stub = @context.Entry::ModuleStub("m")
  assert_eq(@context.extend_entry(loaded, stub), loaded)
  // The other way round the stub is simply replaced.
  assert_eq(@context.extend_entry(stub, loaded), loaded)
  // A stub of a DIFFERENT module replaces, it does not merge.
  assert_eq(@context.extend_entry(loaded, ModuleStub("n")), ModuleStub("n"))
}

///|
test "two loadings of one module merge member by member" {
  let a = @context.Entry::ModuleLoaded(
    "m",
    @context.context_of([("x", Var(TT))]),
  )
  let b = @context.Entry::ModuleLoaded(
    "m",
    @context.context_of([("y", Var(TT))]),
  )
  match @context.extend_entry(a, b) {
    ModuleLoaded(q, members) => {
      assert_eq(q, "m")
      assert_eq(members.keys_as_iter().to_array(), ["x", "y"])
    }
    _ => fail("expected a loaded module")
  }
}

///|
/// A base class is resolved through the context the SUBCLASS was declared in,
/// so the two entries below are enough to answer `fields` and `ancestors`.
fn class_pair() -> (@context.ClassEntry, @context.ClassEntry) {
  let base : @context.ClassEntry = {
    context: @context.empty_context(),
    name: "Point",
    own_fields: ["x", "y"],
    base: None,
  }
  let derived : @context.ClassEntry = {
    context: @context.context_of([("Point", Class(base))]),
    name: "Point3",
    own_fields: ["z"],
    base: Some("Point"),
  }
  (base, derived)
}

///|
test "fields are inherited first, in declaration order" {
  let (base, derived) = class_pair()
  assert_eq(base.fields(), ["x", "y"])
  assert_eq(derived.fields(), ["x", "y", "z"])
  assert_eq(derived.ancestors().map(fn(c) { c.name }), ["Point3", "Point"])
  assert_eq(base.short_name(), "Point")
}

///|
test "a qualified class name prints by its last segment" {
  let entry : @context.ClassEntry = {
    context: @context.empty_context(),
    name: "pkg.mod.Point",
    own_fields: [],
    base: None,
  }
  assert_eq(entry.short_name(), "Point")
}

///|
fn map_text(m : Array[(String, Int)]?) -> String {
  match m {
    None => "-"
    Some(entries) =>
      "{" + entries.map(fn(e) { "\{e.0}=\{e.1}" }).join(", ") + "}"
  }
}

///|
test "matching arguments to fields" {
  let (_, derived) = class_pair()
  // All positional.
  assert_eq(map_text(derived.field_map([1, 2, 3], [], [])), "{x=1, y=2, z=3}")
  // Positional then keyword, in the order the keywords were written.
  assert_eq(
    map_text(derived.field_map([1], ["z", "y"], [3, 2])),
    "{x=1, z=3, y=2}",
  )
  // All keyword.
  assert_eq(
    map_text(derived.field_map([], ["z", "y", "x"], [3, 2, 1])),
    "{z=3, y=2, x=1}",
  )
  // Under-saturated, over-saturated, a repeated keyword, and a keyword that
  // is not a remaining field.
  assert_eq(map_text(derived.field_map([1, 2], [], [])), "-")
  assert_eq(map_text(derived.field_map([1, 2, 3, 4], [], [])), "-")
  assert_eq(map_text(derived.field_map([1], ["y", "y"], [2, 3])), "-")
  assert_eq(map_text(derived.field_map([1, 2], ["w"], [3])), "-")
  // A keyword naming a field the positional arguments already covered.
  assert_eq(map_text(derived.field_map([1, 2], ["x"], [3])), "-")
}

///|
test "the predefined modules and their members" {
  assert_eq(@context.predefined_modules, [
    "builtins", "dataclasses", "math", "sys", "typing",
  ])
  assert_eq(@context.predefined_members("sys"), Some(["argv", "exit"]))
  assert_eq(@context.predefined_members("os"), None)
  // Every member is definitely assigned, and so is `__name__`.
  assert_eq(@context.predefined_context("typing").keys_as_iter().to_array(), [
    "Any", "__name__",
  ])
}
