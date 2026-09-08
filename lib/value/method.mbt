///|
/// The non-mutating methods of the builtin types, which a profile opens.
///
/// PurePy has no methods at all, and that absence is load-bearing: the
/// evaluator's attribute rule has no case for a builtin value, which is what
/// makes `xs.append(1)` unreachable and therefore what makes a list immutable.
/// A profile that added methods carelessly would take that away.
///
/// It cannot, and the reason is worth stating rather than trusting. A `Value`
/// is an immutable enum with no identity. A method here is a function from a
/// receiver and some arguments to a NEW value; there is no cell to write to
/// and no aliasing that could observe a write, so `append` cannot be
/// implemented as mutation even by mistake. The tables below are `match name`
/// with a `_ => None` default, so the mutating half of Python's API --
/// `append`, `extend`, `insert`, `pop`, `remove`, `sort`, `reverse`, `clear`,
/// `update`, `setdefault` -- is absent rather than denied, and absent means
/// the same `Stuck` an unknown attribute has always produced.
///
/// One trap, written down because the names are one letter apart: `sorted(xs)`
/// answers a new list and `xs.sort()` mutates. The builtin is a profile away;
/// the method never will be.
///
/// `None` means "no such method". The caller turns it into the message an
/// unknown attribute already has, so a typo reads the same as it always did.

///|
/// `s.upper()`, `s.split(",")`, and the rest of `str`.
pub fn str_method(
  recv : String,
  name : String,
  args : Array[Value],
) -> Outcome? {
  match (name, args) {
    ("upper", []) => Some(Val(Str(recv.to_upper())))
    ("lower", []) => Some(Val(Str(recv.to_lower())))
    ("strip", []) => Some(Val(Str(recv.trim().to_owned())))
    ("lstrip", []) =>
      Some(Val(Str(recv.trim_start(chars=" \t\n\r").to_owned())))
    ("rstrip", []) => Some(Val(Str(recv.trim_end(chars=" \t\n\r").to_owned())))
    ("startswith", [Str(p)]) => Some(Val(Bool(recv.has_prefix(p))))
    ("endswith", [Str(p)]) => Some(Val(Bool(recv.has_suffix(p))))
    ("replace", [Str(a), Str(b)]) =>
      Some(Val(Str(recv.replace_all(old=a, new=b))))
    ("split", [Str(sep)]) =>
      if sep.is_empty() {
        // Python raises ValueError, which PurePy does not model.
        Some(Stuck("splitting on an empty separator"))
      } else {
        Some(Val(List(split_on(recv, sep).map(fn(t) { Value::Str(t) }))))
      }
    // `s.split()` with no argument splits on runs of whitespace and drops the
    // empty pieces, which is a different rule and not a default argument.
    ("split", []) =>
      Some(Val(List(split_space(recv).map(fn(t) { Value::Str(t) }))))
    ("join", [xs]) =>
      match elems(xs) {
        None => Some(Aborts(TypeError))
        Some(parts) => {
          let out : Array[String] = []
          for x in parts {
            match x {
              Str(t) => out.push(t)
              _ => return Some(Aborts(TypeError))
            }
          }
          Some(Val(Str(out.join(recv))))
        }
      }
    ("count", [Str(t)]) => Some(Val(Int(BigInt::from_int(count_of(recv, t)))))
    ("find", [Str(t)]) => Some(Val(Int(BigInt::from_int(index_of(recv, t)))))
    ("index", [Str(t)]) => {
      let i = index_of(recv, t)
      // `find` answers -1 and `index` raises. Python's is a ValueError; the
      // nearest thing PurePy models is nothing, so this is undefined.
      Some(
        if i < 0 {
          Stuck("index of a substring that is not there")
        } else {
          Val(Int(BigInt::from_int(i)))
        },
      )
    }
    ("isdigit", []) =>
      Some(Val(Bool(all_chars(recv, fn(c) { c >= '0' && c <= '9' }))))
    ("isalpha", []) =>
      Some(
        Val(
          Bool(
            all_chars(recv, fn(c) {
              (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            }),
          ),
        ),
      )
    ("isspace", []) =>
      Some(
        Val(
          Bool(
            all_chars(recv, fn(c) {
              c == ' ' || c == '\t' || c == '\n' || c == '\r'
            }),
          ),
        ),
      )
    _ => None
  }
}

///|
/// `xs.index(x)`, `xs.count(x)`: what a list and a tuple share, which is
/// everything about them that does not mutate.
pub fn seq_method(
  recv : Array[Value],
  name : String,
  args : Array[Value],
) -> Outcome? {
  match (name, args) {
    ("count", [x]) => {
      let mut n = 0
      for y in recv {
        match eq(x, y) {
          Some(true) => n += 1
          Some(false) => ()
          // `eq` is partial on purpose, and a count that skipped the pairs it
          // does not cover would be answering a different question.
          None =>
            return Some(
              Stuck("counting " + x.kind_name() + " among " + y.kind_name()),
            )
        }
      }
      Some(Val(Int(BigInt::from_int(n))))
    }
    ("index", [x]) => {
      for i, y in recv {
        match eq(x, y) {
          Some(true) => return Some(Val(Int(BigInt::from_int(i))))
          Some(false) => ()
          None =>
            return Some(
              Stuck("comparing " + x.kind_name() + " with " + y.kind_name()),
            )
        }
      }
      Some(Stuck("index of an element that is not there"))
    }
    _ => None
  }
}

///|
/// `d.get(k)`, `d.keys()`: a dictionary, read and never written.
///
/// `keys`, `values` and `items` answer with a list rather than a view, as
/// `range` answers with a list rather than a range. Everything that consumes
/// one agrees; printing one directly does not.
pub fn dict_method(
  recv : Array[(String, Value)],
  name : String,
  args : Array[Value],
) -> Outcome? {
  match (name, args) {
    ("get", [Str(k)]) =>
      Some(
        Val(
          match lookup(recv, k) {
            Some(v) => v
            None => Value::None
          },
        ),
      )
    ("get", [Str(k), fallback]) =>
      Some(
        Val(
          match lookup(recv, k) {
            Some(v) => v
            None => fallback
          },
        ),
      )
    // Python's `get` takes any hashable key and PurePy's dictionaries are
    // keyed by strings alone, so anything else has nowhere to look.
    ("get", _) => Some(Stuck("a dict key that is not a str"))
    ("keys", []) => Some(Val(List(recv.map(fn(e) { Value::Str(e.0) }))))
    ("values", []) => Some(Val(List(recv.map(fn(e) { e.1 }))))
    ("items", []) =>
      Some(Val(List(recv.map(fn(e) { Value::Tuple([Value::Str(e.0), e.1]) }))))
    _ => None
  }
}

// ---------------------------------------------------------------------------

///|
fn all_chars(s : String, p : (Char) -> Bool) -> Bool {
  // Python's `isdigit` and friends are False for the empty string.
  if s.is_empty() {
    return false
  }
  for c in s {
    if !p(c) {
      return false
    }
  }
  true
}

///|
/// The code-point index of `needle` in `haystack`, or -1.
fn index_of(haystack : String, needle : String) -> Int {
  let hs = haystack.to_array()
  let ns = needle.to_array()
  if ns.is_empty() {
    return 0
  }
  if ns.length() > hs.length() {
    return -1
  }
  for i in 0..<=(hs.length() - ns.length()) {
    let mut same = true
    for j, c in ns {
      if hs[i + j] != c {
        same = false
        break
      }
    }
    if same {
      return i
    }
  }
  -1
}

///|
/// Non-overlapping occurrences, as Python counts them.
fn count_of(haystack : String, needle : String) -> Int {
  let hs = haystack.to_array()
  let ns = needle.to_array()
  if ns.is_empty() {
    return hs.length() + 1
  }
  let mut n = 0
  let mut i = 0
  while i + ns.length() <= hs.length() {
    let mut same = true
    for j, c in ns {
      if hs[i + j] != c {
        same = false
        break
      }
    }
    if same {
      n += 1
      i += ns.length()
    } else {
      i += 1
    }
  }
  n
}

///|
/// `s.split(sep)`: every piece between separators, empties included.
fn split_on(s : String, sep : String) -> Array[String] {
  let out : Array[String] = []
  let hs = s.to_array()
  let ns = sep.to_array()
  let piece = StringBuilder()
  let mut i = 0
  while i < hs.length() {
    let mut same = i + ns.length() <= hs.length()
    if same {
      for j, c in ns {
        if hs[i + j] != c {
          same = false
          break
        }
      }
    }
    if same {
      out.push(piece.to_string())
      piece.reset()
      i += ns.length()
    } else {
      piece.write_char(hs[i])
      i += 1
    }
  }
  out.push(piece.to_string())
  out
}

///|
/// `s.split()`: runs of whitespace, and no empty pieces at all.
fn split_space(s : String) -> Array[String] {
  let out : Array[String] = []
  let piece = StringBuilder()
  for c in s {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      if !piece.is_empty() {
        out.push(piece.to_string())
        piece.reset()
      }
    } else {
      piece.write_char(c)
    }
  }
  if !piece.is_empty() {
    out.push(piece.to_string())
  }
  out
}
