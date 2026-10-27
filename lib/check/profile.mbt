///|
/// Typing what a profile adds.
///
/// None of this is the reference's: a profile is outside the specification,
/// and the reference refuses every program here. What is here is the least
/// that lets a profile's programs be TYPED -- PurePy is a typed language
/// since v0.16, and a feature the checker cannot type is one no well-formed
/// program can use.
///
/// The builtins and methods are typed by RULE rather than by signature: the
/// result of `sorted(xs)` is a list of whatever `xs` holds, which a
/// monomorphic `Callable` cannot say. Each rule reads its arguments' types
/// and answers the result's, refusing with the same reasons the core rules
/// use where an argument does not fit. Under `core` nothing here is reached.

///|
/// The builtins `ExtraBuiltins` adds, typed by `builtin_call_type`.
fn extra_builtin_entries(profile : @profile.Profile) -> Array[(String, Entry)] {
  if !profile.has(ExtraBuiltins) {
    return []
  }
  @context.extra_builtin_names.map(fn(n) { (n, Var(Builtin(n))) })
}

///|
/// The builtins context: the core members, with the profile's added, which
/// replace an annotation-only name they share -- `int`, `str`, `list` -- by a
/// function that can still be named in an annotation (`check_in_scope`).
fn builtins_context(profile : @profile.Profile) -> Context {
  let ms = match predefined_members("builtins") {
    Some(ms) => ms
    None => abort("builtins is predefined")
  }
  let extras = extra_builtin_entries(profile)
  let out = ms.filter(fn(m) { !extras.iter().any(fn(e) { e.0 == m.0 }) })
  predefined_context([..out, ..extras])
}

///|
/// The element type of an iterable, for a profile's rules. Unlike the core
/// `iterated_type` it looks through a literal: `sorted("ba")` is a list of
/// strings, where the core rule -- the reference's -- iterates `str` and not
/// `Literal['ba']`.
fn profile_iterated_type(e : @ast.Expr, ctx : ModCtx) -> @types.Type raise {
  let t = synth_expr(e, ctx)
  match elem_type(ctx.sigma(), @types.base_type(t)) {
    Some(x) => x
    None => raise ill(NotIterable(tau=render(t)), e.span())
  }
}

///|
fn arity(
  args : Array[@ast.Expr],
  lo : Int32,
  hi : Int32,
  span : @basic.Span,
) -> Unit raise {
  if args.length() < lo || args.length() > hi {
    raise ill(CallArityMismatch(expected=hi, given=args.length()), span)
  }
}

///|
fn number_type(
  t : @types.Type,
  span : @basic.Span,
  ctx : ModCtx,
) -> @types.Type raise {
  if @types.subtype(ctx.sigma(), t, @types.t_int) {
    @types.t_int
  } else if @types.subtype(ctx.sigma(), t, @types.t_float) {
    @types.t_float
  } else {
    raise ill(TypeMismatch(expected="float", actual=render(t)), span)
  }
}

///|
/// The element type of an iterable argument; `[]` and `{}` are checked as a
/// list or dict of `default` rather than refused for having no type.
fn iterable_arg(
  e : @ast.Expr,
  default : @types.Type,
  ctx : ModCtx,
) -> @types.Type raise {
  if !synthesises(e) {
    check_expr(e, List(default), ctx)
    return default
  }
  profile_iterated_type(e, ctx)
}

///|
/// Values of the type can be ordered: numbers with numbers, strings with
/// strings. `sorted`, `min` and `max` compare their elements.
fn check_orderable(
  t : @types.Type,
  span : @basic.Span,
  ctx : ModCtx,
) -> Unit raise {
  let sigma = ctx.sigma()
  if !@types.subtype(sigma, t, @types.t_float) &&
    !@types.subtype(sigma, t, @types.t_str) {
    raise ill(NoBinaryOverload(op="<", sigma=render(t), sigma_=render(t)), span)
  }
}

///|
fn builtin_call_type(
  name : String,
  e : @ast.Expr,
  ctx : ModCtx,
) -> @types.Type raise {
  guard e is Call(args~, span~, ..) else { abort("a call") }
  let sigma = ctx.sigma()
  match name {
    "abs" => {
      arity(args, 1, 1, span)
      number_type(synth_expr(args[0], ctx), args[0].span(), ctx)
    }
    "all" | "any" => {
      arity(args, 1, 1, span)
      let t = iterable_arg(args[0], @types.t_bool, ctx)
      if !@types.subtype(sigma, t, @types.t_bool) {
        raise ill(
          TypeMismatch(expected="bool", actual=render(t)),
          args[0].span(),
        )
      }
      @types.t_bool
    }
    "divmod" => {
      arity(args, 2, 2, span)
      let a = number_type(synth_expr(args[0], ctx), args[0].span(), ctx)
      let b = number_type(synth_expr(args[1], ctx), args[1].span(), ctx)
      let t = @types.join_seq(sigma, [a, b])
      Tuple([t, t])
    }
    "enumerate" => {
      arity(args, 1, 1, span)
      List(Tuple([@types.t_int, profile_iterated_type(args[0], ctx)]))
    }
    "float" | "int" => {
      arity(args, 1, 1, span)
      let t = synth_expr(args[0], ctx)
      if !@types.subtype(sigma, t, @types.t_float) &&
        !@types.subtype(sigma, t, @types.t_str) {
        raise ill(
          TypeMismatch(expected="float | str", actual=render(t)),
          args[0].span(),
        )
      }
      if name == "int" {
        @types.t_int
      } else {
        @types.t_float
      }
    }
    "str" | "repr" => {
      arity(args, 1, 1, span)
      synth_expr(args[0], ctx) |> ignore
      @types.t_str
    }
    "list" | "reversed" => {
      arity(args, 1, 1, span)
      List(profile_iterated_type(args[0], ctx))
    }
    // A tuple of a length no annotation can name: what it is is `Sized`,
    // which is enough to print it, measure it and compare it.
    "tuple" => {
      arity(args, 1, 1, span)
      profile_iterated_type(args[0], ctx) |> ignore
      @types.t_sized
    }
    "sorted" => {
      arity(args, 1, 1, span)
      let t = profile_iterated_type(args[0], ctx)
      check_orderable(t, args[0].span(), ctx)
      List(t)
    }
    "max" | "min" => {
      if args.is_empty() {
        raise ill(CallArityMismatch(expected=1, given=0), span)
      }
      let t = if args.length() == 1 {
        profile_iterated_type(args[0], ctx)
      } else {
        @types.join_seq(
          sigma,
          args.map(fn(a) raise { @types.base_type(synth_expr(a, ctx)) }),
        )
      }
      check_orderable(t, span, ctx)
      t
    }
    "sum" => {
      arity(args, 1, 1, span)
      number_type(iterable_arg(args[0], @types.t_int, ctx), args[0].span(), ctx)
    }
    "zip" =>
      List(Tuple(args.map(fn(a) raise { profile_iterated_type(a, ctx) })))
    _ => abort("no typing rule for the builtin " + name)
  }
}

///|
/// The type of `recv.attr(args)` where `recv` is a string, list, tuple or
/// dict, under `BuiltinMethods`; `None` when the receiver is none of those,
/// for the core rules to refuse.
fn method_call_type(
  recv : @types.Type,
  attr : String,
  e : @ast.Expr,
  ctx : ModCtx,
) -> @types.Type? raise {
  guard e is Call(args~, span~, ..) else { abort("a call") }
  let sigma = ctx.sigma()
  let no_such = fn() raise {
    raise ill(UnknownMethod(tau=render(recv), x=attr), span)
  }
  let str_args = fn(n : Int32) raise {
    arity(args, n, n, span)
    for a in args {
      check_expr(a, @types.t_str, ctx)
    }
  }
  match @types.base_type(recv) {
    Prim(Str) =>
      Some(
        match attr {
          "upper" | "lower" | "strip" | "lstrip" | "rstrip" => {
            str_args(0)
            @types.t_str
          }
          "startswith" | "endswith" => {
            str_args(1)
            @types.t_bool
          }
          "replace" => {
            str_args(2)
            @types.t_str
          }
          "split" => {
            arity(args, 0, 1, span)
            for a in args {
              check_expr(a, @types.t_str, ctx)
            }
            List(@types.t_str)
          }
          "join" => {
            arity(args, 1, 1, span)
            let t = iterable_arg(args[0], @types.t_str, ctx)
            if !@types.subtype(sigma, t, @types.t_str) {
              raise ill(
                TypeMismatch(expected="str", actual=render(t)),
                args[0].span(),
              )
            }
            @types.t_str
          }
          "count" | "find" | "index" => {
            str_args(1)
            @types.t_int
          }
          "isdigit" | "isalpha" | "isspace" => {
            str_args(0)
            @types.t_bool
          }
          _ => no_such()
        },
      )
    List(_) | Tuple(_) =>
      Some(
        match attr {
          "count" | "index" => {
            arity(args, 1, 1, span)
            synth_expr(args[0], ctx) |> ignore
            @types.t_int
          }
          _ => no_such()
        },
      )
    Dict(v) =>
      Some(
        match attr {
          "get" => {
            arity(args, 1, 2, span)
            check_expr(args[0], @types.t_str, ctx)
            let other = if args.length() == 2 {
              synth_expr(args[1], ctx)
            } else {
              @types.t_none
            }
            @types.join_seq(sigma, [v, other])
          }
          "keys" => {
            arity(args, 0, 0, span)
            List(@types.t_str)
          }
          "values" => {
            arity(args, 0, 0, span)
            List(v)
          }
          "items" => {
            arity(args, 0, 0, span)
            List(Tuple([@types.t_str, v]))
          }
          _ => no_such()
        },
      )
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Narrowing, under `Identity`

///|
/// What a condition says about the variables it tests: their types where it
/// holds, and where it does not. Only `Identity` produces one, so under
/// `core` both are empty and every rule that consults this is unchanged.
///
/// mypy's narrowing, restricted to what PurePy can spell: a variable compared
/// with `None` by `is` or `is not`, either way round, under `not`, `and` and
/// `or`. A variable is assigned once, so the narrowed type holds for as long
/// as the condition does -- nothing can assign it in between.
///
/// A side that would be `Never` -- `x is None` at `x: int` -- is left at the
/// variable's own type. mypy calls that branch unreachable and skips it; it
/// is never taken, so checking it at the wider type refuses nothing mypy
/// accepts that would run.
priv struct Narrowing {
  yes : Context
  no : Context
}

///|
fn no_narrowing() -> Narrowing {
  { yes: empty_context(), no: empty_context(), }
}

///|
fn narrowing(cond : @ast.Expr, ctx : ModCtx) -> Narrowing {
  guard ctx.program.profile.has(Identity) else { return no_narrowing() }
  let sigma = ctx.sigma()
  match cond {
    Compare(left~, ops=[Is | IsNot as op], comparators=[right], ..) => {
      let x = match (left, right) {
        (Name(id~, ..), Constant(value=None, ..))
        | (Constant(value=None, ..), Name(id~, ..)) => id
        _ => return no_narrowing()
      }
      guard ctx.assigned_type(x) is Some(tau) else { return no_narrowing() }
      let at = fn(t : @types.Type) {
        if t == @types.t_never {
          empty_context()
        } else {
          context_of([(x, Var(t))])
        }
      }
      let none = at(@types.meet(sigma, @types.t_none, tau))
      let some = at(not_none(sigma, tau))
      if op is Is {
        { yes: none, no: some, }
      } else {
        { yes: some, no: none, }
      }
    }
    UnaryOp(op=Not, operand~, ..) => {
      let n = narrowing(operand, ctx)
      { yes: n.no, no: n.yes, }
    }
    // `a and b` holds where both do, and fails where `a` does or where `a`
    // holds and `b` fails; `b` is read where `a` holds.
    BoolOp(op=And, values~, ..) => {
      let mut acc = narrowing(values[0], ctx)
      for v in values[1:] {
        let n = narrowing(v, ctx.override_gamma(acc.yes))
        acc = {
          yes: override_context(acc.yes, n.yes),
          no: join_narrowed(sigma, acc.no, override_context(acc.yes, n.no)),
        }
      }
      acc
    }
    BoolOp(op=Or, values~, ..) => {
      let mut acc = narrowing(values[0], ctx)
      for v in values[1:] {
        let n = narrowing(v, ctx.override_gamma(acc.no))
        acc = {
          yes: join_narrowed(sigma, acc.yes, override_context(acc.no, n.yes)),
          no: override_context(acc.no, n.no),
        }
      }
      acc
    }
    _ => no_narrowing()
  }
}

///|
/// `tau` without `None`, as `case None:` leaves it.
fn not_none(sigma : @types.ClassTable, tau : @types.Type) -> @types.Type {
  @types.join_seq(
    sigma,
    @types.disjuncts(tau).filter(fn(t) {
      t != @types.t_none && t != Literal(NoneLit)
    }),
  )
}

///|
/// What two paths both know: a variable narrowed on both, at the join of its
/// types. One narrowed on a single path is at its own type, and drops out.
fn join_narrowed(
  sigma : @types.ClassTable,
  g : Context,
  h : Context,
) -> Context {
  let mut out = empty_context()
  g.each(fn(x, a) {
    match (a, h.get(x)) {
      (Var(s), Some(Var(t))) => out = out.add(x, Var(@types.join(sigma, s, t)))
      _ => ()
    }
  })
  out
}
