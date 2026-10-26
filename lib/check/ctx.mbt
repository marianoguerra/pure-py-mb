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
  /// A name the scope will bind, not yet declared: what every name a body
  /// assigns starts as (v0.17).
  Unbound
  /// Declared at a type and not yet assigned: `x: int` with no value.
  DU(@types.Type)
  /// Possibly unassigned: assigned on some paths and not others. Whether it
  /// was declared in a branch changes only the message.
  PU(Declared, declared_in_branch~ : Bool)
  /// A generic function's signature: the reference's `TypeScheme`.
  Scheme(Array[String], @types.Type)
  /// A type parameter in scope: usable only in an annotation.
  TypeParam
  /// A type alias (`type X[T] = ...`): its definition, resolved where it is
  /// used, since the aliases of a mutual type region may name one another.
  Alias(TypeDefinition)
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
/// The `i`th definition of a mutual type region, and the context and module
/// the region was checked in.
pub(all) struct TypeDefinition {
  gamma : Context
  q : String
  chis : Array[@ast.Stmt]
  i : Int32
} derive(Eq, Debug)

///|
/// What a variable entry was declared at: a type, or a generic signature.
pub(all) enum Declared {
  Mono(@types.Type)
  Poly(Array[String], @types.Type)
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
///
/// `Assigns`'s second component: the sequence falls through only for mypy's
/// sake, and if it ends a function body it is refused for that reason, at
/// that place.
priv enum Outcome {
  Returns
  Assigns(Context, (@err.Reason, @basic.Span)?)
}

///|
fn assigns_nothing() -> Outcome {
  Assigns(empty_context(), None)
}

///|
/// Two branches agree on an entry, or it is possibly unassigned at the type
/// it was declared at.
fn merge_entry(a : Entry?, b : Entry?, declared_in_branch : Bool) -> Entry {
  match (a, b) {
    (Some(x), Some(y)) if x == y => x
    (Some(x), _) | (None, Some(x)) =>
      PU(declared_type_of(x), declared_in_branch~)
    (None, None) => abort("an entry on one side at least")
  }
}

///|
fn merge_context(g : Context, h : Context, declared : Array[String]) -> Context {
  let mut out = empty_context()
  g.each(fn(x, a) {
    out = out.add(x, merge_entry(Some(a), h.get(x), declared.contains(x)))
  })
  h.each(fn(x, b) {
    if !g.contains(x) {
      out = out.add(x, merge_entry(None, Some(b), declared.contains(x)))
    }
  })
  out
}

///|
/// The type a variable entry was declared or assigned at.
fn declared_type_of(e : Entry) -> Declared {
  match e {
    Var(t) | DU(t) => Mono(t)
    PU(d, ..) => d
    Scheme(ps, t) => Poly(ps, t)
    _ => abort("merged entries are assigned or declared variables")
  }
}

///|
fn merge_outcomes(rs : Array[Outcome], declared : Array[String]) -> Outcome {
  let branches : Array[Context] = []
  let mypy_only = []
  for r in rs {
    if r is Assigns(d, m) {
      branches.push(d)
      mypy_only.push(m)
    }
  }
  if branches.is_empty() {
    return Returns
  }
  let mut acc = branches[0]
  for i in 1..<branches.length() {
    acc = merge_context(acc, branches[i], declared)
  }
  // Mypy-only when every branch that falls through does so only for mypy.
  Assigns(
    acc,
    if mypy_only.iter().all(fn(m) { m is Some(_) }) {
      mypy_only[0]
    } else {
      None
    },
  )
}

///|
fn override_outcomes(r : Outcome, s : Outcome) -> Outcome {
  match (r, s) {
    (Returns, _) => Returns
    (_, Returns) => Returns
    // A statement after a mypy-only fall-through is reachable only for mypy.
    (Assigns(a, m), Assigns(b, n)) =>
      Assigns(override_context(a, b), if m is None { n } else { None })
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
              Typed(t) => Var(t)
              AnnotationOnly => Predefined
              ClassOf(c) => Class(c)
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
