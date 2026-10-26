///|
/// Finding a program's modules on disk.
///
/// A port of the reference's `check_program.py` discovery: what a module name
/// means as a path, which files are part of the program, and what each one
/// imports. The result is a value -- a `SourceTree` -- so that the checker and
/// the evaluator both take one and neither touches the filesystem. A test can
/// build one in memory.
///
/// Three rules that are not obvious:
///
///   * A directory with no `__init__.py` is a NAMESPACE PACKAGE, and its body
///     is empty. `pkg/sub.py` alone makes `pkg` a module.
///   * Every `.py` under the entry's directory is discovered, whether or not
///     anything imports it, and so is every proper prefix of its name. An
///     unused module is therefore parsed and sieved, though not checked.
///   * A module that fails to parse, or that the sieve rejects, is a
///     PROGRAM-level error carrying the file's path -- not a module-level one.
pub struct SourceTree {
  /// The directory the entry file is in, as `pathlib` would print it.
  base_dir : String
  /// Module name to parsed module, for every module loaded so far. The entry
  /// is `__main__`.
  modules : Map[String, @ast.Module]
  /// Module name to the path a message should print for it. A predefined
  /// module's path is `<name>`.
  paths : Map[String, String]
  /// Every module the program HAS, loaded or not. A checked program knows its
  /// modules by name from the start and parses each one only when something
  /// imports it, as the reference does since v0.16: an unused module that
  /// would not parse is no business of the program's.
  names : Array[String]
  /// How to load a module that is named but not loaded yet.
  loader : ((String) -> (@ast.Module, String) raise)?
}

///|
/// Build a source tree in memory, for a test or a library caller.
pub fn SourceTree::of(
  modules : Map[String, @ast.Module],
  base_dir~ : String = ".",
) -> SourceTree {
  let paths : Map[String, String] = Map([])
  for name in modules.keys() {
    paths[name] = name
  }
  { base_dir, modules, paths, names: modules.keys().collect(), loader: None, }
}

///|
pub fn SourceTree::module_names(self : SourceTree) -> Array[String] {
  self.names
}

///|
/// Whether the program has a module of this name, loaded or not.
pub fn SourceTree::contains(self : SourceTree, q : String) -> Bool {
  self.modules.contains(q) || self.names.contains(q)
}

///|
/// A module's tree, loading it first if it has not been. Loading is where a
/// file that will not parse, or that the sieve refuses, is found out.
pub fn SourceTree::load(self : SourceTree, q : String) -> @ast.Module raise {
  match self.modules.get(q) {
    Some(m) => m
    None =>
      match self.loader {
        Some(f) if self.names.contains(q) => {
          let (m, path) = f(q)
          self.modules[q] = m
          self.paths[q] = path
          m
        }
        _ => raise @err.ill_formed_program("module '\{q}' not found")
      }
  }
}

///|
pub fn SourceTree::get(self : SourceTree, q : String) -> @ast.Module? {
  self.modules.get(q)
}

///|
pub fn SourceTree::path_of(self : SourceTree, q : String) -> String {
  match self.paths.get(q) {
    Some(p) => p
    None => q
  }
}

///|
pub fn SourceTree::modules_map(self : SourceTree) -> Map[String, @ast.Module] {
  self.modules
}

// ---------------------------------------------------------------------------

///|
/// Where a module name lives, if it lives anywhere: `a/b.py`, then
/// `a/b/__init__.py`, then the directory `a/b` as a namespace package.
pub fn is_module(name : String, base_dir : String) -> String? {
  let stem = name.replace_all(old=".", new="/")
  let file = join(base_dir, stem + ".py")
  if @fs.path_exists(file) {
    return Some(file)
  }
  let init = join(base_dir, stem + "/__init__.py")
  if @fs.path_exists(init) {
    return Some(init)
  }
  let dir = join(base_dir, stem)
  let is_dir = @fs.is_dir(dir) catch { _ => false }
  if is_dir {
    Some(dir)
  } else {
    None
  }
}

///|
/// Read, parse and sieve one module. A failure at any of the three is a
/// program-level error naming the file.
fn load(
  name : String,
  base_dir : String,
  profile : @profile.Profile,
) -> @ast.Module raise {
  let path = match is_module(name, base_dir) {
    Some(p) => p
    None =>
      raise @err.ill_formed_program(
        "module " + @basic.py_repr(name) + " not found under " + base_dir,
      )
  }
  load_path(path, profile)
}

///|
/// Read, parse and sieve the module at a path.
fn load_path(path : String, profile : @profile.Profile) -> @ast.Module raise {
  let is_dir = @fs.is_dir(path) catch { _ => false }
  if is_dir {
    // A namespace package: named, with nothing in it.
    return { body: [], span: @basic.nowhere, }
  }
  let text = @fs.read_file_to_string(path) catch {
    _ => raise @err.ill_formed_program("\{path}: cannot be read")
  }
  let src = @basic.Source::new(text, name=path)
  let tree = @parser.parse(src) catch {
    // A syntax error keeps its exit code, 1, and is reported against the
    // file without its position, as the reference reports it since v0.18.
    @err.PurePyError(d) => raise d.as_parse_error().at_path(path).raise_()
    e => raise @err.ill_formed_program("\{path}: parse error: \{e}")
  }
  match @sieve.result(tree, profile~) {
    // The sieve's verdict keeps its exit code; the reference puts the path
    // in front of the message and drops the position.
    Some(d) => raise d.at_path(path).raise_()
    None => ()
  }
  tree
}

///|
/// Every module a tree imports, plus each `from a import b` where `a.b` is
/// itself a module.
fn import_targets(tree : @ast.Module, base_dir : String) -> Array[String] {
  let out : Array[String] = []
  let add = fn(q : String) { if !out.contains(q) { out.push(q) } }
  walk_imports(tree.body, fn(s) {
    match s {
      Import(names~, ..) =>
        for a in names {
          add(a.name)
        }
      ImportFrom(module_name~, names~, ..) =>
        match module_name {
          Some(m) => {
            add(m)
            for a in names {
              let child = m + "." + a.name
              if is_module(child, base_dir) is Some(_) {
                add(child)
              }
            }
          }
          None => ()
        }
      _ => ()
    }
  })
  out
}

///|
/// Every import statement anywhere in a body -- the reference uses `ast.walk`,
/// so a nested import counts for discovery even though the checker rejects it.
fn walk_imports(body : Array[@ast.Stmt], f : (@ast.Stmt) -> Unit) -> Unit {
  for s in body {
    if s is (Import(..) | ImportFrom(..)) {
      f(s)
    }
    match s {
      FunctionDef(body=inner, ..) | ClassDef(body=inner, ..) =>
        walk_imports(inner, f)
      If(body=a, or_else=b, ..)
      | While(body=a, or_else=b, ..)
      | For(body=a, or_else=b, ..) => {
        walk_imports(a, f)
        walk_imports(b, f)
      }
      With(body=inner, ..) => walk_imports(inner, f)
      Try(body=a, handlers~, or_else=b, finalbody~, ..) => {
        walk_imports(a, f)
        for h in handlers {
          walk_imports(h.body, f)
        }
        walk_imports(b, f)
        walk_imports(finalbody, f)
      }
      Match(cases~, ..) =>
        for c in cases {
          walk_imports(c.body, f)
        }
      _ => ()
    }
  }
}

///|
/// The module name a file has, relative to the base directory.
fn module_name(base_dir : String, path : String) -> String {
  let rel = if base_dir == "." {
    path
  } else if path.has_prefix(base_dir + "/") {
    path[base_dir.length() + 1:].to_owned()
  } else {
    path
  }
  if name_of(rel) == "__init__.py" {
    let dir = parent(rel)
    if dir == "." {
      ""
    } else {
      dir.replace_all(old="/", new=".")
    }
  } else {
    let without = if rel.has_suffix(".py") {
      rel[:rel.length() - 3].to_owned()
    } else {
      rel
    }
    without.replace_all(old="/", new=".")
  }
}

///|
/// Every `.py` file under a directory, `__pycache__` excluded.
fn walk_py_files(dir : String) -> Array[String] {
  let out : Array[String] = []
  // `read_dir` answers with a view; the sort below is in place, and a
  // directory's order is the platform's, not one we may rely on.
  let entries = @fs.read_dir(dir).to_owned() catch { _ => return out }
  @basic.sort_names(entries)
  for e in entries {
    if e == "__pycache__" || e == "." || e == ".." {
      continue
    }
    let full = join(dir, e)
    let is_dir = @fs.is_dir(full) catch { _ => false }
    if is_dir {
      for p in walk_py_files(full) {
        out.push(p)
      }
    } else if e.has_suffix(".py") {
      out.push(full)
    }
  }
  out
}

// ---------------------------------------------------------------------------

///|
/// Discover a whole program from its entry file.
///
/// `sweep` decides whether every `.py` under the entry's directory is part of
/// the program, or only what the entry imports, transitively. Checking sweeps:
/// the reference discovers an unused module and reports it if it will not
/// parse. Running does not: the semantics only ever loads a module something
/// imports, and a directory full of unrelated files -- which is exactly what
/// the conformance suite's module-level tests are -- must not be dragged in.
///
/// `profile` reaches here because discovery SIEVES each file it loads. A tree
/// found under `core` and checked under a richer profile would have been
/// rejected before the checker ever saw it.
pub fn SourceTree::from_entry(
  entry_path : String,
  predefined~ : Array[String],
  sweep~ : Bool = true,
  profile~ : @profile.Profile = @profile.core,
) -> SourceTree raise {
  let base_dir = parent(entry_path)
  if sweep {
    return lazy_tree(entry_path, base_dir, predefined, profile)
  }
  let entry_tree = load(stem(entry_path), base_dir, profile)
  let modules : Map[String, @ast.Module] = Map([])
  let paths : Map[String, String] = Map([])
  modules["__main__"] = entry_tree
  paths["__main__"] = entry_path
  let queue : Array[String] = []
  for p in predefined {
    queue.push(p)
  }
  @basic.sort_names(queue)
  for n in with_proper_prefixes(import_targets(entry_tree, base_dir)) {
    queue.push(n)
  }
  let mut i = 0
  while i < queue.length() {
    let name = queue[i]
    i += 1
    if modules.contains(name) {
      continue
    }
    let path = is_module(name, base_dir)
    if path is None && predefined.contains(name) {
      modules[name] = { body: [], span: @basic.nowhere, }
      paths[name] = "<\{name}>"
      continue
    }
    let tree = load(name, base_dir, profile)
    modules[name] = tree
    paths[name] = match path {
      Some(p) => p
      None => name
    }
    for q in with_proper_prefixes(import_targets(tree, base_dir)) {
      queue.push(q)
    }
  }
  { base_dir, modules, names: modules.keys().collect(), paths, loader: None, }
}

///|
/// The program a checker sees: every module under the entry's directory by
/// name -- the entry's own name among them, so `import main` from `main.py`
/// is a module like any other -- plus the predefined ones and `__main__`,
/// each parsed the first time it is loaded.
fn lazy_tree(
  entry_path : String,
  base_dir : String,
  predefined : Array[String],
  profile : @profile.Profile,
) -> SourceTree {
  let modules : Map[String, @ast.Module] = Map([])
  let paths : Map[String, String] = Map([])
  for p in predefined {
    modules[p] = { body: [], span: @basic.nowhere, }
    paths[p] = "<\{p}>"
  }
  paths["__main__"] = entry_path
  let names : Array[String] = ["__main__", ..predefined]
  let found : Array[String] = []
  for p in walk_py_files(base_dir) {
    let n = module_name(base_dir, p)
    if n != "" && !found.contains(n) {
      found.push(n)
    }
  }
  for n in with_proper_prefixes(found) {
    if !names.contains(n) {
      names.push(n)
    }
  }
  let loader = fn(q : String) -> (@ast.Module, String) raise {
    if q == "__main__" {
      return (load_path(entry_path, profile), entry_path)
    }
    match is_module(q, base_dir) {
      Some(path) => (load(q, base_dir, profile), path)
      None => raise @err.ill_formed_program("module '\{q}' not found")
    }
  }
  { base_dir, modules, paths, names, loader: Some(loader), }
}
