///|
/// Contexts, entries and the three operators of Figure 2.2 and Definition 3.1.
///
/// A port of the reference's `contexts.py`. The context is an IMMUTABLE sorted
/// map: immutable because contexts are threaded functionally through every
/// rule and nothing may see a later branch's bindings, sorted because two
/// messages -- the submodule clash and the mutual-region duplicate -- name
/// `sorted(...)[0]`, and an accidental order would name a different variable.
pub type Context = @sorted_map.SortedMap[String, Entry]

///|
/// Whether a variable is definitely assigned. The spec writes `tt` and `ff`.
pub(all) enum Status {
  TT
  FF
} derive(Eq, Debug, Compare)

///|
/// What a name can stand for.
pub(all) enum Entry {
  /// A variable, definitely assigned or not.
  Var(Status)
  /// A module named but not loaded: `import a.b` puts `a.b` in scope as a
  /// stub until something loads it.
  ModuleStub(String)
  /// A module whose members are known.
  ModuleLoaded(String, Context)
  /// A class declaration.
  Class(ClassEntry)
} derive(Eq, Debug)

///|
/// A class, with the context it was DECLARED in.
///
/// The declaring context is the load-bearing part: `fields` and `ancestors`
/// resolve the base class through it and not through whatever context is
/// current, so a class that is imported keeps the meaning it had where it was
/// written.
pub(all) struct ClassEntry {
  context : Context
  name : String
  own_fields : Array[String]
  base : String?
} derive(Eq, Debug)

///|
/// A module being checked: the context, the program it belongs to, and its own
/// qualified name.
pub(all) struct ModuleContext[M] {
  gamma : Context
  program : M
  q : String
} derive(Eq, Debug)

///|
pub fn empty_context() -> Context {
  @sorted_map.SortedMap::new()
}

///|
pub fn context_of(entries : Array[(String, Entry)]) -> Context {
  @sorted_map.SortedMap(entries[:])
}

// ---------------------------------------------------------------------------
// Lookup

///|
pub fn[M] ModuleContext::override_gamma(
  self : ModuleContext[M],
  delta : Context,
) -> ModuleContext[M] {
  let mut g = self.gamma
  delta.each(fn(k, v) { g = g.add(k, v) })
  { ..self, gamma: g, }
}

///|
pub fn[M] ModuleContext::override_var(
  self : ModuleContext[M],
  delta : VarContext,
) -> ModuleContext[M] {
  let mut g = self.gamma
  delta.each(fn(k, v) { g = g.add(k, Var(v)) })
  { ..self, gamma: g, }
}

///|
/// A delta of variables only: what a statement's result type carries.
pub type VarContext = @sorted_map.SortedMap[String, Status]

///|
pub fn empty_vars() -> VarContext {
  @sorted_map.SortedMap::new()
}

///|
pub fn vars_of(entries : Array[(String, Status)]) -> VarContext {
  @sorted_map.SortedMap(entries[:])
}

///|
pub fn[M] ModuleContext::var_status(
  self : ModuleContext[M],
  x : String,
) -> Status? {
  match self.gamma.get(x) {
    Some(Var(s)) => Some(s)
    _ => None
  }
}

///|
pub fn[M] ModuleContext::class_of(
  self : ModuleContext[M],
  c : String,
) -> ClassEntry? {
  match self.gamma.get(c) {
    Some(Class(e)) => Some(e)
    _ => None
  }
}

///|
/// The module a name stands for, loaded or not.
pub fn[M] ModuleContext::module_of(
  self : ModuleContext[M],
  x : String,
) -> Entry? {
  match self.gamma.get(x) {
    Some(ModuleStub(_) as e) | Some(ModuleLoaded(_, _) as e) => Some(e)
    _ => None
  }
}

///|
/// What a qualified name stands for: a name in the context, or a member of a
/// loaded module reached through it.
pub fn[M] entry_of(e : @ast.Expr, ctx : ModuleContext[M]) -> Entry? {
  match e {
    Name(id~, ..) => ctx.gamma.get(id)
    Attribute(value~, attr~, ..) =>
      match entry_of(value, ctx) {
        Some(ModuleLoaded(_, members)) => members.get(attr)
        _ => None
      }
    _ => None
  }
}

///|
pub fn[M] class_entry(e : @ast.Expr, ctx : ModuleContext[M]) -> ClassEntry? {
  match entry_of(e, ctx) {
    Some(Class(c)) => Some(c)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Classes

///|
/// The last segment of a class's qualified name -- what a message prints.
pub fn ClassEntry::short_name(self : ClassEntry) -> String {
  match self.name.rev_split_once(".") {
    Some((_, last)) => last.to_owned()
    None => self.name
  }
}

///|
/// The class and every class it inherits from, nearest first.
pub fn ClassEntry::ancestors(self : ClassEntry) -> Array[ClassEntry] {
  match self.base {
    None => [self]
    Some(b) =>
      match self.context.get(b) {
        Some(Class(base)) => [self] + base.ancestors()
        _ => abort("a class's base must be a class in its declaring context")
      }
  }
}

///|
/// Every field, INHERITED FIRST -- which is the order a constructor's
/// positional arguments are in and the order an object prints in.
pub fn ClassEntry::fields(self : ClassEntry) -> Array[String] {
  match self.base {
    None => self.own_fields
    Some(b) =>
      match self.context.get(b) {
        Some(Class(base)) => base.fields() + self.own_fields
        _ => abort("a class's base must be a class in its declaring context")
      }
  }
}

///|
/// Match a constructor's or a pattern's arguments to the class's fields.
///
/// `None` when the call is over- or under-saturated, when a keyword is
/// repeated, or when the keywords are not exactly the fields the positional
/// arguments did not cover.
pub fn[T] ClassEntry::field_map(
  self : ClassEntry,
  positional : Array[T],
  kwd_names : Array[String],
  kwd_values : Array[T],
) -> Array[(String, T)]? {
  let xs = self.fields()
  let n = positional.length()
  if n + kwd_names.length() != xs.length() {
    return None
  }
  let seen = @sorted_map.SortedMap::from_iter(
    kwd_names.iter().map(fn(k) { (k, true) }),
  )
  if seen.length() != kwd_names.length() {
    return None
  }
  let rest = @sorted_map.SortedMap::from_iter(
    xs[n:].iter().map(fn(k) { (k, true) }),
  )
  if seen.length() != rest.length() {
    return None
  }
  for k in kwd_names {
    if !rest.contains(k) {
      return None
    }
  }
  let out : Array[(String, T)] = []
  for i in 0..<n {
    out.push((xs[i], positional[i]))
  }
  for i, k in kwd_names {
    out.push((k, kwd_values[i]))
  }
  Some(out)
}

// ---------------------------------------------------------------------------
// Result types: what a statement leaves behind

///|
/// Figure 3.1's result: a sequence either returns or assigns a delta.
pub(all) enum ResultType {
  Returns
  Assigns(VarContext)
} derive(Eq, Debug)

///|
pub fn assigns_empty() -> ResultType {
  Assigns(empty_vars())
}

///|
/// `tt` only when both sides say so.
pub fn merge_status(a : Status, b : Status) -> Status {
  if a is TT && b is TT {
    TT
  } else {
    FF
  }
}

///|
/// The merge of two branches' deltas: a name assigned on one side only is
/// present but not definitely assigned.
pub fn merge_delta(d1 : VarContext, d2 : VarContext) -> VarContext {
  let mut out = empty_vars()
  d1.each(fn(k, a) {
    out = out.add(
      k,
      match d2.get(k) {
        Some(b) => merge_status(a, b)
        None => FF
      },
    )
  })
  d2.each(fn(k, b) {
    if !d1.contains(k) {
      out = out.add(k, FF)
    } else {
      ignore(b)
    }
  })
  out
}

///|
/// The merge of a match's or an if's branches. A branch that returns
/// contributes nothing; if every branch returns, so does the whole.
pub fn merge_results(rs : Array[ResultType]) -> ResultType {
  let branches : Array[VarContext] = []
  for r in rs {
    match r {
      Assigns(d) => branches.push(d)
      Returns => ()
    }
  }
  if branches.is_empty() {
    return Returns
  }
  let mut acc = branches[0]
  for i in 1..<branches.length() {
    acc = merge_delta(acc, branches[i])
  }
  Assigns(acc)
}

///|
pub fn override_delta(d1 : VarContext, d2 : VarContext) -> VarContext {
  let mut out = d1
  d2.each(fn(k, v) { out = out.add(k, v) })
  out
}

///|
/// Sequencing: once anything returns, the sequence returns.
pub fn override_results(r1 : ResultType, r2 : ResultType) -> ResultType {
  match (r1, r2) {
    (Returns, _) => Returns
    (_, Returns) => Returns
    (Assigns(a), Assigns(b)) => Assigns(override_delta(a, b))
  }
}

// ---------------------------------------------------------------------------
// Extension: what an import adds to a context

///|
/// Extending prefers a loaded module over a stub of the same module, and
/// merges two loadings of the same module member by member. Anything else is
/// simply replaced.
pub fn extend_entry(a : Entry, b : Entry) -> Entry {
  match (a, b) {
    (ModuleLoaded(qa, ma), ModuleLoaded(qb, mb)) if qa == qb =>
      ModuleLoaded(qa, extend_context(ma, mb))
    (ModuleLoaded(qa, _), ModuleStub(qb)) if qa == qb => a
    _ => b
  }
}

///|
pub fn extend_context(g1 : Context, g2 : Context) -> Context {
  let mut out = g1
  g2.each(fn(x, e) {
    out = out.add(
      x,
      match g1.get(x) {
        Some(old) => extend_entry(old, e)
        None => e
      },
    )
  })
  out
}

// ---------------------------------------------------------------------------
// The predefined modules

///|
/// Figure 2.7's modules, and what each exports.
///
/// `typing` exposes only `Any` here. Figure 2.7 of the spec also lists
/// `Callable`; the reference does not, and the reference is the oracle. The
/// divergence is recorded rather than reconciled, to be revisited when
/// upstream settles it.
pub fn predefined_members(q : String) -> Array[String]? {
  match q {
    "builtins" => Some(["print", "len", "range"])
    "math" =>
      Some([
        "pi", "e", "sqrt", "exp", "log", "sin", "cos", "tan", "floor", "ceil",
      ])
    "sys" => Some(["argv", "exit"])
    "typing" => Some(["Any"])
    "dataclasses" => Some(["dataclass"])
    _ => None
  }
}

///|
pub let predefined_modules : Array[String] = [
  "builtins", "dataclasses", "math", "sys", "typing",
]

///|
/// Every predefined module's members are definitely assigned, and so is
/// `__name__`, which every module has.
pub fn predefined_context(q : String) -> Context {
  let entries : Array[(String, Entry)] = [("__name__", Var(TT))]
  match predefined_members(q) {
    Some(ms) =>
      for m in ms {
        entries.push((m, Var(TT)))
      }
    None => ()
  }
  context_of(entries)
}

///|
/// The fields a class declares, from its declaration.
pub fn own_fields(node : @ast.Stmt) -> Array[String] {
  @analysis.own_fields(node)
}
