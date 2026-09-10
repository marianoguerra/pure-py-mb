///|
/// Python's `str` and `repr` of a value.
///
/// The two differ in exactly one place -- a string is itself under `str` and
/// quoted under `repr` -- and `print` uses `str` while a container prints its
/// elements with `repr`. Everything else is the same function.
///
/// A closure, a module, a class or a primitive has no printable form here.
/// Python prints one with an address in it, which no implementation can
/// reproduce, so printing one is an undefined operation and is reported as
/// such rather than invented.
pub fn Value::str(self : Value) -> String? {
  match self {
    Str(s) => Some(s)
    other => other.repr()
  }
}

///|
/// What `print` writes for these arguments: `str` of each, joined by a single
/// space, and a newline. `None` if one of them has no printable form, which is
/// the operation `print` leaves undefined.
///
/// A host that REDEFINES `builtins.print` is handed the arguments and not the
/// text, and most of them still want the text for something -- a transcript
/// beside the values, a fallback for a shape they do not recognise. This is
/// how they get it without writing the join a second time and drifting from
/// the oracle on the first argument that renders unusually.
pub fn print_text(args : Array[Value]) -> String? {
  let parts : Array[String] = []
  for a in args {
    match a.str() {
      Some(t) => parts.push(t)
      None => return None
    }
  }
  Some(parts.join(" ") + "\n")
}

///|
pub fn Value::repr(self : Value) -> String? {
  match self {
    None => Some("None")
    Bool(b) => Some(if b { "True" } else { "False" })
    Int(n) => Some(n.to_string())
    Float(d) => Some(@basic.py_float_repr(d))
    Str(s) => Some(@basic.py_repr(s))
    List(xs) => bracketed(xs, "[", "]", trailing_comma=false)
    // A one-element tuple keeps its comma: `('x',)`.
    Tuple(xs) => bracketed(xs, "(", ")", trailing_comma=xs.length() == 1)
    Dict(entries) => {
      let out = StringBuilder()
      out.write_string("{")
      for i, e in entries {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(@basic.py_repr(e.0))
        out.write_string(": ")
        match e.1.repr() {
          Some(t) => out.write_string(t)
          None => return None
        }
      }
      out.write_string("}")
      Some(out.to_string())
    }
    // `P(x=1, y='a')`: the class's short name and every field, inherited
    // first, which is the order `fields` gives them.
    Obj(entry, env) => {
      let out = StringBuilder()
      out.write_string(entry.short_name())
      out.write_string("(")
      for i, x in entry.fields() {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(x)
        out.write_string("=")
        match env.get(x) {
          Some(v) =>
            match v.repr() {
              Some(t) => out.write_string(t)
              None => return None
            }
          None => return None
        }
      }
      out.write_string(")")
      Some(out.to_string())
    }
    _ => None
  }
}

///|
fn bracketed(
  xs : Array[Value],
  open : String,
  close : String,
  trailing_comma~ : Bool,
) -> String? {
  let out = StringBuilder()
  out.write_string(open)
  for i, v in xs {
    if i > 0 {
      out.write_string(", ")
    }
    match v.repr() {
      Some(t) => out.write_string(t)
      None => return None
    }
  }
  if trailing_comma {
    out.write_string(",")
  }
  out.write_string(close)
  Some(out.to_string())
}
