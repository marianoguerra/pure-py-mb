///|
/// A host function that answers later: `Host::call` is `async`, so a host may
/// park a run and resume it when its own work is done.
///
/// The three things worth pinning down are that a run parks where it stood
/// and not at a statement boundary, that the value the host supplies is the
/// value the guest sees, and that a synchronous embedder is told which of the
/// two things happened -- `Suspended` and a `done` that fires later, or the
/// answer and a `done` that fired already.
async fn[T] park(register : ((T) -> Unit) -> Unit) -> T noraise = "%async.suspend"

///|
/// A host that never answers on the spot: every call parks, and the
/// continuation goes on the queue for the test to run.
fn parking_host(
  queue : Array[(@value.Value) -> Unit],
  out : StringBuilder,
) -> Host {
  Host::new(
    write=text => out.write_string(text),
    modules=[{ name: "io", members: [("ask", @value.host_fn("io.ask"))], }],
    call=(_name, _args) => Val(park(k => queue.push(k))),
  )
}

///|
fn tree_of(source : String) -> @program.SourceTree {
  let parsed : Map[String, @ast.Module] = Map([])
  parsed["__main__"] = @parser.parse_string(source, name="__main__") catch {
    _ => abort("the test's own source does not parse")
  }
  @program.SourceTree::of(parsed)
}

///|
test "a host call parks the run and resumes it with a value" {
  let queue : Array[(@value.Value) -> Unit] = []
  let out = StringBuilder()
  // Both calls are operands of one expression, so the second parks with the
  // first one's value already in hand and half an addition still to do.
  let tree = tree_of("from io import ask\nprint(ask() + ask())\n")
  let mut ended : RunResult? = None
  let returned = run_with(tree, parking_host(queue, out), done=r => {
    ended = Some(r)
  })
  // The run has not ended, and the driver says so rather than guessing.
  inspect(returned is Suspended, content="true")
  inspect(ended is None, content="true")
  inspect(queue.length(), content="1")
  // The host does its work and answers. That resumes into the second call,
  // which parks in turn.
  let first = queue.pop().unwrap()
  first(Int(2N))
  inspect(ended is None, content="true")
  inspect(out.to_string(), content="")
  inspect(queue.length(), content="1")
  // The second answer completes the addition, the print and the run.
  let second = queue.pop().unwrap()
  second(Int(40N))
  inspect(out.to_string(), content="42\n")
  inspect(ended is Some(Finished), content="true")
}

///|
test "a parked run that is never resumed stays parked" {
  let queue : Array[(@value.Value) -> Unit] = []
  let out = StringBuilder()
  let tree = tree_of("from io import ask\nprint(ask())\n")
  let mut ended : RunResult? = None
  let returned = run_with(tree, parking_host(queue, out), done=r => {
    ended = Some(r)
  })
  inspect(returned is Suspended, content="true")
  inspect(ended is None, content="true")
  inspect(out.to_string(), content="")
  // Dropping the continuation drops the run. Nothing else happens: there is
  // no timeout, no cleanup and no second answer.
  queue.clear()
  inspect(ended is None, content="true")
}

///|
test "a host that answers on the spot is unchanged by any of this" {
  let out = StringBuilder()
  let host = Host::new(
    write=text => out.write_string(text),
    modules=[{ name: "io", members: [("ask", @value.host_fn("io.ask"))], }],
    call=(_name, _args) => Val(Int(7N)),
  )
  let tree = tree_of("from io import ask\nprint(ask() * ask())\n")
  let mut ended : RunResult? = None
  let returned = run_with(tree, host, done=r => ended = Some(r))
  // The answer is the return value, `done` has already fired, and the guest
  // cannot tell that a call was allowed to park.
  inspect(returned is Finished, content="true")
  inspect(ended is Some(Finished), content="true")
  inspect(out.to_string(), content="49\n")
}
