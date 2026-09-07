///|
/// Pattern well-formedness, subsumption and linearity: Figures 3.3 and 3.4.
///
/// A port of the reference's `patterns.py`.
using @ast {type Pattern, type Expr}

///|
type Ctx = @context.ModuleContext[Program]

///|
/// A pattern that matches everything and looks at nothing: `_`, or a bare
/// capture. Used to decide whether a match is exhaustive.
pub fn is_catch_all(p : Pattern) -> Bool {
  p is MatchAs(pattern=None, ..)
}

///|
/// The value a literal pattern stands for, as a constant. A negated literal
/// is folded here, so that `-1` and `-1` compare equal and `-0` equals `0`.
fn literal_value(p : Pattern) -> @ast.Constant {
  match p {
    MatchValue(value=Constant(value~, ..), ..) => value
    MatchValue(value=UnaryOp(op~, operand=Constant(value~, ..), ..), ..) =>
      if op is USub {
        negate(value)
      } else {
        value
      }
    _ => abort("unexpected MatchValue payload")
  }
}

///|
fn negate(c : @ast.Constant) -> @ast.Constant {
  match c {
    Int(n) => Int(-n)
    Float(d) => Float(-d)
    other => other
  }
}

///|
/// Python's `==` between two literal pattern values.
///
/// The one case that matters and is easy to miss: `1 == 1.0` is True in
/// Python, so `case 1:` subsumes `case 1.0:`. Everything else compares within
/// its own kind.
fn literal_eq(a : @ast.Constant, b : @ast.Constant) -> Bool {
  match (a, b) {
    (Int(x), Int(y)) => x == y
    (Float(x), Float(y)) => x == y
    (Int(x), Float(y)) | (Float(y), Int(x)) => big_eq_double(x, y)
    (Str(x), Str(y)) => x == y
    _ => false
  }
}

///|
/// An integer and a float compare EXACTLY in Python: `2 ** 53 + 1` is not
/// equal to the double nearest it, and `1 == 1.0` is. So the double is turned
/// into the integer it exactly is, when it is one, and compared there.
fn big_eq_double(n : BigInt, d : Double) -> Bool {
  match exact_integer(d) {
    Some(m) => m == n
    None => false
  }
}

///|
/// The integer a double exactly equals, or `None` when it is not an integer.
///
/// Read off the bit pattern rather than through any decimal text, so it is
/// exact at every magnitude: a double is `mantissa * 2^exponent`, and when it
/// is integral the shift below loses nothing.
pub fn exact_integer(d : Double) -> BigInt? {
  if d.is_nan() || d.is_inf() || d != d.floor() {
    return None
  }
  let bits = d.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent = ((bits >> 52) & 0x7FFUL).to_int()
  let fraction = bits & 0xFFFFFFFFFFFFFUL
  let (mantissa, shift) = if exponent == 0 {
    (fraction, -1074)
  } else {
    (fraction | (1UL << 52), exponent - 1075)
  }
  let mut n = BigInt::from_uint64(mantissa)
  if shift > 0 {
    n = n << shift
  } else if shift < 0 {
    n = n >> -shift
  }
  Some(if negative { -n } else { n })
}

///|
/// A dict pattern's key. The sieve has already insisted it is a string.
fn dict_key(k : Expr) -> String {
  match k {
    Constant(value=Str(s), ..) => s
    _ => abort("a dict pattern key must be a string literal")
  }
}

///|
/// Whether every value `q` matches is a value `p` matches -- so a case after
/// `p` written with `q` can never run.
pub fn subsumes(p : Pattern, q : Pattern, ctx : Ctx) -> Bool {
  // Peel the `as` off either side: it binds a name and matches whatever its
  // inner pattern matches.
  match q {
    MatchAs(pattern=Some(inner), ..) => return subsumes(p, inner, ctx)
    _ => ()
  }
  match p {
    MatchAs(pattern=Some(inner), ..) => return subsumes(inner, q, ctx)
    _ => ()
  }
  // A bare capture matches everything, so nothing but a catch-all subsumes it.
  if q is MatchAs(pattern=None, ..) {
    return true
  }
  match (p, q) {
    (MatchValue(..), MatchValue(..)) =>
      literal_eq(literal_value(p), literal_value(q))
    // `None`, `True` and `False` match by identity.
    (MatchSingleton(value=a, ..), MatchSingleton(value=b, ..)) => a == b
    (
      MatchMapping(keys=pk, patterns=pp, ..),
      MatchMapping(keys=qk, patterns=qp, ..),
    ) => {
      // `p` subsumes `q` when `p` demands no more keys than `q` does and its
      // sub-patterns subsume `q`'s on every key `q` names.
      let pm = keyed(pk, pp)
      for i, k in qk {
        match lookup(pm, dict_key(k)) {
          None => return false
          Some(sub) => if !subsumes(sub, qp[i], ctx) { return false }
        }
      }
      true
    }
    (
      MatchSequence(kind=pkind, patterns=pp, ..),
      MatchSequence(kind=qkind, patterns=qp, ..),
    ) => {
      // A list pattern and a tuple pattern match disjoint sets of values, so
      // neither subsumes the other -- which is why the bracket is recorded.
      if pkind != qkind || pp.length() != qp.length() {
        return false
      }
      for i in 0..<pp.length() {
        if !subsumes(pp[i], qp[i], ctx) {
          return false
        }
      }
      true
    }
    (
      MatchClass(cls=pc, patterns=pp, kwd_attrs=pa, kwd_patterns=pkp, ..),
      MatchClass(cls=qc, patterns=qp, kwd_attrs=qa, kwd_patterns=qkp, ..),
    ) => {
      let cp = @context.class_entry(pc, ctx)
      let cq = @context.class_entry(qc, ctx)
      match (cp, cq) {
        (Some(cp), Some(cq)) => {
          // `p`'s class must be `q`'s class or a subclass of it.
          if !cp.ancestors().iter().any(fn(a) { a.name == cq.name }) {
            return false
          }
          let map_p = cp.field_map(pp, pa, pkp)
          let map_q = cq.field_map(qp, qa, qkp)
          match (map_p, map_q) {
            (Some(mp), Some(mq)) => {
              for x in cq.fields() {
                match (lookup(mp, x), lookup(mq, x)) {
                  (Some(a), Some(b)) => if !subsumes(a, b, ctx) { return false }
                  _ => return false
                }
              }
              true
            }
            _ => false
          }
        }
        _ => false
      }
    }
    _ => false
  }
}

///|
fn keyed(
  keys : Array[Expr],
  patterns : Array[Pattern],
) -> Array[(String, Pattern)] {
  let out : Array[(String, Pattern)] = []
  for i, k in keys {
    out.push((dict_key(k), patterns[i]))
  }
  out
}

///|
fn[T] lookup(pairs : Array[(String, T)], key : String) -> T? {
  for pair in pairs {
    if pair.0 == key {
      return Some(pair.1)
    }
  }
  None
}

///|
/// One pattern: known class, right arity, no repeated keyword, no repeated
/// dictionary key.
pub fn check_pattern(p : Pattern, ctx : Ctx) -> Unit raise {
  match p {
    MatchClass(cls~, patterns~, kwd_attrs~, kwd_patterns~, span~) => {
      let entry = match @context.class_entry(cls, ctx) {
        Some(e) => e
        None =>
          raise @err.ill_formed(
            UnknownClassInPattern(
              cls=if @analysis.is_qualified_name(cls) {
                @analysis.qualified_name(cls)
              } else {
                @write.unparse_expr(cls)
              },
            ),
            span~,
          )
      }
      let c_name = entry.short_name()
      let xs = entry.fields()
      if entry.field_map(patterns, kwd_attrs, kwd_patterns) is None {
        let n = patterns.length()
        if n + kwd_attrs.length() != xs.length() {
          raise @err.ill_formed(
            PatternArityMismatch(
              cls=c_name,
              expected=xs.length(),
              got=n + kwd_attrs.length(),
            ),
            span~,
          )
        }
        if has_duplicate(kwd_attrs) {
          raise @err.ill_formed(DuplicatePatternKeyword(cls=c_name), span~)
        }
        raise @err.ill_formed(
          UnknownFieldInPattern(
            cls=c_name,
            expected_fields=sorted_unique(xs[n:]),
          ),
          span~,
        )
      }
      for sub in patterns {
        check_pattern(sub, ctx)
      }
      for sub in kwd_patterns {
        check_pattern(sub, ctx)
      }
    }
    MatchSequence(patterns~, ..) =>
      for sub in patterns {
        check_pattern(sub, ctx)
      }
    MatchMapping(keys~, patterns~, span~, ..) => {
      let seen : Array[String] = []
      for k in keys {
        let key = dict_key(k)
        if seen.contains(key) {
          raise @err.ill_formed(DuplicateDictKey(key~), span~)
        }
        seen.push(key)
      }
      for sub in patterns {
        check_pattern(sub, ctx)
      }
    }
    MatchAs(pattern=Some(inner), ..) => check_pattern(inner, ctx)
    _ => ()
  }
}

///|
fn has_duplicate(names : Array[String]) -> Bool {
  let seen : Array[String] = []
  for n in names {
    if seen.contains(n) {
      return true
    }
    seen.push(n)
  }
  false
}

///|
fn sorted_unique(names : ArrayView[String]) -> Array[String] {
  let out : Array[String] = []
  for n in names {
    if !out.contains(n) {
      out.push(n)
    }
  }
  @basic.sort_names(out)
  out
}

///|
/// A match's cases: each pattern well formed and linear, and none subsumed by
/// an earlier one. The error points at the MATCH statement, not the case,
/// because a `match_case` carries no position.
pub fn check_pattern_list(
  patterns : Array[Pattern],
  span : @basic.Span,
  ctx : Ctx,
) -> Unit raise {
  for i, p in patterns {
    check_pattern(p, ctx)
    let vars_ = @analysis.binds_seq(p)
    if has_duplicate(vars_) {
      raise @err.ill_formed(NonlinearPattern(index=i + 1), span~)
    }
    for j in 0..<i {
      if subsumes(p, patterns[j], ctx) {
        raise @err.ill_formed(
          UnreachableCase(index=i + 1, subsumed_by=j + 1),
          span~,
        )
      }
    }
  }
}
