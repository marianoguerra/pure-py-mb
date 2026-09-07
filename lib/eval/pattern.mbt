///|
/// Pattern matching: Figure 4.2.
///
/// The rules are narrower than "anything else fails", and the narrowness is
/// deliberate. `eval-pat-list-no` fires when the value is NEITHER a list nor
/// a tuple, or is a list of the wrong length -- so a list pattern against a
/// TUPLE is covered by no rule at all and the run is undefined, while a tuple
/// pattern against an integer is an honest no-match. A literal pattern
/// against a list reaches `eq` between unrelated kinds and is undefined too.
/// The conformance suite has a test for each of the three.
pub fn Interp::match_pattern(
  self : Interp,
  env : Env,
  p : @ast.Pattern,
  v : Value,
) -> MatchResult {
  match p {
    // eval-pat-lit, eval-pat-lit-no, eval-pat-neg-lit, eval-pat-neg-lit-no
    MatchValue(value~, ..) => {
      let literal = match self.eval_expr(value, env) {
        Val(u) => u
        Aborts(_) => return MatchStuck("a literal pattern that aborts")
        Stuck(op) => return MatchStuck(op)
      }
      match @value.eq(literal, v) {
        Some(true) => Match(@value.empty_env())
        Some(false) => NoMatch
        None => MatchStuck("a literal pattern against " + v.kind_name())
      }
    }
    // `None`, `True` and `False` match by identity, which for these three is
    // the same as equality.
    MatchSingleton(value~, ..) => {
      let want : Value = match value {
        None => Value::None
        Bool(b) => Bool(b)
        _ => return MatchStuck("a singleton pattern that is not None or a bool")
      }
      match (want, v) {
        (Value::None, Value::None) => Match(@value.empty_env())
        (Bool(a), Bool(b)) =>
          if a == b {
            Match(@value.empty_env())
          } else {
            NoMatch
          }
        _ => NoMatch
      }
    }
    // eval-pat-var, eval-pat-wild, eval-pat-as
    MatchAs(pattern~, name~, ..) => {
      let inner = match pattern {
        None => MatchResult::Match(@value.empty_env())
        Some(q) => self.match_pattern(env, q, v)
      }
      match name {
        None => inner
        Some(x) => inner.then(Match(@value.env_of([(x, v)])))
      }
    }
    // eval-pat-list / eval-pat-tuple and their no-match rules
    MatchSequence(kind~, patterns~, ..) => {
      let want_list = kind is List
      let elements = match v {
        List(xs) => if want_list { Some(xs) } else { Option::None }
        Tuple(xs) => if want_list { Option::None } else { Some(xs) }
        _ => Some([])
      }
      match v {
        List(_) | Tuple(_) => ()
        // Neither a list nor a tuple: an honest no-match for either bracket.
        _ => return NoMatch
      }
      match elements {
        // A list pattern against a tuple, or the reverse: no rule covers it.
        Option::None =>
          MatchStuck(
            (if want_list { "a list pattern" } else { "a tuple pattern" }) +
            " against " +
            v.kind_name(),
          )
        Some(xs) => {
          if xs.length() != patterns.length() {
            return NoMatch
          }
          let mut result = MatchResult::Match(@value.empty_env())
          for i in 0..<patterns.length() {
            result = result.then(self.match_pattern(env, patterns[i], xs[i]))
          }
          result
        }
      }
    }
    // eval-pat-dict, eval-pat-dict-no
    MatchMapping(keys~, patterns~, ..) =>
      match v {
        Dict(entries) => {
          let mut result = MatchResult::Match(@value.empty_env())
          for i, k in keys {
            let key = match self.eval_expr(k, env) {
              Val(Str(s)) => s
              _ => return MatchStuck("a dict pattern key that is not a string")
            }
            match find(entries, key) {
              Option::None => return NoMatch
              Some(u) =>
                result = result.then(self.match_pattern(env, patterns[i], u))
            }
          }
          result
        }
        _ => NoMatch
      }
    // eval-pat-constr, eval-pat-constr-no
    MatchClass(cls~, patterns~, kwd_attrs~, kwd_patterns~, ..) => {
      let entry = match self.resolve_class(cls, env) {
        Some(c) => c
        None => return MatchStuck("a pattern whose class is not a class")
      }
      match v {
        Obj(actual, fields_env) => {
          // A subclass matches: the pattern's class must be among the
          // object's ancestors, and only the pattern class's fields are bound.
          if !actual.ancestors().iter().any(fn(a) { a.name == entry.name }) {
            return NoMatch
          }
          let mapped = match
            entry.field_map(patterns, kwd_attrs, kwd_patterns) {
            Some(m) => m
            None =>
              return MatchStuck("a constructor pattern of the wrong shape")
          }
          let mut result = MatchResult::Match(@value.empty_env())
          for x in entry.fields() {
            let sub = match lookup_pattern(mapped, x) {
              Some(s) => s
              None => return MatchStuck("a field with no sub-pattern")
            }
            match fields_env.get(x) {
              Some(u) => result = result.then(self.match_pattern(env, sub, u))
              None => return MatchStuck("an object missing one of its fields")
            }
          }
          result
        }
        _ => NoMatch
      }
    }
    _ => MatchStuck("pattern " + p.kind_name())
  }
}

///|
fn find(entries : Array[(String, Value)], key : String) -> Value? {
  for e in entries {
    if e.0 == key {
      return Some(e.1)
    }
  }
  None
}

///|
fn lookup_pattern(
  pairs : Array[(String, @ast.Pattern)],
  key : String,
) -> @ast.Pattern? {
  for p in pairs {
    if p.0 == key {
      return Some(p.1)
    }
  }
  None
}

///|
/// `dispatch(ρ, v, p⃗, s⃗)`: the first case whose pattern matches, with its
/// bindings; no bindings and `pass` if none does.
pub fn Interp::dispatch(
  self : Interp,
  env : Env,
  v : Value,
  cases : Array[@ast.MatchCase],
) -> Dispatch {
  for c in cases {
    match self.match_pattern(env, c.pattern, v) {
      Match(bindings) => return Taken(bindings, c.body)
      NoMatch => ()
      MatchStuck(op) => return DispatchStuck(op)
    }
  }
  FellThrough
}

///|
/// What a match statement does with a value.
pub(all) enum Dispatch {
  Taken(Env, Array[@ast.Stmt])
  FellThrough
  DispatchStuck(String)
}

///|
/// `resolve-class(ρ, q)`: the class a qualified name stands for.
pub fn Interp::resolve_class(
  self : Interp,
  e : @ast.Expr,
  env : Env,
) -> @context.ClassEntry? {
  match e {
    Name(id~, ..) =>
      match env.get(id) {
        Some(Class(c)) => Some(c)
        _ => None
      }
    Attribute(value~, attr~, ..) =>
      match self.eval_expr(value, env) {
        Val(Mod(_, members)) =>
          match members.get(attr) {
            Some(Class(c)) => Some(c)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}
