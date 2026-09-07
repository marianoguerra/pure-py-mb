///|
/// Module and program evaluation: Figures 4.11 to 4.13.
///
/// Loading mirrors the static rules: the import prefix first, then the body,
/// under `builtins`. An import loads the ancestors of its target from the
/// root down, each before its descendant.
///
/// The one departure is the cache, and it is about OUTPUT rather than values.
/// The spec says loading is deterministic and needs no cache, which is true
/// of what a module loads TO; it is not true of what loading PRINTS. Two
/// imports of a module that prints would print twice, and CPython prints
/// once. The suite has a test for it.
pub async fn Interp::load(
  self : Interp,
  q : String,
) -> Result[Env, Outcome] noraise {
  match self.loaded.get(q) {
    Some(env) => return Ok(env)
    None => ()
  }
  // eval-predefined, and the host's own modules on the same footing: named,
  // loaded once, and with no source behind them.
  match self.predefined(q) {
    Some(env) => {
      self.loaded[q] = env
      return Ok(env)
    }
    None => ()
  }
  match self.host.modules.get(q) {
    Some(env) => {
      self.loaded[q] = env
      return Ok(env)
    }
    None => ()
  }
  if self.loading.contains(q) {
    return Err(Stuck("an import cycle reaching '" + q + "'"))
  }
  let m = match self.tree.get(q) {
    Some(m) => m
    None => return Err(Stuck("the module '" + q + "' is not in this program"))
  }
  self.loading.push(q)
  let result = self.load_body(m, q)
  let _ = self.loading.pop()
  match result {
    Ok(env) => {
      self.loaded[q] = env
      Ok(env)
    }
    err => err
  }
}

///|
/// eval-module: the import prefix, then the body under `builtins`, and the
/// module's submodules as stubs beneath what the body assigned.
async fn Interp::load_body(
  self : Interp,
  m : @ast.Module,
  q : String,
) -> Result[Env, Outcome] noraise {
  let (prefix, rest) = @analysis.split_imports(m.body)
  let imported = match self.eval_imports(prefix, q) {
    Ok(env) => env
    Err(o) => return Err(o)
  }
  let builtins = match self.predefined("builtins") {
    Some(env) => env
    None => @value.empty_env()
  }
  // `__name__` is set BEFORE the imports run, not after: CPython puts it in
  // the module's dictionary before executing the body, so
  // `from lib import __name__` rebinds it and `print(__name__)` says `lib`.
  // The static rules prepend `__name__ = q` to the body instead, which cannot
  // tell the difference because it tracks statuses and not values.
  let named = @value.env_of([("__name__", Value::Str(q))])
  let base = @value.override_env(@value.override_env(builtins, named), imported)
  match self.eval_body(rest, base) {
    Assigns(delta) =>
      // What the module exports: its submodules as stubs, then its own name,
      // then what the body assigned. Imported names are NOT exported.
      Ok(
        @value.override_env(self.submods(q), @value.override_env(named, delta)),
      )
    Returns(_) => Err(Stuck("a module body that returns"))
    ResultAborts(k) => Err(Aborts(k))
    ResultStuck(op) => Err(Stuck(op))
  }
}

///|
/// The modules of the program that are children of `q`, as stubs.
fn Interp::submods(self : Interp, q : String) -> Env {
  let entries : Array[(String, Value)] = []
  let seen : Array[String] = []
  for name in self.tree.module_names() {
    if name.has_prefix(q + ".") {
      let rest = name[q.length() + 1:].to_owned()
      let child = match rest.split_once(".") {
        Some((head, _)) => head.to_owned()
        None => rest
      }
      if !seen.contains(child) {
        seen.push(child)
        entries.push((child, Value::ModStub(q + "." + child)))
      }
    }
  }
  @value.env_of(entries)
}

///|
/// The import prefix of a module (Figure 4.12a).
async fn Interp::eval_imports(
  self : Interp,
  prefix : Array[@ast.Stmt],
  q : String,
) -> Result[Env, Outcome] noraise {
  // Each import's bindings are collected in SOURCE order -- loading prints,
  // and the order it prints in is observable -- and folded from the RIGHT.
  // `eval-import` reads `{x: v} ⊲ ρ'` with `ρ'` the result of the imports
  // AFTER it, so a later import of the same name wins over an earlier one.
  let bindings : Array[Env] = []
  for s in prefix {
    match s {
      // eval-import: `import a.b.c` binds `a`, to a module whose `b` is a
      // module whose `c` is the one imported.
      Import(names~, ..) => {
        let target = names[0].name
        // Ancestors first, from the root down. The rules do not order the
        // premises of `eval-import`, and `loads-as` recurses from the deepest
        // parent upward, but loading PRINTS and CPython loads a package
        // before its submodule.
        for p in @program.proper_prefixes(target) {
          match self.load(p) {
            Ok(_) => ()
            Err(o) => return Err(o)
          }
        }
        let loaded = match self.load(target) {
          Ok(env) => env
          Err(o) => return Err(o)
        }
        let bound = match self.loads_as(target, Value::Mod(target, loaded)) {
          Ok(v) => v
          Err(o) => return Err(o)
        }
        let root = match target.split_once(".") {
          Some((head, _)) => head.to_owned()
          None => target
        }
        bindings.push(@value.env_of([(root, bound)]))
      }
      // eval-from-import
      ImportFrom(module_name~, names~, ..) => {
        let source = match module_name {
          Some(x) => x
          None => return Err(Stuck("a from-import with no module"))
        }
        // The ancestors of the target are loaded first, unless they are
        // ancestors of the importing module -- which is loading already.
        for p in @program.proper_prefixes(source) {
          if !prefix_of(p, q) {
            match self.load(p) {
              Ok(_) => ()
              Err(o) => return Err(o)
            }
          }
        }
        let loaded = match self.load(source) {
          Ok(env) => env
          Err(o) => return Err(o)
        }
        let entries : Array[(String, Value)] = []
        for a in names {
          match self.import_name(loaded, a.name) {
            Ok(v) => entries.push((a.name, v))
            Err(o) => return Err(o)
          }
        }
        bindings.push(@value.env_of(entries))
      }
      _ => return Err(Stuck("a statement in the import prefix"))
    }
  }
  let mut out = @value.empty_env()
  for i = bindings.length() - 1; i >= 0; i = i - 1 {
    out = @value.extend_env(bindings[i], out)
  }
  Ok(out)
}

///|
fn prefix_of(p : String, q : String) -> Bool {
  p == q || q.has_prefix(p + ".")
}

///|
/// `ρ, x imports o` (Figure 4.11): a member of a loaded module, with a
/// submodule stub loaded on the way out.
async fn Interp::import_name(
  self : Interp,
  members : Env,
  x : String,
) -> Result[Value, Outcome] noraise {
  match members.get(x) {
    None => Err(Stuck("no member '" + x + "' to import"))
    Some(ModStub(sub)) =>
      match self.load(sub) {
        Ok(env) => Ok(Mod(sub, env))
        Err(o) => Err(o)
      }
    Some(v) => Ok(v)
  }
}

///|
/// `q, v loads-as v'` (Figure 4.12b): the reference for the ROOT of a dotted
/// module name, loading each ancestor on the way.
async fn Interp::loads_as(
  self : Interp,
  q : String,
  v : Value,
) -> Result[Value, Outcome] noraise {
  match q.rev_split_once(".") {
    None => Ok(v)
    Some((parent, x)) => {
      let parent_name = parent.to_owned()
      let parent_env = match self.load(parent_name) {
        Ok(env) => env
        Err(o) => return Err(o)
      }
      self.loads_as(
        parent_name,
        Mod(
          parent_name,
          @value.extend_env(parent_env, @value.env_of([(x.to_owned(), v)])),
        ),
      )
    }
  }
}

// ---------------------------------------------------------------------------

///|
/// How a run ended, or that it has not ended yet.
pub(all) enum RunResult {
  /// The main module loaded: `SystemExit(0)`.
  Finished
  /// The run aborted with a termination kind.
  Terminated(Termination)
  /// The run reached an operation the semantics leaves undefined.
  Undefined(String)
  /// The run is parked in a host call that has not answered yet, and the
  /// synchronous driver had nothing to return.
  ///
  /// This is not an end: the run resumes when the host calls the
  /// continuation it was handed, and `run_with`'s `done` is called with the
  /// real answer then. A host whose `call` always answers immediately never
  /// sees this.
  Suspended
} derive(Debug)

///|
/// `⇒ κ` (Figure 4.13): evaluate a program by loading its main module.
pub async fn Interp::run(self : Interp) -> RunResult noraise {
  match self.load("__main__") {
    Ok(_) => Finished
    Err(Aborts(k)) => Terminated(k)
    Err(Stuck(op)) => Undefined(op)
    Err(Val(_)) => Finished
  }
}

///|
/// Evaluate a program and answer with its transcript and how it ended.
///
/// The simple path: output is collected and handed back. A caller that wants
/// output as it happens, its own modules, or its own functions supplies a
/// `Host` and uses `run_with`.
///
/// The host this builds answers no foreign call, so this run cannot suspend
/// and the result is never `Suspended`. The transcript is complete.
pub fn run_program(
  tree : @program.SourceTree,
  argv? : Array[String] = [],
  max_depth? : Int = default_max_depth,
) -> (String, RunResult) {
  let sink = Sink::new()
  let host = Host::new(write=fn(text) { sink.write(text) }, argv~)
  let result = run_with(tree, host, max_depth~)
  (sink.text(), result)
}

///|
/// Evaluate a program against a host, from a synchronous caller.
///
/// Output goes wherever the host sends it, so nothing is returned but how the
/// run ended.
///
/// A host call may suspend -- park the run and answer later -- and a
/// synchronous caller cannot wait for it. So this returns when the run ends
/// OR when it suspends, whichever comes first, and there are two ways to
/// learn the answer:
///
///   * The return value is the answer when the run ended here, and
///     `Suspended` when it did not.
///   * `done` is called exactly once with the answer whenever the run really
///     ends: before this returns when nothing suspended, and from inside the
///     host's own continuation when something did.
///
/// A host that always answers immediately can ignore `done` and read the
/// return value, which is what every caller before suspension existed did.
/// A host that suspends should pass `done`, because the value returned here
/// is not the answer.
///
/// An embedder that is itself asynchronous does not need any of this:
/// `Interp::run` is an `async` function and can simply be awaited.
pub fn run_with(
  tree : @program.SourceTree,
  host : Host,
  max_depth? : Int = default_max_depth,
  done? : (RunResult) -> Unit = fn(_) {  },
) -> RunResult {
  let interp = Interp::new(tree, host~, max_depth~)
  let mut answer : RunResult = Suspended
  run_async(() => {
    let r = interp.run()
    answer = r
    done(r)
  })
  answer
}

///|
/// Start an asynchronous computation from a synchronous caller.
///
/// The compiler's own driver: it runs the work until it finishes or until it
/// suspends, and returns either way. A suspended computation resumes when
/// whoever took its continuation calls it, on whatever stack that happens to
/// be -- so the work may still be running after this has returned.
fn run_async(work : async () -> Unit noraise) -> Unit = "%async.run"
