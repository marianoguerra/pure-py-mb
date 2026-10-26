///|
/// Contexts, entries and their operators: a port of the reference's
/// `contexts.py`.
///
/// A context maps a name to what it stands for. It is immutable and sorted:
/// immutable because contexts are threaded functionally through every rule and
/// no branch may see another's bindings, sorted so that nothing a message
/// reports depends on the order a map happened to be built in.
pub type Context = @sorted_map.SortedMap[String, Entry]

///|
/// What a name can stand for.
pub(all) enum Entry {
  /// A variable that is definitely assigned, with its type.
  Var(@types.Type)
  /// A variable that is not definitely assigned: the spec's `ff`.
  Unassigned
  /// A module named but not loaded.
  ModuleStub(String)
  /// A module whose members are known.
  ModuleLoaded(String, Context)
  /// A class, by its qualified name in the class table.
  Class(String)
  /// A name usable only in an annotation or as a decorator: `int`, `list`,
  /// `Callable`, `dataclass`.
  Predefined
} derive(Eq, Debug)

///|
pub fn empty_context() -> Context {
  @sorted_map.SortedMap::new()
}

///|
pub fn context_of(entries : Array[(String, Entry)]) -> Context {
  let mut g = empty_context()
  for e in entries {
    g = g.add(e.0, e.1)
  }
  g
}

///|
/// `{**gamma, **delta}`.
pub fn override_context(gamma : Context, delta : Context) -> Context {
  let mut g = gamma
  delta.each(fn(k, v) { g = g.add(k, v) })
  g
}

///|
/// A module being checked: its context, the program it belongs to, and its
/// own qualified name. The class table is the program's.
priv struct ModCtx {
  gamma : Context
  program : Program
  q : String
}

///|
fn ModCtx::sigma(self : ModCtx) -> @types.ClassTable {
  self.program.sigma
}

///|
fn ModCtx::override_gamma(self : ModCtx, delta : Context) -> ModCtx {
  { ..self, gamma: override_context(self.gamma, delta), }
}

///|
fn ModCtx::assigned_type(self : ModCtx, x : String) -> @types.Type? {
  match self.gamma.get(x) {
    Some(Var(t)) => Some(t)
    _ => None
  }
}

///|
fn ModCtx::is_assigned(self : ModCtx, x : String) -> Bool {
  self.gamma.get(x) is Some(Var(_))
}

///|
/// What a qualified name stands for: a name in the context, or a member of a
/// loaded module reached through it.
fn resolve_name(q : Array[String], ctx : ModCtx) -> Entry? {
  if q.length() == 1 {
    return ctx.gamma.get(q[0])
  }
  match resolve_name(q[:q.length() - 1].to_owned(), ctx) {
    Some(ModuleLoaded(_, members)) => members.get(q[q.length() - 1])
    _ => None
  }
}

///|
fn ModCtx::module_of(self : ModCtx, x : String) -> Entry? {
  match self.gamma.get(x) {
    Some(ModuleStub(_) as e) | Some(ModuleLoaded(_, _) as e) => Some(e)
    _ => None
  }
}

///|
fn entry_of(e : @ast.Expr, ctx : ModCtx) -> Entry? {
  match @types.dotted_name(e) {
    Some(q) => resolve_name(q, ctx)
    None => None
  }
}

///|
fn class_of_name(e : @ast.Expr, ctx : ModCtx) -> String? {
  match entry_of(e, ctx) {
    Some(Class(c)) => Some(c)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Static outcomes

///|
/// What a statement sequence leaves behind: it returns, or it assigns.
priv enum Outcome {
  Returns
  Assigns(Context)
}

///|
fn assigns_nothing() -> Outcome {
  Assigns(empty_context())
}

///|
/// Assigned in both branches gives the join of the two types; assigned in one
/// alone is not definitely assigned.
fn merge_entry(sigma : @types.ClassTable, a : Entry, b : Entry) -> Entry {
  match (a, b) {
    (Var(s), Var(t)) => Var(@types.join_seq(sigma, [s, t]))
    _ => Unassigned
  }
}

///|
fn merge_context(
  sigma : @types.ClassTable,
  g : Context,
  h : Context,
) -> Context {
  let mut out = empty_context()
  g.each(fn(x, a) {
    out = out.add(
      x,
      match h.get(x) {
        Some(b) => merge_entry(sigma, a, b)
        None => Unassigned
      },
    )
  })
  h.each(fn(x, _) { if !g.contains(x) { out = out.add(x, Unassigned) } })
  out
}

///|
fn merge_outcomes(sigma : @types.ClassTable, rs : Array[Outcome]) -> Outcome {
  let branches : Array[Context] = []
  for r in rs {
    if r is Assigns(d) {
      branches.push(d)
    }
  }
  if branches.is_empty() {
    return Returns
  }
  let mut acc = branches[0]
  for i in 1..<branches.length() {
    acc = merge_context(sigma, acc, branches[i])
  }
  Assigns(acc)
}

///|
fn override_outcomes(r : Outcome, s : Outcome) -> Outcome {
  match (r, s) {
    (Returns, _) => Returns
    (_, Returns) => Returns
    (Assigns(a), Assigns(b)) => Assigns(override_context(a, b))
  }
}

///|
/// Extending prefers a loaded module over a stub of the same module, and
/// merges two loadings of the same module member by member.
fn extend_entry(a : Entry, b : Entry) -> Entry {
  match (a, b) {
    (ModuleLoaded(qa, ma), ModuleLoaded(qb, mb)) =>
      if qa == qb {
        ModuleLoaded(qa, extend_context(ma, mb))
      } else {
        b
      }
    (ModuleLoaded(qa, _), ModuleStub(qb)) => if qa == qb { a } else { b }
    _ => b
  }
}

///|
fn extend_context(g : Context, h : Context) -> Context {
  let mut out = g
  h.each(fn(x, e) {
    out = out.add(
      x,
      match g.get(x) {
        Some(old) => extend_entry(old, e)
        None => e
      },
    )
  })
  out
}

///|
/// The join of each variable's types across several deltas, which must all
/// assign the same variables, each definitely.
fn join_context(sigma : @types.ClassTable, deltas : Array[Context]) -> Context {
  let mut out = empty_context()
  deltas[0].each(fn(x, _) {
    let ts = deltas.map(fn(d) {
      match d.get(x) {
        Some(Var(t)) => t
        _ => abort("a pattern binds every variable at a type")
      }
    })
    out = out.add(x, Var(@types.join_seq(sigma, ts)))
  })
  out
}

// ---------------------------------------------------------------------------
// The predefined modules

///|
/// Each predefined module's members as context entries.
pub fn predefined_members(q : String) -> Array[(String, Entry)]? {
  match @types.predefined_members(q) {
    Some(ms) =>
      Some(
        ms.map(fn(m) {
          (
            m.0,
            match m.1 {
              Some(t) => Var(t)
              None => Predefined
            },
          )
        }),
      )
    None => None
  }
}

///|
/// The modules the specification predefines.
pub let predefined_modules : Array[String] = @types.predefined_modules

///|
/// A predefined module's signature: its members, and `__name__`.
fn predefined_context(members : Array[(String, Entry)]) -> Context {
  context_of([..members, ("__name__", Var(@types.t_str))])
}
