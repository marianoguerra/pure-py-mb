///|
/// What the host supplies: everything about a PurePy run that is not pure.
///
/// PurePy is a pure language, but a RUN is not a pure thing: it prints, it
/// reads its arguments, it loads modules, and -- when it is embedded -- it
/// calls out to whatever the application wants to expose. Those four are the
/// whole of it, and they are all here, so an embedder can see the surface at
/// once instead of discovering it a call at a time.
///
///   * **Output.** `write` receives what `print` produced, one call per
///     `print`, while the run is still going. A host that streams to a
///     terminal writes it out; a host that wants a transcript accumulates.
///   * **Arguments.** `argv` is what `sys.argv` reads. `argv[0]` is the
///     program's own name, as in Python.
///   * **Modules.** `modules` are importable modules the host defines, beyond
///     the five the specification predefines. Their members are values, and a
///     member may be a function the host implements.
///   * **Foreign calls.** `call` answers a call to one of those functions. It
///     is given the name the host registered and the arguments the guest
///     passed, and returns an `Outcome`: a value, an abort, or -- for
///     anything it does not recognise or cannot do -- an operation the
///     semantics does not cover.
///
///     It is `async`, so it may also answer LATER: a host that has to read a
///     socket, await a promise or ask a person suspends, and the whole run
///     parks where it stood -- mid-expression, inside a call, anywhere -- and
///     resumes on the value the host eventually supplies. Nothing about the
///     guest changes: PurePy has no `await`, and a program cannot tell a call
///     that answered late from one that answered at once. See `run_with` for
///     how a synchronous embedder drives a run that can park.
///
/// Everything else about a run is already a value: the program is a
/// `SourceTree`, so a host that keeps its guest code in a database, a zip file
/// or a string never touches the filesystem.
///
/// Note what is NOT here. There is no way for the host to mutate a guest
/// value, because there is no mutation; no way to install a callback the guest
/// invokes implicitly, because there are no hooks; and no ambient authority at
/// all -- a guest can reach exactly the modules the host handed it. A host
/// that gives no modules gives a program that can only compute and print.
///
/// Suspension adds nothing to that list. A parked run is not a concurrent
/// one: there is one guest, it is at exactly one point, and the host holds
/// the only continuation. Resuming it twice is the host resuming it twice,
/// which is the host's bug and not an escape from the semantics.
pub struct Host {
  write : (String) -> Unit
  argv : Array[String]
  modules : Map[String, @value.Env]
  call : async (String, Array[@value.Value]) -> @value.Outcome noraise
}

///|
/// A module the host defines: a name the guest can import, and its members.
///
/// A member is any `Value`. `@value.host_fn("name")` makes one the guest can
/// call and the host answers by name.
pub(all) struct HostModule {
  name : String
  members : Array[(String, @value.Value)]
}

///|
/// A host.
///
/// Every part has a default that does nothing observable: output is dropped,
/// `sys.argv` is empty, no modules are defined, and a foreign call is an
/// operation the semantics does not cover. A host supplies the parts it wants.
///
/// A `call` that answers on the spot is written exactly as it was before it
/// could do otherwise: a plain function is a valid `async` one.
pub fn Host::new(
  write? : (String) -> Unit = fn(_) {  },
  argv? : Array[String] = [],
  modules? : Array[HostModule] = [],
  call? : async (String, Array[@value.Value]) -> @value.Outcome noraise = fn(
    name,
    _,
  ) {
    Stuck(
      "a call to the host function '" + name + "', which it does not answer",
    )
  },
) -> Host {
  let table : Map[String, @value.Env] = Map([])
  for m in modules {
    // Every module has a `__name__`, as the predefined ones do.
    let entries : Array[(String, @value.Value)] = [("__name__", Str(m.name))]
    for e in m.members {
      entries.push(e)
    }
    table[m.name] = @value.env_of(entries)
  }
  { write, argv, modules: table, call, }
}

///|
/// The names of each host module's members.
///
/// The CHECKER needs these and not the values: a `from hostmod import f` has
/// to type-check before it can run, and the checker has no business knowing
/// what `f` is. This is the one place the two sides of a host module meet.
pub fn Host::member_names(self : Host) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = Map([])
  for name, env in self.modules {
    let members : Array[String] = []
    env.each(fn(k, _) { if k != "__name__" { members.push(k) } })
    @basic.sort_names(members)
    out[name] = members
  }
  out
}

///|
/// The modules a program may import that have no source: the five the
/// specification predefines, and the host's own.
pub fn Host::module_names(self : Host) -> Array[String] {
  let out : Array[String] = []
  for p in @context.predefined_modules {
    out.push(p)
  }
  for name, _ in self.modules {
    if !out.contains(name) {
      out.push(name)
    }
  }
  @basic.sort_names(out)
  out
}

// ---------------------------------------------------------------------------

///|
/// Somewhere to put output when the caller just wants the transcript.
///
/// `run_program` uses one of these; `run_with` does not, because a host that
/// supplies its own `write` has somewhere better to put it.
pub struct Sink {
  buf : StringBuilder
}

///|
pub fn Sink::new() -> Sink {
  { buf: StringBuilder(), }
}

///|
pub fn Sink::write(self : Sink, text : String) -> Unit {
  self.buf.write_string(text)
}

///|
pub fn Sink::text(self : Sink) -> String {
  self.buf.to_string()
}
