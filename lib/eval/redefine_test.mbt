///|
/// A host that redefines `builtins.print`: what a run prints, as VALUES.
///
/// `write` is handed text -- `str` of each argument, joined, terminated --
/// which is the right shape for a terminal and the wrong one for anything that
/// wanted the arguments. A redefinition is handed the arguments.
fn capturing(
  captured : Array[Array[@value.Value]],
  wrote : Array[String],
  name? : String = "builtins.print",
) -> @eval.Host {
  @eval.Host::new(
    write=text => wrote.push(text),
    call=(_, args) => {
      captured.push(args)
      Val(None)
    },
    redefined=[(name, @value.host_fn("cap.print"))],
  )
}

///|
/// `tree_of`, for a program of several modules. The single-module one lives in
/// `suspend_test.mbt`, which got there first.
fn tree_of_modules(modules : Array[(String, String)]) -> @program.SourceTree {
  let parsed : Map[String, @ast.Module] = Map([])
  for m in modules {
    parsed[m.0] = @parser.parse_string(m.1, name=m.0) catch {
      _ => abort("the test's own source does not parse")
    }
  }
  @program.SourceTree::of(parsed)
}

///|
test "a redefined print is handed the values, and write is never called" {
  let captured : Array[Array[@value.Value]] = []
  let wrote : Array[String] = []
  let result = @eval.run_with(
    tree_of("print(1, \"a\", [2, 3])\nprint()\n"),
    capturing(captured, wrote),
  )
  assert_true(result is Finished)
  // Two calls, with the arguments the guest wrote and nothing added.
  assert_eq(captured.length(), 2)
  debug_inspect(
    captured[0],
    content=(
      #|[Int(1), Str("a"), List([Int(2), Int(3)])]
    ),
  )
  assert_eq(captured[1].length(), 0)
  // Output is the host's business now, and this host produced none.
  assert_eq(wrote.length(), 0)
}

///|
/// The property the shadowing workaround cannot claim: there is ONE print.
///
/// A `from cap import print` prepended to the body shadows the binding and
/// nothing else, so `from builtins import print` and `builtins.print` both
/// reach around it to the real one. A redefinition is the binding.
test "every way of naming print reaches the redefinition" {
  for
    source in [
      "print(1)\n", "from builtins import print\nprint(1)\n", "import builtins\nbuiltins.print(1)\n",
    ] {
    let captured : Array[Array[@value.Value]] = []
    let wrote : Array[String] = []
    let result = @eval.run_with(tree_of(source), capturing(captured, wrote))
    assert_true(result is Finished, msg=source)
    assert_eq(captured.length(), 1, msg=source)
    assert_eq(wrote.length(), 0, msg=source)
  }
}

///|
/// A redefinition reaches a module that never mentions it, because `builtins`
/// is under every module's body and not only the main one's.
test "a redefinition reaches every module" {
  let captured : Array[Array[@value.Value]] = []
  let wrote : Array[String] = []
  let tree = tree_of_modules([
    ("helper", "def shout(x):\n    print(x)\n    return x\n"),
    ("__main__", "from helper import shout\nshout(7)\n"),
  ])
  assert_true(@eval.run_with(tree, capturing(captured, wrote)) is Finished)
  assert_eq(captured.length(), 1)
  debug_inspect(captured[0], content="[Int(7)]")
}

///|
/// A redefinition answers with an `Outcome`, so it may refuse -- and the abort
/// is sited at the guest's call, exactly as a host function's is.
test "a redefined print may abort, and the site is the guest's call" {
  let host = @eval.Host::new(call=(_, _) => Aborts(TypeError), redefined=[
    ("builtins.print", @value.host_fn("cap.print")),
  ])
  match @eval.run_with(tree_of("x = 1\nprint(x)\n"), host) {
    Terminated(k, Some(site)) => {
      assert_eq(k.to_text(), "TypeError")
      assert_eq(site.to_display(), "__main__:2:0")
    }
    _ => fail("a refusing print terminates")
  }
}

///|
/// Not only `builtins`. `sys.exit` is the second thing an embedder wants, and
/// it is the same field.
test "sys.exit redefined" {
  let seen : Array[Array[@value.Value]] = []
  let host = @eval.Host::new(
    call=(_, args) => {
      seen.push(args)
      Aborts(SystemExit(0N))
    },
    redefined=[("sys.exit", @value.host_fn("cap.exit"))],
  )
  let result = @eval.run_with(tree_of("import sys\nsys.exit(3)\n"), host)
  // The host logged the code it was given and then ended the run its own way.
  debug_inspect(seen, content="[[Int(3)]]")
  assert_true(result is Terminated(SystemExit(_), _))
}

///|
/// A redefinition replaces; it does not shadow a value that is still reachable
/// underneath. `math.pi` is a constant, and a constant is a member too.
test "a redefined constant" {
  let sink = @eval.Sink::new()
  let host = @eval.Host::new(write=t => sink.write(t), redefined=[
    ("math.pi", @value.Value::Int(3N)),
  ])
  assert_true(
    @eval.run_with(tree_of("import math\nprint(math.pi, math.e)\n"), host)
    is Finished,
  )
  // `pi` is the host's; `e` is untouched.
  assert_eq(sink.text(), "3 2.718281828459045\n")
}

///|
/// An empty `redefined` is PurePy, which is what keeps the conformance suite
/// and the goldens out of this feature's way.
test "a host that redefines nothing prints as the specification says" {
  let sink = @eval.Sink::new()
  let plain = @eval.Host::new(write=t => sink.write(t))
  assert_true(
    @eval.run_with(tree_of("print(1, \"a\", [2, 3])\n"), plain) is Finished,
  )
  assert_eq(sink.text(), "1 a [2, 3]\n")
  assert_eq(plain.unknown_redefinitions(), [])
}

///|
/// `print_text` is what `print` would have written, so a host that redefines
/// it can still have the transcript without writing the join a second time.
test "print_text is the text print would have written" {
  let captured : Array[Array[@value.Value]] = []
  let wrote : Array[String] = []
  let source = "print(1, \"a\", [2, 3])\nprint()\nprint(None, 1.5)\n"
  assert_true(
    @eval.run_with(tree_of(source), capturing(captured, wrote)) is Finished,
  )
  let rendered = captured.map(args => @value.print_text(args).unwrap())
  // The same three lines a host that had not redefined anything would see.
  let sink = @eval.Sink::new()
  assert_true(
    @eval.run_with(tree_of(source), @eval.Host::new(write=t => sink.write(t)))
    is Finished,
  )
  assert_eq(rendered.join(""), sink.text())
  // A value with no printable form is the operation `print` leaves undefined.
  assert_eq(@value.print_text([@value.Value::Prim(Print)]), None)
}

///|
/// A key nobody has is a silence, and this is how a host breaks it.
test "unknown redefinitions" {
  let host = @eval.Host::new(redefined=[
    ("builtins.print", @value.host_fn("p")),
    // A typo, a name only a profile has, a module of the host's own, and a
    // key that is not a dotted name at all.
    ("builtins.pirnt", @value.host_fn("p")),
    ("builtins.sorted", @value.host_fn("p")),
    ("store.get", @value.host_fn("p")),
    ("print", @value.host_fn("p")),
  ])
  assert_eq(host.unknown_redefinitions(), [
    "builtins.pirnt", "builtins.sorted", "print", "store.get",
  ])
  // Under a profile that has `sorted`, it is a member like any other.
  assert_eq(host.unknown_redefinitions(profile=@profile.builtins()), [
    "builtins.pirnt", "print", "store.get",
  ])
  // And a key nobody has changes nothing about the run.
  let sink = @eval.Sink::new()
  let typo = @eval.Host::new(write=t => sink.write(t), redefined=[
    ("builtins.pirnt", @value.host_fn("p")),
  ])
  assert_true(@eval.run_with(tree_of("print(1)\n"), typo) is Finished)
  assert_eq(sink.text(), "1\n")
}
