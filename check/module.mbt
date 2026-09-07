///|
/// Module well-formedness: Figures 3.5 to 3.7.
///
/// A port of the reference's `check_module.py`. The interesting parts are all
/// about IMPORTS:
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
/// The program is a value: `Program` holds the module map and the caches, so
/// checking two programs cannot see each other's answers. The reference keys
/// its global cache on `id(M)` for the same reason.
pub struct Program {
  modules : Map[String, @ast.Module]
  signatures : Map[String, @context.Context]
  loading : Array[String]
}

///|
/// A program from a map of module name to parsed module.
pub fn Program::new(modules : Map[String, @ast.Module]) -> Program {
  { modules, signatures: Map([]), loading: [], }
}

///|
/// The program a single file makes: the predefined modules, empty, and the
/// file itself as `__main__`. This is what `check_module.py` builds.
pub fn Program::single(m : @ast.Module) -> Program {
  let modules : Map[String, @ast.Module] = Map([])
  for p in @context.predefined_modules {
    modules[p] = { body: [], span: @basic.nowhere, }
  }
  modules["__main__"] = m
  Program::new(modules)
}

///|
/// `__name__ = '<q>'`, prepended to every module body before it is checked --
/// which is why `__name__` is a member of every module's signature.
fn name_assign(q : String) -> @ast.Stmt {
  Assign(
    targets=[Name(id="__name__", ctx=Store, span=@basic.nowhere)],
    value=Constant(value=Str(q), span=@basic.nowhere),
    span=@basic.nowhere,
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
/// `a.b.c` has proper prefixes `a` and `a.b`.
fn proper_prefixes(q : String) -> Array[String] {
  let parts = q.split(".").map(fn(v) { v.to_owned() }).collect()
  let out : Array[String] = []
  for i in 1..<parts.length() {
    out.push(parts[:i].to_owned().join("."))
  }
  out
}

///|
fn first_segment(q : String) -> String {
  match q.split_once(".") {
    Some((head, _)) => head.to_owned()
    None => q
  }
}

// ---------------------------------------------------------------------------

///|
/// The signature of a module: what a `from`-import of it can name.
///
/// Cached per program, and guarded by a loading stack so that a cycle is a
/// program-level error rather than a hang.
pub fn check_module(program : Program, q : String) -> @context.Context raise {
  match program.signatures.get(q) {
    Some(cached) => return cached
    None => ()
  }
  match program.loading.search(q) {
    Some(i) => {
      let cycle = program.loading[i:].to_owned()
      cycle.push(q)
      raise @err.ill_formed_program("import cycle: " + cycle.join(" -> "))
    }
    None => ()
  }
  let m = match program.modules.get(q) {
    Some(m) => m
    None => raise @err.ill_formed_program("module '\{q}' not found")
  }
  program.loading.push(q)
  let result = try check_module_body(program, m, q) catch {
    // The innermost module that failed is the one whose path is reported.
    @err.PurePyError(d) => {
      let _ = program.loading.pop()
      raise @err.PurePyError(d.attribute_to(q))
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
) -> @context.Context raise {
  // Imports are not statements: they are a prefix of the body, and one
  // anywhere else is an error before anything is checked.
  match @analysis.find_nested_import(m.body) {
    Some(node) => raise @err.ill_formed(NonTopLevelImport, span=node.span())
    None => ()
  }
  let (prefix, rest) = @analysis.split_imports(m.body)
  match @analysis.find_import(rest) {
    Some(node) => {
      let mut d = @err.Diagnostic::new(
        IllFormed(ImportAfterStatement),
        span=node.span(),
      )
      // The first statement that is not an import is the one the import has
      // to move above.
      if !rest.is_empty() && !@analysis.is_import(rest[0]) {
        d = d.with_related(rest[0].span(), "this statement comes before it")
      }
      raise d.raise_()
    }
    None => ()
  }
  let empty_ctx : Ctx = { gamma: @context.empty_context(), program, q, }
  let gamma0 = check_imports_prefix(prefix[:], empty_ctx)
  let body = [name_assign(q)]
  for s in rest {
    body.push(s)
  }
  let gamma1 = @context.extend_context(
    @context.predefined_context("builtins"),
    gamma0,
  )
  let items = @analysis.statements(body)
  // A module body may not return.
  for item in items {
    if result_type_statement(item) is Returns {
      raise @err.ill_formed(TopLevelReturn, span=first_node(item).span())
    }
  }
  let final_ctx = check_seq(items[:], { gamma: gamma1, program, q, })
  check_submodule_clash(program, m, gamma0, body, q)
  signature(program, body, final_ctx, q)
}

///|
/// The bindings the import prefix makes, folded so that a later import
/// extends an earlier one rather than replacing it.
fn check_imports_prefix(
  prefix : ArrayView[@ast.Stmt],
  ctx : Ctx,
) -> @context.Context raise {
  if prefix.is_empty() {
    return @context.empty_context()
  }
  @context.extend_context(
    import_bindings(prefix[0], ctx),
    check_imports_prefix(prefix[1:], ctx),
  )
}

///|
fn import_bindings(s : @ast.Stmt, ctx : Ctx) -> @context.Context raise {
  match s {
    Import(names~, span~) => {
      let q = names[0].name
      if !ctx.program.modules.contains(q) {
        raise @err.ill_formed(UnknownModule(q~), span~)
      }
      // `import a.b` inside `a` would need `a` while `a` is being checked.
      if proper_prefix_of(ctx.q, q) {
        raise @err.ill_formed(OwnDescendantImport(q~, q0=ctx.q), span~)
      }
      let delta = check_module(ctx.program, q)
      @context.context_of([
        (first_segment(q), loads_as(q, ModuleLoaded(q, delta), ctx)),
      ])
    }
    ImportFrom(module_name~, names~, span~, ..) => {
      if names.is_empty() {
        raise @err.ill_formed(EmptyFromImport, span~)
      }
      let source = match module_name {
        Some(m) => m
        None => abort("the sieve insists a from-import names its module")
      }
      if !ctx.program.modules.contains(source) {
        raise @err.ill_formed(UnknownModule(q=source), span~)
      }
      let delta = check_module(ctx.program, source)
      // Every ancestor of the imported module is loaded too, unless it is an
      // ancestor of the importing module -- which is being checked already.
      for p in proper_prefixes(source) {
        if !prefix_of(p, ctx.q) {
          check_module(ctx.program, p) |> ignore
        }
      }
      let entries : Array[(String, @context.Entry)] = []
      for a in names {
        entries.push((a.name, imported_entry(s, a.name, source, delta, ctx)))
      }
      @context.context_of(entries)
    }
    _ => abort("not an import")
  }
}

///|
/// `import a.b.c` binds `a`, to a module whose `b` is a module whose `c` is
/// the module that was imported.
fn loads_as(
  q : String,
  theta : @context.Entry,
  ctx : Ctx,
) -> @context.Entry raise {
  match q.rev_split_once(".") {
    None => theta
    Some((parent, x)) => {
      let parent_name = parent.to_owned()
      let parent_ctx = check_module(ctx.program, parent_name)
      loads_as(
        parent_name,
        ModuleLoaded(
          parent_name,
          @context.extend_context(
            parent_ctx,
            @context.context_of([(x.to_owned(), theta)]),
          ),
        ),
        ctx,
      )
    }
  }
}

///|
/// What `from q import x` binds `x` to.
fn imported_entry(
  s : @ast.Stmt,
  x : String,
  q : String,
  gamma_src : @context.Context,
  ctx : Ctx,
) -> @context.Entry raise {
  let span = s.span()
  match gamma_src.get(x) {
    None => raise @err.ill_formed(UnknownMember(x~, q~), span~)
    // A submodule named in the signature is loaded by the from-import.
    Some(ModuleStub(sub)) => ModuleLoaded(sub, check_module(ctx.program, sub))
    Some(Var(FF)) => raise @err.ill_formed(UnassignedMember(x~, q~), span~)
    Some(entry) => entry
  }
}

///|
/// The modules of the program that are children of `q`, as stubs.
fn submods(program : Program, q : String) -> @context.Context {
  let seen : Array[String] = []
  let entries : Array[(String, @context.Entry)] = []
  for name in program.modules.keys() {
    if name.has_prefix(q + ".") {
      let child = first_segment(name[q.length() + 1:].to_owned())
      if !seen.contains(child) {
        seen.push(child)
        entries.push((child, ModuleStub("\{q}.\{child}")))
      }
    }
  }
  @context.context_of(entries)
}

///|
/// What a module exports: its own members, and the fixed table for a
/// predefined one.
fn own_members(body : Array[@ast.Stmt], q : String) -> Array[String] {
  match @context.predefined_members(q) {
    Some(ms) => ms
    None => @analysis.assigns_body(body).to_array()
  }
}

///|
/// A binding that shadows a submodule would make `q.x` ambiguous.
fn check_submodule_clash(
  program : Program,
  m : @ast.Module,
  gamma0 : @context.Context,
  body : Array[@ast.Stmt],
  q : String,
) -> Unit raise {
  let subs = submods(program, q)
  let clash : Array[String] = []
  for name in gamma0.keys_as_iter() {
    if subs.contains(name) && !clash.contains(name) {
      clash.push(name)
    }
  }
  for name in own_members(body, q) {
    if subs.contains(name) && !clash.contains(name) {
      clash.push(name)
    }
  }
  if clash.is_empty() {
    return
  }
  @basic.sort_names(clash)
  let x = clash[0]
  match find_binder(m.body, x) {
    Some(node) =>
      raise @err.ill_formed(
        SubmoduleNameClash(name=x, submodule="\{q}.\{x}"),
        span=node.span(),
      )
    None => abort("a clashing name must have a statement that binds it")
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
fn signature(
  program : Program,
  body : Array[@ast.Stmt],
  final_ctx : Ctx,
  q : String,
) -> @context.Context {
  let stubs = submods(program, q)
  let own = match @context.predefined_members(q) {
    Some(_) => @context.predefined_context(q)
    None => {
      let entries : Array[(String, @context.Entry)] = []
      for name in own_members(body, q) {
        match final_ctx.gamma.get(name) {
          Some(e) => entries.push((name, e))
          None => ()
        }
      }
      @context.context_of(entries)
    }
  }
  @context.extend_context(stubs, own)
}

// ---------------------------------------------------------------------------

///|
/// Check one module as `__main__`, with only the predefined modules
/// importable -- what `pure-py check FILE` does.
pub fn check_single(m : @ast.Module) -> @err.Diagnostic? {
  let program = Program::single(m)
  try check_module(program, "__main__") |> ignore catch {
    @err.PurePyError(d) => Some(d)
    _ => None
  } noraise {
    _ => None
  }
}

///|
/// The modules every program has, whatever its source tree.
pub fn predefined_module_names() -> Array[String] {
  @context.predefined_modules
}
