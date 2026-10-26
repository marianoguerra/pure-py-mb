///|
/// Module and program well-formedness: a port of the reference's
/// `check_module.py` and `check_program.py`.
///
/// The interesting parts are all about IMPORTS:
///
///   * A module's signature is computed once and cached, and a cycle is
///     detected by a stack rather than a depth limit -- so `a` importing `b`
///     importing `a` names both, in the order they were entered.
///   * `import a.b.c` binds `a` alone, to a module whose members contain `b`,
///     whose members contain `c`. That is `loads_as`.
///   * Every module in the program that begins with `q.` is a SUBMODULE of
///     `q` and appears in its signature as a stub -- named but not loaded.
///     Binding a name that clashes with one is an error.
///
/// The program is a value: `Program` holds the module tree and the caches,
/// so checking two programs cannot see each other's answers. The reference
/// keys its global cache on `id(M)` for the same reason.
pub struct Program {
  tree : @program.SourceTree
  /// Modules an EMBEDDING host defines, and each member's type.
  ///
  /// They stand exactly where the predefined modules stand: named, with an
  /// empty body, and with their members given by a table rather than read off
  /// a body. What a host function IS is the evaluator's business; what it may
  /// be called with is the checker's, and that is the type.
  host_members : Map[String, Array[(String, @types.Type)]]
  /// The superset of PurePy the caller opted in to.
  profile : @profile.Profile
  /// The class table: every class declared so far, program-wide.
  ///
  /// The reference threads Σ through every rule and returns it, but always
  /// the newest one, and never rolls one back -- so one table per program,
  /// updated where a class is declared, gives the same answers.
  mut sigma : @types.ClassTable
  signatures : Map[String, Context]
  loading : Array[String]
}

///|
/// A program from a source tree.
pub fn Program::new(
  tree : @program.SourceTree,
  host_members~ : Map[String, Array[(String, @types.Type)]] = Map([]),
  profile~ : @profile.Profile = @profile.core,
) -> Program {
  for p in predefined_modules {
    add_bodiless(tree, p)
  }
  for name, _ in host_members {
    add_bodiless(tree, name)
  }
  {
    tree,
    host_members,
    profile,
    sigma: @types.predefined_classes(),
    signatures: Map([]),
    loading: [],
  }
}

///|
/// A module with no source -- predefined, or the host's -- stands in the
/// program with an empty body. Discovery puts the predefined ones in a tree
/// read off a disk; a tree assembled in memory has never seen them.
fn add_bodiless(tree : @program.SourceTree, q : String) -> Unit {
  if !tree.modules.contains(q) {
    tree.modules[q] = { body: [], span: @basic.nowhere, }
    tree.paths[q] = "<\{q}>"
  }
  if !tree.names.contains(q) {
    tree.names.push(q)
  }
}

///|
/// `__name__: str = '<q>'`, the declaration that begins every module's body,
/// at the start of the module.
fn name_declaration(q : String) -> @ast.Stmt {
  let at = @basic.Span::at({ line: 1, col: 0, offset: 0, })
  AnnAssign(
    target=Name(id="__name__", ctx=Store, span=at),
    annotation=Name(id="str", ctx=Load, span=at),
    value=Some(Constant(value=Str(q), span=at)),
    simple=true,
    span=at,
  )
}

///|
fn prefix_of(p : String, q : String) -> Bool {
  p == q || q.has_prefix(p + ".")
}

///|
fn proper_prefix_of(p : String, q : String) -> Bool {
  p != q && prefix_of(p, q)
}

///|
fn first_segment(q : String) -> String {
  match q.split_once(".") {
    Some((head, _)) => head.to_owned()
    None => q
  }
}

///|
/// The members of a module that has no source: one the specification
/// predefines, or one an embedding host defines.
fn members_without_source(
  program : Program,
  q : String,
) -> Array[(String, Entry)]? {
  match predefined_members(q) {
    Some(ms) =>
      Some(
        if q == "builtins" {
          let extras = extra_builtin_entries(program.profile)
          [
            ..ms.filter(fn(m) { !extras.iter().any(fn(e) { e.0 == m.0 }) }),
            ..extras,
          ]
        } else {
          ms
        },
      )
    None =>
      match program.host_members.get(q) {
        Some(ms) => Some(ms.map(fn(m) { (m.0, Var(m.1)) }))
        None => None
      }
  }
}

// ---------------------------------------------------------------------------

///|
/// The signature of a module: what an import of it can name.
///
/// Cached per program, and guarded by a loading stack so that a cycle is a
/// program-level error rather than a hang.
pub fn check_module(program : Program, q : String) -> Context raise {
  // The reference has the module in hand before it asks the cache, so a
  // module that will not parse fails here, whatever else is true.
  let m = program.tree.load(q)
  match program.signatures.get(q) {
    Some(cached) => return cached
    None => ()
  }
  match program.loading.search(q) {
    Some(i) => {
      let cycle = [..program.loading[i:], q]
      raise @err.ill_formed_program("import cycle: " + cycle.join(" -> "))
    }
    None => ()
  }
  program.loading.push(q)
  let result = try check_module_body(program, m, q) catch {
    // The innermost module that failed is the one whose path is reported.
    @err.PurePyError(d) => {
      let _ = program.loading.pop()
      raise @err.PurePyError(
        if d.kind is IllFormed(_) {
          d.attribute_to(q)
        } else {
          d
        },
      )
    }
    e => {
      let _ = program.loading.pop()
      raise e
    }
  } noraise {
    r => r
  }
  let _ = program.loading.pop()
  program.signatures[q] = result
  result
}

///|
fn check_module_body(
  program : Program,
  m : @ast.Module,
  q : String,
) -> Context raise {
  match members_without_source(program, q) {
    Some(ms) => return predefined_context(ms)
    None => ()
  }
  let (prefix, stmts) = @analysis.split_imports(m.body)
  let imported = @analysis.declares_body(prefix).map(fn(d) { d.0 })
  let empty_ctx : ModCtx = { gamma: empty_context(), program, q, }
  let gamma = check_imports_prefix(prefix[:], empty_ctx)
  let body = [name_declaration(q), ..stmts]
  let bound = scope(imported, body)
  check_assignments_declared(body, [])
  let builtins = builtins_context(program.profile)
  let final_ctx = check_top_seq(@analysis.statements(body)[:], {
    gamma: override_context(override_context(builtins, gamma), bound),
    program,
    q,
  })
  check_submodule_names(program, m, gamma, body, q)
  module_signature(program, body, final_ctx, q)
}

///|
/// The bindings the import prefix makes, folded so that a later import
/// extends an earlier one rather than replacing it.
fn check_imports_prefix(
  prefix : ArrayView[@ast.Stmt],
  ctx : ModCtx,
) -> Context raise {
  if prefix.is_empty() {
    return empty_context()
  }
  let gamma = check_import(prefix[0], ctx)
  extend_context(gamma, check_imports_prefix(prefix[1:], ctx))
}

///|
fn check_import(iota : @ast.Stmt, ctx : ModCtx) -> Context raise {
  let program = ctx.program
  match iota {
    Import(names~, span~) => {
      let q = names[0].name
      if proper_prefix_of(ctx.q, q) {
        raise ill(
          ImportOfContainedModule(
            q~,
            q_=ctx.q,
            from_import="from \{q} import <name>",
          ),
          span,
        )
      }
      let parts = q.split(".").map(fn(v) { v.to_owned() }).collect()
      let x = parts[0]
      let delta = check_imported(x, span, ctx)
      context_of([
        (x, loads_as(ModuleLoaded(x, delta), parts[1:].to_owned(), span, ctx)),
      ])
    }
    ImportFrom(module_name~, names~, span~, ..) => {
      guard module_name is Some(q) else {
        abort("a relative import is rejected by the sieve")
      }
      let xs = names.map(fn(a) { a.name })
      for i, x in xs {
        if xs[:i].contains(x) {
          raise ill(DuplicateImportedName(x~), span)
        }
      }
      let delta = check_imported(q, span, ctx)
      // Every module containing the imported one is loaded too, unless it
      // contains the importing module -- which is being checked already.
      for p in @program.proper_prefixes(q) {
        if !prefix_of(p, ctx.q) {
          check_module(program, p) |> ignore
        }
      }
      let mut out = empty_context()
      for x in xs {
        out = out.add(x, imported_entry(iota, x, q, delta, ctx))
      }
      out
    }
    _ => abort("not an import")
  }
}

///|
fn check_imported(
  q : String,
  span : @basic.Span,
  ctx : ModCtx,
) -> Context raise {
  if !ctx.program.tree.contains(q) {
    raise ill(UnknownModule(q~), span)
  }
  check_module(ctx.program, q)
}

///|
/// `import a.b.c` binds `a`, to a module whose `b` is a module whose `c` is
/// the module that was imported, each loaded in that order.
fn loads_as(
  theta : Entry,
  xs : Array[String],
  span : @basic.Span,
  ctx : ModCtx,
) -> Entry raise {
  guard theta is ModuleLoaded(q, members) else { abort("a loaded module") }
  if xs.is_empty() {
    return theta
  }
  let x = xs[0]
  let qx = q + "." + x
  let gamma = check_imported(qx, span, ctx)
  let inner = loads_as(ModuleLoaded(qx, gamma), xs[1:].to_owned(), span, ctx)
  ModuleLoaded(q, extend_context(members, context_of([(x, inner)])))
}

///|
/// What `from q import x` binds `x` to.
fn imported_entry(
  iota : @ast.Stmt,
  x : String,
  q : String,
  gamma : Context,
  ctx : ModCtx,
) -> Entry raise {
  let span = iota.span()
  match gamma.get(x) {
    None => raise ill(UnknownMember(x~, q~), span)
    // A submodule named in the signature is loaded by the from-import.
    Some(ModuleStub(sub)) => ModuleLoaded(sub, check_module(ctx.program, sub))
    Some(Unbound | DU(_) | PU(_)) => raise ill(UnassignedMember(x~, q~), span)
    Some(entry) => entry
  }
}

///|
/// The modules of the program that are children of `q`, as stubs.
fn submods(program : Program, q : String) -> Context {
  let mut out = empty_context()
  for name in program.tree.module_names() {
    if name.has_prefix(q + ".") {
      let child = first_segment(name[q.length() + 1:].to_owned())
      out = out.add(child, ModuleStub("\{q}.\{child}"))
    }
  }
  out
}

///|
/// A binding that shadows a submodule would make `q.x` ambiguous.
fn check_submodule_names(
  program : Program,
  m : @ast.Module,
  gamma : Context,
  body : Array[@ast.Stmt],
  q : String,
) -> Unit raise {
  let subs = submods(program, q)
  let clash : Array[String] = []
  let consider = fn(x : String) {
    if subs.contains(x) && !clash.contains(x) {
      clash.push(x)
    }
  }
  gamma.each(fn(x, _) { consider(x) })
  for x in @analysis.assigns_body(body).to_array() {
    consider(x)
  }
  if clash.is_empty() {
    return
  }
  @basic.sort_names(clash)
  let x = clash[0]
  match find_binder(m.body, x) {
    Some(node) => raise ill(DuplicateMember(x~, q~), node.span())
    None => abort("a clashing name has a statement that binds it")
  }
}

///|
fn binds_name(s : @ast.Stmt, x : String) -> Bool {
  match s {
    Import(names~, ..) => first_segment(names[0].name) == x
    ImportFrom(names~, ..) => names.iter().any(fn(a) { a.name == x })
    ClassDef(name~, ..) => name == x
    _ => @analysis.assigns_stmt(s).contains(x)
  }
}

///|
fn find_binder(stmts : Array[@ast.Stmt], x : String) -> @ast.Stmt? {
  for s in stmts {
    if binds_name(s, x) {
      return Some(s)
    }
  }
  None
}

///|
/// The signature: submodule stubs, overridden by the module's own members.
fn module_signature(
  program : Program,
  body : Array[@ast.Stmt],
  final_ctx : ModCtx,
  q : String,
) -> Context {
  let mut own = empty_context()
  for x in @analysis.assigns_body(body).to_array() {
    match final_ctx.gamma.get(x) {
      Some(e) => own = own.add(x, e)
      None => ()
    }
  }
  override_context(submods(program, q), own)
}

// ---------------------------------------------------------------------------
// Entry points

///|
/// Check one module as `__main__`, with only the predefined modules and the
/// host's importable -- what `pure-py check FILE` does.
pub fn check_single(
  m : @ast.Module,
  host_members~ : Map[String, Array[(String, @types.Type)]] = Map([]),
  profile~ : @profile.Profile = @profile.core,
) -> @err.Diagnostic? {
  let tree = @program.SourceTree::of(Map([("__main__", m)]))
  let program = Program::new(tree, host_members~, profile~)
  try check_module(program, "__main__") |> ignore catch {
    @err.PurePyError(d) => Some(d)
    _ => None
  } noraise {
    _ => None
  }
}

///|
/// Program well-formedness: the entry module checked against everything the
/// source tree contains.
///
/// One rule the module checker does not have: a module-level rejection is
/// attributed to the FILE it came from, so a program whose `helper.py` is ill
/// formed says so, and loses its position. Anything else is already a whole
/// sentence.
pub fn check_program(
  tree : @program.SourceTree,
  host_members~ : Map[String, Array[(String, @types.Type)]] = Map([]),
  profile~ : @profile.Profile = @profile.core,
) -> @err.Diagnostic? {
  let program = Program::new(tree, host_members~, profile~)
  try check_module(program, "__main__") |> ignore catch {
    @err.PurePyError(d) =>
      match d.kind {
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
pub fn check_entry(
  entry_path : String,
  profile~ : @profile.Profile = @profile.core,
) -> @err.Diagnostic? {
  let tree = @program.SourceTree::from_entry(
    entry_path,
    predefined=predefined_modules,
    profile~,
  ) catch {
    @err.PurePyError(d) => return Some(d)
    e => return Some(@err.Diagnostic::new(Program(msg="\{e}")))
  }
  check_program(tree, profile~)
}

///|
/// The modules every program has, whatever its source tree.
pub fn predefined_module_names() -> Array[String] {
  predefined_modules
}
