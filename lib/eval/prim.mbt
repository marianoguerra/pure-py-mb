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
    Print => {
      let parts : Array[String] = []
      for a in args {
        match a.str() {
          Some(t) => parts.push(t)
          // A closure, a module or a class has no printable form: Python
          // prints an address, which no implementation can reproduce.
          None => return Stuck("printing " + a.kind_name())
        }
      }
      self.write(parts.join(" ") + "\n")
      Val(None)
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
