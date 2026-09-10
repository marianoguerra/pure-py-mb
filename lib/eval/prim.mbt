///|
/// The predefined functions of Figure 2.7.
///
/// The figure gives `len`, `range` and `sys.exit` as partial maps from
/// arguments to outcomes, and a call outside a map's domain has no
/// derivation. So `len` has an explicit "otherwise aborts TypeError" and
/// `range` does not: `range("x")` is undefined, while `len(1)` aborts. The
/// asymmetry is the figure's, not this port's.
///
/// The figure leaves `print` and the `math` functions without a definition.
/// They are implemented as Python implements them, since CPython is the
/// oracle for what a run prints.
async fn Interp::call_primitive(
  self : Interp,
  p : @value.Primitive,
  args : Array[Value],
) -> Outcome noraise {
  match p {
    Print =>
      match @value.print_text(args) {
        Some(text) => {
          self.write(text)
          Val(None)
        }
        // A closure, a module or a class has no printable form: Python prints
        // an address, which no implementation can reproduce.
        None => Stuck("printing " + unprintable(args))
      }
    Len =>
      if args.length() != 1 {
        Aborts(TypeError)
      } else {
        match @value.iter(args[0]) {
          Some(xs) => Val(Int(BigInt::from_int(xs.length())))
          None => Aborts(TypeError)
        }
      }
    Range =>
      if args.length() != 1 {
        Stuck("range with \{args.length()} arguments")
      } else {
        match args[0] {
          Int(n) => {
            // `range` is the one predefined function that builds a sequence
            // from a NUMBER, so it is the one place a three-character program
            // can ask for more memory than the machine has. Charged before it
            // builds, not after: `range(10 ** 9)` has to be refused rather
            // than survived.
            if !self.spend(n) {
              return Stuck("a run longer than \{self.max_steps} steps")
            }
            let out : Array[Value] = []
            let mut i = 0N
            while i < n {
              out.push(Int(i))
              i = i + 1N
            }
            Val(List(out))
          }
          v => Stuck("range of " + v.kind_name())
        }
      }
    Exit =>
      if args.is_empty() {
        Aborts(SystemExit(0N))
      } else if args.length() == 1 {
        match args[0] {
          Int(n) => Aborts(SystemExit(n))
          v => Stuck("sys.exit of " + v.kind_name())
        }
      } else {
        Stuck("sys.exit with \{args.length()} arguments")
      }
    // `math.floor` and `math.ceil` return an integer in Python; the rest
    // return a float.
    MathFloor | MathCeil => {
      let x = match numeric(args) {
        Some(d) => d
        None => return Stuck("a math function of the wrong shape")
      }
      let r = if p is MathFloor { x.floor() } else { @math.ceil(x) }
      match @value.exact_integer(r) {
        Some(n) => Val(Int(n))
        None => Stuck("floor or ceil of a value with no integer")
      }
    }
    Sqrt | Exp | Log | Sin | Cos | Tan => {
      let x = match numeric(args) {
        Some(d) => d
        None => return Stuck("a math function of the wrong shape")
      }
      match p {
        // `sqrt` of a negative number and `log` of a non-positive one raise
        // ValueError in Python, which is not a termination kind.
        Sqrt =>
          if x < 0.0 {
            Stuck("the square root of a negative number")
          } else {
            Val(Float(x.sqrt()))
          }
        Log =>
          if x <= 0.0 {
            Stuck("the logarithm of a number that is not positive")
          } else {
            Val(Float(@math.ln(x)))
          }
        Exp => Val(Float(@math.exp(x)))
        Sin => Val(Float(@math.sin(x)))
        Cos => Val(Float(@math.cos(x)))
        _ => Val(Float(@math.tan(x)))
      }
    }
    // The builtins a profile adds. Nothing below checks the profile: a
    // primitive is only reachable by being bound in an environment, and only
    // `Interp::predefined` under a profile that asked binds these.
    //
    // Every one of them declines to coerce. Python answers `sum([True])` with
    // 1, `any([1])` with True and `int(True)` with 1, all by treating a value
    // as something it is not; PurePy makes a bool not a number and has no
    // truthiness at all, so each of those is undefined here. That is the whole
    // difference between adding a library to PurePy and adding Python to it.
    Abs
    | Repr
    | ToStr
    | ToInt
    | ToFloat
    | ToList
    | ToTuple
    | Reversed
    | Round
    | Sorted
    | Sum
    | All
    | Any
    | Enumerate =>
      if args.length() != 1 {
        Aborts(TypeError)
      } else {
        unary_builtin(p, args[0])
      }
    Min | Max => extremum(p is Min, args)
    DivMod =>
      if args.length() != 2 {
        Aborts(TypeError)
      } else {
        match
          (
            @value.binop(FloorDiv, args[0], args[1]),
            @value.binop(Mod, args[0], args[1]),
          ) {
          (Val(q), Val(r)) => Val(Tuple([q, r]))
          (Aborts(k), _) | (_, Aborts(k)) => Aborts(k)
          (Stuck(w), _) | (_, Stuck(w)) => Stuck(w)
        }
      }
    Zip => {
      let columns : Array[Array[Value]] = []
      for a in args {
        match @value.elems(a) {
          Some(xs) => columns.push(xs)
          None => return Aborts(TypeError)
        }
      }
      // Python's `zip` stops at the shortest, and with no arguments is empty.
      let mut shortest = 0
      for i, col in columns {
        if i == 0 || col.length() < shortest {
          shortest = col.length()
        }
      }
      let out : Array[Value] = []
      for i in 0..<shortest {
        out.push(Tuple(columns.map(fn(col) { col[i] })))
      }
      Val(List(out))
    }
    // `typing.Any`, `typing.Callable` and `dataclasses.dataclass` are values
    // so that importing them binds something. They are never called.
    Opaque(name) => Stuck("calling " + name)
    // A function the host supplies. It answers by name, and what it cannot
    // answer is an operation the semantics does not cover -- the same as any
    // other undefined operation, and reported the same way.
    Foreign(name) => (self.host.call)(name, args)
  }
}

///|
/// The kind of the first argument `print` could not render, for the message.
///
/// A second pass, on the path where the run has already ended, so that the
/// join itself stays in one place. `print_text` answered `None`, so one of
/// them is here.
fn unprintable(args : Array[Value]) -> String {
  for a in args {
    if a.str() is None {
      return a.kind_name()
    }
  }
  "a value with no printable form"
}

///|
/// The single numeric argument a `math` function takes, as a double. An
/// integer is converted, as Python converts it.
fn numeric(args : Array[Value]) -> Double? {
  if args.length() != 1 {
    return None
  }
  match args[0] {
    Float(d) => Some(d)
    Int(n) => Some(@value.big_to_double(n))
    _ => None
  }
}

///|
/// The one-argument builtins a profile adds.
///
/// `enumerate`, `zip`, `reversed`, `sorted`, `list` and `tuple` answer with a
/// list or a tuple where Python answers with a lazy object. That is not a
/// shortcut: `range` already does it, because Figure 2.7 defines `range` as a
/// list, and PurePy has no iterator to be lazy with. It is observable --
/// `print(zip(a, b))` prints the pairs here and `<zip object at 0x...>` in
/// Python -- and it is observable for `range` today. Everything that CONSUMES
/// one agrees.
fn unary_builtin(p : @value.Primitive, v : Value) -> Outcome {
  match p {
    Abs =>
      match v {
        Int(n) => Val(Int(if n < 0N { -n } else { n }))
        Float(d) => Val(Float(if d < 0.0 { -d } else { d }))
        // `abs(True)` is 1 in Python. A bool is not a number here.
        _ => Aborts(TypeError)
      }
    Repr =>
      match v.repr() {
        Some(t) => Val(Str(t))
        None => Stuck("repr of " + v.kind_name())
      }
    ToStr =>
      match v.str() {
        Some(t) => Val(Str(t))
        None => Stuck("str of " + v.kind_name())
      }
    ToInt =>
      match v {
        Int(_) => Val(v)
        // Python truncates toward zero, which is not the floor.
        Float(d) =>
          if d.is_nan() || d.is_inf() {
            Aborts(TypeError)
          } else {
            match
              @value.exact_integer(
                if d < 0.0 {
                  @math.ceil(d)
                } else {
                  d.floor()
                },
              ) {
              Some(n) => Val(Int(n))
              None => Stuck("int of a float with no integer")
            }
          }
        Str(t) =>
          match parse_int(t) {
            Some(n) => Val(Int(n))
            // Python raises ValueError, which PurePy does not model.
            None => Stuck("int of a string that is not a number")
          }
        _ => Aborts(TypeError)
      }
    ToFloat =>
      match v {
        Float(_) => Val(v)
        Int(n) => Val(Float(@value.big_to_double(n)))
        Str(t) =>
          try @string.parse_double(t.trim(chars=" ").to_owned()) catch {
            _ => Stuck("float of a string that is not a number")
          } noraise {
            d => Val(Float(d))
          }
        _ => Aborts(TypeError)
      }
    ToList | ToTuple | Reversed | Enumerate | Sorted =>
      match @value.iter(v) {
        None => Aborts(TypeError)
        Some(xs) =>
          match p {
            ToList => Val(List(xs))
            ToTuple => Val(Tuple(xs))
            Reversed => Val(List(xs.rev()))
            Enumerate => {
              let out : Array[Value] = []
              for i, x in xs {
                out.push(Tuple([Int(BigInt::from_int(i)), x]))
              }
              Val(List(out))
            }
            // A total order over the whole list or nothing: `@value.order` is
            // partial, and a sort that fell back on the original positions
            // would be inventing one.
            _ =>
              match sorted(xs) {
                Some(out) => Val(List(out))
                None => Stuck("sorting a list this order does not cover")
              }
          }
      }
    Round =>
      match v {
        Int(_) => Val(v)
        // Python rounds halves to even, and `round(x)` answers an int.
        Float(d) =>
          match @value.exact_integer(round_half_even(d)) {
            Some(n) => Val(Int(n))
            None => Stuck("round of a value with no integer")
          }
        _ => Aborts(TypeError)
      }
    Sum =>
      match @value.elems(v) {
        None => Aborts(TypeError)
        Some(xs) => {
          let mut acc = Value::Int(0N)
          for x in xs {
            match @value.binop(Add, acc, x) {
              Val(w) => acc = w
              other => return other
            }
          }
          Val(acc)
        }
      }
    // PurePy has no truthiness, so these want real bools -- the same thing
    // `if`, `and` and an `assert` want, and for the same reason.
    All | Any =>
      match @value.elems(v) {
        None => Aborts(TypeError)
        Some(xs) => {
          let want = p is Any
          for x in xs {
            match x {
              Bool(b) => if b == want { return Val(Bool(want)) }
              other =>
                return Stuck(
                  "'" +
                  (if want { "any" } else { "all" }) +
                  "' over a " +
                  other.kind_name() +
                  ": PurePy has no truthiness",
                )
            }
          }
          Val(Bool(!want))
        }
      }
    _ => Stuck("a builtin of the wrong shape")
  }
}

///|
/// `min` and `max`: one iterable, or two or more values.
fn extremum(want_min : Bool, args : Array[Value]) -> Outcome {
  let xs = if args.length() == 1 {
    match @value.elems(args[0]) {
      Some(xs) => xs
      None => return Aborts(TypeError)
    }
  } else if args.is_empty() {
    return Aborts(TypeError)
  } else {
    args
  }
  if xs.is_empty() {
    // Python raises ValueError on an empty sequence.
    return Stuck("min or max of nothing")
  }
  let mut best = xs[0]
  for x in xs[1:] {
    match @value.order(x, best) {
      Some(c) => if (c < 0) == want_min && c != 0 { best = x }
      None =>
        return Stuck("comparing " + x.kind_name() + " with " + best.kind_name())
    }
  }
  Val(best)
}

///|
/// An insertion sort over a PARTIAL order, refusing rather than guessing.
///
/// `@value.order` answers `None` for a pair it does not cover -- an int and a
/// str, a nan and anything -- and a sort that skipped such a pair would put
/// the list in an order the language cannot justify. So one unordered pair
/// makes the whole call undefined, which is the same discipline `@value.eq`
/// follows.
fn sorted(xs : Array[Value]) -> Array[Value]? {
  let out : Array[Value] = []
  for x in xs {
    let mut at = out.length()
    for i, y in out {
      match @value.order(x, y) {
        Some(c) => if c < 0 && at == out.length() { at = i }
        None => return None
      }
    }
    out.insert(at, x)
  }
  Some(out)
}

///|
/// Python's `round`: halves go to the even neighbour, not away from zero.
fn round_half_even(d : Double) -> Double {
  let down = d.floor()
  let frac = d - down
  if frac > 0.5 {
    down + 1.0
  } else if frac < 0.5 {
    down
  } else if down % 2.0 == 0.0 {
    down
  } else {
    down + 1.0
  }
}

///|
/// `int("...")`: an optionally signed run of digits, and nothing else.
///
/// Deliberately narrower than Python's, which takes underscores and every
/// Unicode decimal digit. What it accepts, it agrees with Python about; what
/// it does not, it declines rather than guessing.
fn parse_int(t : String) -> BigInt? {
  let s = t.trim(chars=" ")
  let (sign, digits) = if s.has_prefix("-") {
    (-1N, s[1:])
  } else if s.has_prefix("+") {
    (1N, s[1:])
  } else {
    (1N, s)
  }
  if digits.is_empty() {
    return None
  }
  let mut acc = 0N
  for c in digits {
    if c < '0' || c > '9' {
      return None
    }
    acc = acc * 10N + BigInt::from_int(c.to_int() - '0'.to_int())
  }
  Some(sign * acc)
}
