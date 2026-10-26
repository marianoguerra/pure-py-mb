///|
/// The syntactic analyses of Annex A.1: what a statement assigns, what it
/// binds, what it captures, and where its free variables are.
///
/// A port of the reference's `aux.py`, function for function, so that the two
/// can be read side by side. Two things carry over deliberately:
///
///   * **Sets are sorted.** The reference uses Python's `set` and then `min`
///     or `sorted` wherever the choice is observable, so no order is ever
///     accidental. Sorted sets here make that structural rather than a habit.
///   * **A mutual region is formed on the fly.** `statements` groups a run of
///     consecutive `def`s into one item, and nothing in the tree records it.
///     The evaluator groups the same way, from the same function.
pub type NameSet = @sorted_set.SortedSet[String]

///|
pub let empty : NameSet = @sorted_set.SortedSet::new()

///|
pub fn names(xs : Array[String]) -> NameSet {
  @sorted_set.SortedSet::from_iter(xs.iter())
}

///|
/// A PurePy statement: a Python statement, or a mutual region of consecutive
/// function definitions. A Python body is the spec's right-nested sequence.
pub(all) enum Statement {
  Single(@ast.Stmt)
  Region(Array[@ast.Stmt])
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// Imports

///|
pub fn is_import(s : @ast.Stmt) -> Bool {
  s is (Import(..) | ImportFrom(..))
}

///|
/// The leading run of imports, and everything after it.
pub fn split_imports(
  body : Array[@ast.Stmt],
) -> (Array[@ast.Stmt], Array[@ast.Stmt]) {
  let mut i = 0
  while i < body.length() && is_import(body[i]) {
    i += 1
  }
  (body[:i].to_owned(), body[i:].to_owned())
}

///|
/// The first import anywhere in a list, for the "imports must precede all
/// other statements" check.
pub fn find_import(stmts : Array[@ast.Stmt]) -> @ast.Stmt? {
  for s in stmts {
    if is_import(s) {
      return Some(s)
    }
  }
  None
}

///|
/// The first import inside a function, a branch or a case body -- which is
/// where an import is not allowed at all.
pub fn find_nested_import(
  stmts : Array[@ast.Stmt],
  nested~ : Bool = false,
) -> @ast.Stmt? {
  for s in stmts {
    if nested && is_import(s) {
      return Some(s)
    }
    match s {
      FunctionDef(body~, ..) =>
        match find_nested_import(body, nested=true) {
          Some(r) => return Some(r)
          None => ()
        }
      If(body~, or_else~, ..) => {
        match find_nested_import(body, nested=true) {
          Some(r) => return Some(r)
          None => ()
        }
        match find_nested_import(or_else, nested=true) {
          Some(r) => return Some(r)
          None => ()
        }
      }
      Match(cases~, ..) =>
        for c in cases {
          match find_nested_import(c.body, nested=true) {
            Some(r) => return Some(r)
            None => ()
          }
        }
      _ => ()
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Mutual regions

///|
/// Group a body into statements: a run of consecutive `def`s is one region.
pub fn statements(body : Array[@ast.Stmt]) -> Array[Statement] {
  let out : Array[Statement] = []
  let mut i = 0
  while i < body.length() {
    if body[i] is FunctionDef(..) {
      let region : Array[@ast.Stmt] = []
      while i < body.length() && body[i] is FunctionDef(..) {
        region.push(body[i])
        i += 1
      }
      out.push(Region(region))
    } else {
      out.push(Single(body[i]))
      i += 1
    }
  }
  out
}

// ---------------------------------------------------------------------------
// What a pattern binds

///|
/// In source order, with repeats: the linearity check counts them.
pub fn binds_seq(p : @ast.Pattern) -> Array[String] {
  match p {
    MatchValue(..) | MatchSingleton(..) => []
    MatchAs(pattern~, name~, ..) => {
      let out : Array[String] = match pattern {
        Some(q) => binds_seq(q)
        None => []
      }
      match name {
        Some(n) => out.push(n)
        None => ()
      }
      out
    }
    MatchSequence(patterns~, ..) | MatchMapping(patterns~, ..) => {
      let out : Array[String] = []
      for q in patterns {
        for n in binds_seq(q) {
          out.push(n)
        }
      }
      out
    }
    MatchClass(patterns~, kwd_patterns~, ..) => {
      let out : Array[String] = []
      for q in patterns {
        for n in binds_seq(q) {
          out.push(n)
        }
      }
      for q in kwd_patterns {
        for n in binds_seq(q) {
          out.push(n)
        }
      }
      out
    }
    MatchStar(..) | MatchOr(..) =>
      abort("unreachable after the sieve: " + p.kind_name())
  }
}

///|
pub fn binds(p : @ast.Pattern) -> NameSet {
  names(binds_seq(p))
}

// ---------------------------------------------------------------------------
// Free variables

///|
pub fn fv_e(e : @ast.Expr) -> NameSet {
  match e {
    Name(id~, ..) => @sorted_set.SortedSet::singleton(id)
    Constant(..) => empty
    Lambda(args~, body~, ..) => fv_e(body).difference(param_names(args))
    Call(func~, args~, keywords~, ..) =>
      fv_e(func)
      .union(fv_e_list(args))
      .union(fv_e_list(keywords.map(fn(k) { k.value })))
    BinOp(left~, right~, ..) => fv_e(left).union(fv_e(right))
    UnaryOp(operand~, ..) => fv_e(operand)
    BoolOp(values~, ..) => fv_e_list(values)
    Compare(left~, comparators~, ..) => fv_e(left).union(fv_e_list(comparators))
    IfExp(cond~, body~, or_else~, ..) =>
      fv_e(cond).union(fv_e(body)).union(fv_e(or_else))
    Attribute(value~, ..) => fv_e(value)
    Subscript(value~, slice~, ..) => fv_e(value).union(fv_e(slice))
    List(elts~, ..) | Tuple(elts~, ..) => fv_e_list(elts)
    Dict(keys~, values~, ..) =>
      fv_e_list(present(keys)).union(fv_e_list(values))
    ListComp(elt~, generators~, ..) => fv_e_comprehension([elt], generators)
    DictComp(key~, value~, generators~, ..) =>
      fv_e_comprehension([key, value], generators)
    // A slice's bounds are expressions like any other, and an omitted one
    // names nothing. Reached only under a profile that opens slicing (#59);
    // under `core` the sieve takes this node before anyone asks.
    Slice(lower~, upper~, step~, ..) => fv_e_list(present([lower, upper, step]))
    // An f-string's holes are expressions, and they name what they name:
    // `f"{x}"` reads `x` exactly as `x` does (#55).
    JoinedStr(parts~, ..) => fv_e_list(hole_values(parts))
    _ => abort("unreachable after the sieve: " + e.kind_name())
  }
}

///|
fn present(keys : Array[@ast.Expr?]) -> Array[@ast.Expr] {
  let out : Array[@ast.Expr] = []
  for k in keys {
    match k {
      Some(e) => out.push(e)
      None => ()
    }
  }
  out
}

///|
fn param_names(a : @ast.Arguments) -> NameSet {
  names(a.args.map(fn(p) { p.arg }))
}

///|
pub fn fv_e_list(es : Array[@ast.Expr]) -> NameSet {
  let mut acc = empty
  for e in es {
    acc = acc.union(fv_e(e))
  }
  acc
}

///|
/// A comprehension binds its targets for the clauses AFTER it and for the
/// element, but not for its own iterable.
fn fv_e_comprehension(
  elts : Array[@ast.Expr],
  generators : ArrayView[@ast.Comprehension],
) -> NameSet {
  if generators.is_empty() {
    return fv_e_list(elts)
  }
  let g = generators[0]
  let rest = fv_e_list(g.ifs).union(fv_e_comprehension(elts, generators[1:]))
  fv_e(g.iter).union(rest.difference(names_in_target(g.target)))
}

///|
pub fn names_in_target(target : @ast.Expr) -> NameSet {
  match target {
    Name(id~, ..) => @sorted_set.SortedSet::singleton(id)
    Tuple(elts~, ..) => {
      let mut acc = empty
      for t in elts {
        acc = acc.union(names_in_target(t))
      }
      acc
    }
    _ => empty
  }
}

///|
pub fn fv_stmt(s : @ast.Stmt) -> NameSet {
  match s {
    Pass(..) => empty
    Assign(value~, ..) => fv_e(value)
    AnnAssign(value~, ..) =>
      match value {
        Some(v) => fv_e(v)
        None => empty
      }
    ExprStmt(value~, ..) => fv_e(value)
    Return(value~, ..) =>
      match value {
        Some(v) => fv_e(v)
        None => empty
      }
    Assert(cond~, msg~, ..) => {
      let mut acc = fv_e(cond)
      match msg {
        Some(m) => acc = acc.union(fv_e(m))
        None => ()
      }
      acc
    }
    If(cond~, body~, or_else~, ..) =>
      fv_e(cond).union(fv_body(body)).union(fv_body(or_else))
    Match(subject~, cases~, ..) => {
      let mut acc = fv_e(subject)
      for c in cases {
        acc = acc.union(fv_body(c.body).difference(binds(c.pattern)))
      }
      acc
    }
    // Parameters and variables assigned in the body are local to the function.
    FunctionDef(name~, args~, body~, ..) =>
      fv_body(body)
      .difference(param_names(args))
      .difference(assigns_body(body))
      .difference(@sorted_set.SortedSet::singleton(name))
    ClassDef(..) => empty
    _ => abort("unreachable after the sieve: " + s.kind_name())
  }
}

///|
pub fn fv_body(body : Array[@ast.Stmt]) -> NameSet {
  let mut acc = empty
  for s in body {
    acc = acc.union(fv_stmt(s))
  }
  acc
}

// ---------------------------------------------------------------------------
// What a statement assigns

///|
pub fn assigns_stmt(s : @ast.Stmt) -> NameSet {
  match s {
    Pass(..) | ExprStmt(..) | Return(..) | Assert(..) => empty
    Assign(targets~, ..) => {
      let out : Array[String] = []
      for t in targets {
        for id in target_names(t) {
          out.push(id)
        }
      }
      names(out)
    }
    AnnAssign(target~, ..) => names(target_names(target))
    If(body~, or_else~, ..) => assigns_body(body).union(assigns_body(or_else))
    Match(cases~, ..) => {
      let mut acc = empty
      for c in cases {
        acc = acc.union(binds(c.pattern)).union(assigns_body(c.body))
      }
      acc
    }
    FunctionDef(name~, ..) | ClassDef(name~, ..) =>
      @sorted_set.SortedSet::singleton(name)
    TypeAlias(name=Name(id~, ..), ..) => @sorted_set.SortedSet::singleton(id)
    _ => abort("unreachable after the sieve: " + s.kind_name())
  }
}

///|
pub fn assigns_body(body : Array[@ast.Stmt]) -> NameSet {
  let mut acc = empty
  for s in body {
    acc = acc.union(assigns_stmt(s))
  }
  acc
}

// ---------------------------------------------------------------------------
// What a statement captures
//
// A name is CAPTURED when a closure closes over it: reassigning it afterwards
// would change what that closure sees, and PurePy forbids exactly that.

///|
pub fn captures_e(e : @ast.Expr) -> NameSet {
  match e {
    Lambda(args~, body~, ..) => fv_e(body).difference(param_names(args))
    Name(..) | Constant(..) => empty
    Call(func~, args~, keywords~, ..) =>
      captures_e(func)
      .union(captures_e_list(args))
      .union(captures_e_list(keywords.map(fn(k) { k.value })))
    BinOp(left~, right~, ..) => captures_e(left).union(captures_e(right))
    UnaryOp(operand~, ..) => captures_e(operand)
    BoolOp(values~, ..) => captures_e_list(values)
    Compare(left~, comparators~, ..) =>
      captures_e(left).union(captures_e_list(comparators))
    IfExp(cond~, body~, or_else~, ..) =>
      captures_e(cond).union(captures_e(body)).union(captures_e(or_else))
    Attribute(value~, ..) => captures_e(value)
    Subscript(value~, slice~, ..) => captures_e(value).union(captures_e(slice))
    List(elts~, ..) | Tuple(elts~, ..) => captures_e_list(elts)
    Dict(keys~, values~, ..) =>
      captures_e_list(present(keys)).union(captures_e_list(values))
    ListComp(elt~, generators~, ..) =>
      captures_quals(generators[:]).union(
        captures_e(elt).difference(binds_quals(generators)),
      )
    DictComp(key~, value~, generators~, ..) =>
      captures_quals(generators[:]).union(
        captures_e(key)
        .union(captures_e(value))
        .difference(binds_quals(generators)),
      )
    Slice(lower~, upper~, step~, ..) =>
      captures_e_list(present([lower, upper, step]))
    JoinedStr(parts~, ..) => captures_e_list(hole_values(parts))
    _ => abort("unreachable after the sieve: " + e.kind_name())
  }
}

///|
pub fn captures_e_list(es : Array[@ast.Expr]) -> NameSet {
  let mut acc = empty
  for e in es {
    acc = acc.union(captures_e(e))
  }
  acc
}

///|
fn captures_quals(generators : ArrayView[@ast.Comprehension]) -> NameSet {
  if generators.is_empty() {
    return empty
  }
  let g = generators[0]
  let rest = captures_e_list(g.ifs).union(captures_quals(generators[1:]))
  captures_e(g.iter).union(rest.difference(names_in_target(g.target)))
}

///|
pub fn binds_quals(generators : Array[@ast.Comprehension]) -> NameSet {
  let mut acc = empty
  for g in generators {
    acc = acc.union(names_in_target(g.target))
  }
  acc
}

///|
pub fn captures(s : @ast.Stmt) -> NameSet {
  match s {
    Pass(..) => empty
    Assign(value~, ..) => captures_e(value)
    AnnAssign(value~, ..) =>
      match value {
        Some(v) => captures_e(v)
        None => empty
      }
    ExprStmt(value~, ..) => captures_e(value)
    Return(value~, ..) =>
      match value {
        Some(v) => captures_e(v)
        None => empty
      }
    Assert(cond~, msg~, ..) => {
      let mut acc = captures_e(cond)
      match msg {
        Some(m) => acc = acc.union(captures_e(m))
        None => ()
      }
      acc
    }
    If(cond~, body~, or_else~, ..) =>
      captures_e(cond).union(captures_body(body)).union(captures_body(or_else))
    // A pattern variable is in the function's scope, so a capture of it
    // counts.
    Match(subject~, cases~, ..) => {
      let mut acc = captures_e(subject)
      for c in cases {
        acc = acc.union(captures_body(c.body))
      }
      acc
    }
    FunctionDef(..) => captures_region([s])
    ClassDef(..) => empty
    _ => abort("unreachable after the sieve: " + s.kind_name())
  }
}

///|
pub fn captures_body(body : Array[@ast.Stmt]) -> NameSet {
  let mut acc = empty
  for s in body {
    acc = acc.union(captures(s))
  }
  acc
}

///|
/// What a whole mutual region captures: the free names of every body, less the
/// parameters, less what each body assigns for itself, less the region's own
/// names -- which is what lets `even` and `odd` name each other.
pub fn captures_region(defs : Array[@ast.Stmt]) -> NameSet {
  let f_names = names(defs.map(fn(d) { def_name(d) }))
  let mut acc = empty
  for d in defs {
    match d {
      FunctionDef(args~, body~, ..) =>
        acc = acc.union(
          fv_body(body)
          .difference(param_names(args))
          .difference(assigns_body(body)),
        )
      _ => ()
    }
  }
  acc.difference(f_names)
}

///|
fn def_name(d : @ast.Stmt) -> String {
  match d {
    FunctionDef(name~, ..) => name
    _ => abort("a mutual region holds only function definitions")
  }
}

///|
pub fn captures_statement(item : Statement) -> NameSet {
  match item {
    Single(s) => captures(s)
    Region(defs) => captures_region(defs)
  }
}

///|
pub fn assigns_statement(item : Statement) -> NameSet {
  match item {
    Single(s) => assigns_stmt(s)
    Region(defs) => names(defs.map(fn(d) { def_name(d) }))
  }
}

///|
pub fn assigns_seq(items : ArrayView[Statement]) -> NameSet {
  let mut acc = empty
  for item in items {
    acc = acc.union(assigns_statement(item))
  }
  acc
}

///|
/// The first statement in a sequence that assigns any of `names_` -- the one a
/// captured-then-reassigned message points at. For a region it is the region's
/// first definition, as the reference reports.
pub fn find_first_reassigning(
  items : ArrayView[Statement],
  names_ : NameSet,
) -> @ast.Stmt? {
  for item in items {
    if !assigns_statement(item).intersection(names_).is_empty() {
      return Some(
        match item {
          Single(s) => s
          Region(defs) => defs[0]
        },
      )
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Classes and qualified names

///|
/// The fields a class declares itself, in declaration order.
pub fn own_fields(node : @ast.Stmt) -> Array[String] {
  match node {
    ClassDef(body~, ..) => {
      let out : Array[String] = []
      for s in body {
        match s {
          AnnAssign(target=Name(id~, ..), ..) => out.push(id)
          _ => ()
        }
      }
      out
    }
    _ => []
  }
}

///|
/// `a`, `a.b`, `a.b.c` as text.
pub fn qualified_name(e : @ast.Expr) -> String {
  match e {
    Name(id~, ..) => id
    Attribute(value~, attr~, ..) => qualified_name(value) + "." + attr
    _ => abort("not a qualified name")
  }
}

///|
pub fn is_qualified_name(e : @ast.Expr) -> Bool {
  match e {
    Name(..) => true
    Attribute(value~, ..) => is_qualified_name(value)
    _ => false
  }
}

///|
/// What a run of comprehension clauses captures, for a caller that has a whole
/// array rather than a view.
pub fn captures_quals_of(generators : Array[@ast.Comprehension]) -> NameSet {
  captures_quals(generators[:])
}

///|
/// The names an assignment target binds.
///
/// A plain `x` binds one. A destructuring target -- `a, b = ...`, or the
/// nested `a, (b, c) = ...` -- binds the leaves of the tuple, and Python lets
/// a list stand where a tuple does. Anything else binds nothing: the sieve has
/// already refused item and attribute assignment, so nothing else reaches
/// here, and answering with the empty set rather than aborting keeps this
/// usable by the sieve itself.
///
/// One definition, because the checker's definite-assignment table, the
/// evaluator's environment and `assigns_stmt` have to agree about what `a, b
/// = f()` assigned or the three disagree about whether `b` exists.
pub fn target_names(e : @ast.Expr) -> Array[String] {
  let out : Array[String] = []
  fn walk(t : @ast.Expr) -> Unit {
    match t {
      Name(id~, ..) => out.push(id)
      Tuple(elts~, ..) | List(elts~, ..) =>
        for x in elts {
          walk(x)
        }
      _ => ()
    }
  }

  walk(e)
  out
}

///|
/// The expressions inside an f-string's holes, in source order.
pub fn hole_values(parts : Array[@ast.FStringPart]) -> Array[@ast.Expr] {
  let out : Array[@ast.Expr] = []
  for part in parts {
    match part {
      Hole(value~, ..) => out.push(value)
      Text(_) => ()
    }
  }
  out
}

///|
#deprecated(skip_current_package=true)
#doc(hidden)
pub extend Statement with Eq::{not_equal, equal}

///|
#deprecated(skip_current_package=true)
#doc(hidden)
pub extend Statement with Debug::{to_repr}

// ---------------------------------------------------------------------------
// Declarations (v0.17)

///|
/// The names a statement DECLARES, or an import binds, each with its
/// statement, in textual order and with repeats: an annotated assignment, a
/// `def`, a class, an import -- and whatever the branches of an `if` or the
/// cases of a `match` declare. Not descending into a `def`'s body.
pub fn declares(s : @ast.Stmt) -> Array[(String, @ast.Stmt)] {
  match s {
    AnnAssign(target=Name(id~, ..), ..) => [(id, s)]
    If(body~, or_else~, ..) => [..declares_body(body), ..declares_body(or_else)]
    Match(cases~, ..) => {
      let out = []
      for c in cases {
        out.append(declares_body(c.body))
      }
      out
    }
    FunctionDef(name~, ..) | ClassDef(name~, ..) => [(name, s)]
    TypeAlias(name=Name(id~, ..), ..) => [(id, s)]
    Import(names~, ..) =>
      [
        (
          match names[0].name.split_once(".") {
            Some((head, _)) => head.to_owned()
            None => names[0].name
          },
          s,
        ),
      ]
    ImportFrom(names~, ..) => names.map(fn(a) { (a.name, s) })
    _ => []
  }
}

///|
pub fn declares_body(body : Array[@ast.Stmt]) -> Array[(String, @ast.Stmt)] {
  let out = []
  for s in body {
    out.append(declares(s))
  }
  out
}

///|
/// The targets of the UNANNOTATED assignments in a body, each with its
/// statement, in textual order, not descending into a `def`. A destructuring
/// target, under a profile that has one, contributes each of its names.
pub fn assign_targets(body : Array[@ast.Stmt]) -> Array[(String, @ast.Stmt)] {
  let out = []
  for s in body {
    match s {
      Assign(targets~, ..) if targets.length() == 1 =>
        for x in target_names(targets[0]) {
          out.push((x, s))
        }
      If(body=a, or_else=b, ..) => {
        out.append(assign_targets(a))
        out.append(assign_targets(b))
      }
      Match(cases~, ..) =>
        for c in cases {
          out.append(assign_targets(c.body))
        }
      _ => ()
    }
  }
  out
}

///|
/// The variables the patterns of a body's `match` statements bind, each with
/// the first `match` that binds it, in the order they are first met. Not
/// descending into a `def`.
pub fn pattern_bound(body : Array[@ast.Stmt]) -> Array[(String, @ast.Stmt)] {
  let out : Array[(String, @ast.Stmt)] = []
  let add = fn(x : String, m : @ast.Stmt) {
    if !out.iter().any(fn(p) { p.0 == x }) {
      out.push((x, m))
    }
  }
  for s in body {
    match s {
      If(body=a, or_else=b, ..) => {
        for p in pattern_bound(a) {
          add(p.0, p.1)
        }
        for p in pattern_bound(b) {
          add(p.0, p.1)
        }
      }
      Match(cases~, ..) =>
        for c in cases {
          for x in binds_seq(c.pattern) {
            add(x, s)
          }
          for p in pattern_bound(c.body) {
            add(p.0, p.1)
          }
        }
      _ => ()
    }
  }
  out
}
