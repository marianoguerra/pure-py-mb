///|
/// The evaluator as a machine with an explicit stack, rather than as a
/// recursive walk.
///
/// PurePy has no loops, so recursion is the only iteration a guest has, and a
/// tree-walking evaluator spends host stack in proportion to how deep the
/// guest goes. That was the arrangement until now: about a dozen host frames
/// per guest call once MoonBit's `async` transform is counted, `max_depth`
/// picked to fire before a JavaScript engine threw a `RangeError` no MoonBit
/// code can catch, and a number that had to be re-measured whenever the
/// evaluator changed shape. Adding one match arm to `eval_expr` once cost four
/// frames of guest depth, because a frame is sized by the whole function.
///
/// Here the continuation is a value: an `Array[Frame]` on the heap. The driver
/// loop below is ONE host frame however deep the guest goes, so
///
///   * guest recursion is bounded by memory rather than by the host's stack,
///     and `max_depth` becomes a policy -- how deep a guest may go -- instead
///     of a guess about an engine;
///   * the bound is the same on every backend, because nothing about it
///     depends on the host any more;
///   * and the evaluator's shape stops being load-bearing. A bigger arm costs
///     what it costs and nothing else.
///
/// It is also closer to what is being ported. PurePy is specified as a
/// small-step operational semantics, and a machine with an explicit
/// continuation is that semantics written down; the recursive walk was the
/// paraphrase.
///
/// **What still recurses, and why that is safe.** Patterns
/// (`match_pattern`), class resolution (`resolve_class`) and module loading
/// (`load`) call back into a fresh machine. None of them can recurse with the
/// GUEST: a pattern's depth is the pattern's own nesting, a `MatchValue` head
/// is a qualified name with no call in it, and imports are bounded by the
/// module graph and guarded against cycles. Each is bounded by the source, so
/// each costs a constant.

///|
/// What the machine does next.
///
/// Five states and no more. `Delta` is what a statement produces -- the names
/// it bound -- and is the only reason this is not simply an expression
/// machine; `Ret` and `Halt` are the two ways control leaves a frame without
/// answering it, which is how `return` and an abort each unwind.
priv enum Ctl {
  /// Evaluate this expression in this environment.
  Ev(@ast.Expr, Env)
  /// Hand this value to the frame on top of the stack.
  Rv(Value)
  /// A statement finished, binding these names.
  Delta(Env)
  /// A `return`: unwind to the nearest call boundary.
  Ret(Value)
  /// An abort or an undefined operation: unwind everything.
  Halt(Outcome)
}

///|
/// What to do once a run of sub-expressions has all been evaluated.
///
/// The five shapes that collect a list of values before doing anything with
/// them are one frame rather than five, because the only thing that differs is
/// this.
priv enum Then {
  MakeList
  MakeTuple
  /// A call whose callee is already a value.
  DoCall(callee~ : Value, at~ : @ast.Expr)
  /// A constructor. The first `positional` values are positional and the rest
  /// answer to `kwnames`, in order.
  DoCtor(
    entry~ : @context.ClassEntry,
    positional~ : Int,
    kwnames~ : Array[String],
    at~ : @ast.Expr
  )
  /// A method call on a builtin value, whose receiver is already a value.
  DoMethod(recv~ : Value, attr~ : String, at~ : @ast.Expr)
}

///|
/// A run of sub-expressions being evaluated left to right.
priv struct Collect {
  exprs : Array[@ast.Expr]
  mut next : Int
  acc : Array[Value]
  env : Env
  then_ : Then
}

///|
/// A dictionary display: keys and values, alternating, in source order.
priv struct DictJob {
  keys : Array[@ast.Expr?]
  values : Array[@ast.Expr]
  mut next : Int
  /// The key of the pair being built, and whether it has one yet. A flag and
  /// not a sentinel, because `{"": 1}` is a dictionary with an empty key.
  mut key : String
  mut has_key : Bool
  pairs : Array[(String, Value)]
  env : Env
}

///|
/// A slice's three bounds. An omitted one is not `None` the PurePy value --
/// `xs[:2]` and `xs[None:2]` are different programs -- so absence survives to
/// `getslice` and this cannot be a `Collect`.
priv struct SliceJob {
  obj : Value
  bounds : Array[@ast.Expr?]
  mut next : Int
  acc : Array[Value?]
  env : Env
  at : @ast.Expr
}

///|
/// A statement sequence: what is left of it, the environment it is running in,
/// and what it has bound so far.
///
/// The environment and the delta are separate because a sequence answers with
/// the bindings THE SEQUENCE made, not with the whole environment -- which is
/// what keeps a function body's locals out of its caller.
priv struct SeqJob {
  items : ArrayView[@analysis.Statement]
  mut next : Int
  mut env : Env
  mut delta : Env
}

///|
/// One active generator of a comprehension: the name it binds, the items it
/// draws from, where it has got to, and the environment it started in.
priv struct CompLevel {
  name : String
  items : Array[Value]
  mut index : Int
  outer : Env
}

///|
/// A comprehension in flight.
///
/// `levels` is the generator loops that are currently open -- one per `for`
/// clause the machine has entered -- so `[x for a in p for b in q]` has two
/// when it is evaluating `x`. Pushing and popping levels is the nesting that
/// `eval_quals` used to do by recursing, made a value so that a call inside
/// the element expression pushes a frame here rather than a host frame.
priv struct CompJob {
  /// The element, for a list comprehension; the key, for a dict one.
  first : @ast.Expr
  /// The value, for a dict comprehension.
  second : @ast.Expr?
  generators : Array[@ast.Comprehension]
  levels : Array[CompLevel]
  out : Array[Value]
  pairs : Array[(String, Value)]
  mut key : String
  base : Env
}

///|
/// A suspended piece of the evaluator: what remains once the thing being
/// evaluated has an answer.
priv enum Frame {
  // -- expressions --------------------------------------------------------
  UnOp(op~ : @ast.UnaryOp, at~ : @ast.Expr)
  BinRight(op~ : @ast.Operator, right~ : @ast.Expr, env~ : Env, at~ : @ast.Expr)
  BinApply(op~ : @ast.Operator, left~ : Value, at~ : @ast.Expr)
  /// `and` and `or`: the operand that decides stops the run.
  Bool(op~ : @ast.BoolOp, values~ : Array[@ast.Expr], next~ : Int, env~ : Env)
  /// A comparison chain, waiting for its left operand.
  CmpLeft(
    ops~ : Array[@ast.CmpOp],
    comparators~ : Array[@ast.Expr],
    env~ : Env,
    at~ : @ast.Expr
  )
  /// The same, waiting for `comparators[next]`, with the previous operand in
  /// hand so that a chain evaluates each operand exactly once.
  CmpRight(
    ops~ : Array[@ast.CmpOp],
    comparators~ : Array[@ast.Expr],
    next~ : Int,
    left~ : Value,
    env~ : Env,
    at~ : @ast.Expr
  )
  IfExp(body~ : @ast.Expr, or_else~ : @ast.Expr, env~ : Env)
  Items(Collect)
  DictPairs(DictJob)
  Attr(attr~ : String, at~ : @ast.Expr)
  /// A subscript, waiting for the thing being subscripted.
  SubOn(slice~ : @ast.Expr, env~ : Env, at~ : @ast.Expr)
  /// A subscript, waiting for the index.
  SubBy(obj~ : Value, at~ : @ast.Expr)
  Slice(SliceJob)
  FString(
    parts~ : Array[@ast.FStringPart],
    next~ : Int,
    acc~ : StringBuilder,
    env~ : Env
  )
  /// A call, waiting for its callee.
  CallOn(
    args~ : Array[@ast.Expr],
    keywords~ : Array[@ast.Keyword],
    env~ : Env,
    at~ : @ast.Expr
  )
  /// A method call, waiting for its receiver.
  MethodOn(
    attr~ : String,
    args~ : Array[@ast.Expr],
    keywords~ : Array[@ast.Keyword],
    env~ : Env,
    at~ : @ast.Expr
  )
  // -- comprehensions -----------------------------------------------------
  CompIter(CompJob)
  CompGuard(job~ : CompJob, index~ : Int)
  CompFirst(CompJob)
  CompSecond(CompJob)
  // -- statements ---------------------------------------------------------
  Seq(SeqJob)
  StAssign(target~ : @ast.Expr)
  StExpr
  StReturn
  StAssert(at~ : @ast.Stmt, msg~ : @ast.Expr?, env~ : Env)
  StAssertMsg(at~ : @ast.Stmt)
  StIf(body~ : Array[@ast.Stmt], or_else~ : Array[@ast.Stmt], env~ : Env)
  StMatch(cases~ : Array[@ast.MatchCase], env~ : Env)
  /// A `match` body, whose result composes with the bindings the pattern made.
  StMatchBody(bindings~ : Env)
  // -- calls --------------------------------------------------------------
  /// The boundary of a guest call: what `return` unwinds to, and what restores
  /// the caller's module and gives back the depth this call took.
  ///
  /// The count of these on the stack IS the call depth, which is why
  /// `max_depth` no longer has anything to do with the host.
  CallBoundary(caller~ : String)
}

// ---------------------------------------------------------------------------
// The driver

///|
/// Run the machine from a starting control state until the stack is empty.
///
/// One host frame, however deep the guest goes. Every `return`, every call and
/// every abort is a move on `stack` rather than a move on the host's.
///
/// It is `async` for one reason: a host function may answer later, and
/// `call_primitive` awaits it. Suspending here parks the loop with the whole
/// continuation already on the heap, which is the same continuation it would
/// have parked with before -- a guest cannot tell.
async fn Interp::drive(
  self : Interp,
  start : Ctl,
  stack : Array[Frame],
) -> Ctl noraise {
  let mut ctl = start
  let base_module = self.in_module
  for ;; {
    match ctl {
      Ev(e, env) => ctl = self.step_expr(e, env, stack)
      Halt(o) => {
        // Nothing catches: PurePy has no `try`. Unwind so that every call
        // boundary gives back its module and its depth, then answer.
        while stack.pop() is Some(f) {
          if f is CallBoundary(caller~) {
            self.in_module = caller
            self.depth -= 1
          }
        }
        self.in_module = base_module
        return Halt(o)
      }
      _ =>
        match stack.pop() {
          Some(f) => ctl = self.resume_frame(f, ctl, stack)
          // The stack is empty, so this is the answer the run was started for.
          None => return ctl
        }
    }
  }
}

///|
/// Run the machine and read the answer as an expression's.
async fn Interp::machine(self : Interp, start : Ctl) -> Outcome noraise {
  match self.drive(start, []) {
    Rv(v) => Val(v)
    // A `return` that reached the bottom: a lambda body is an expression, so
    // its call boundary answered before this could happen, and a module body
    // has no `return` to run. Answering with the value is the reading that
    // cannot surprise anyone.
    Ret(v) => Val(v)
    Delta(_) => Val(Value::None)
    Halt(o) => o
    Ev(_, _) => Stuck("a machine that would not settle")
  }
}

///|
/// Run the machine over a statement sequence and read the answer as one.
///
/// The three ways a sequence can end are the three the machine already has:
/// it ran out of statements (`Delta`), it returned (`Ret`), or it stopped
/// (`Halt`).
async fn Interp::machine_seq(
  self : Interp,
  items : ArrayView[@analysis.Statement],
  env : Env,
) -> StmtResult noraise {
  let stack : Array[Frame] = []
  let start = self.start_seq(items, env, stack)
  match self.drive(start, stack) {
    Delta(d) => Assigns(d)
    Ret(v) => Returns(v)
    Rv(_) => Assigns(@value.empty_env())
    Halt(Aborts(k)) => ResultAborts(k)
    Halt(Stuck(op)) => ResultStuck(op)
    Halt(Val(_)) => Assigns(@value.empty_env())
    Ev(_, _) => ResultStuck("a machine that would not settle")
  }
}

///|
/// Enter a callee from outside the machine: the public `apply`.
async fn Interp::machine_apply(
  self : Interp,
  callee : Value,
  actual : Array[Value],
) -> Outcome noraise {
  let stack : Array[Frame] = []
  let start = self.enter(callee, actual, None, stack)
  match self.drive(start, stack) {
    Rv(v) => Val(v)
    Ret(v) => Val(v)
    Delta(_) => Val(Value::None)
    Halt(o) => o
    Ev(_, _) => Stuck("a machine that would not settle")
  }
}

///|
/// Give `ctl` to `f`, and say what to do next.
///
/// `Ret` and `Halt` do not belong to any frame: the first unwinds to the
/// nearest call boundary and the second to the bottom, so both are answered
/// here before a frame ever sees them.
async fn Interp::resume_frame(
  self : Interp,
  f : Frame,
  ctl : Ctl,
  stack : Array[Frame],
) -> Ctl noraise {
  match ctl {
    Ret(v) =>
      match f {
        CallBoundary(caller~) => {
          self.in_module = caller
          self.depth -= 1
          Rv(v)
        }
        _ => Ret(v)
      }
    Halt(o) => Halt(o)
    Rv(v) => self.resume_value(f, v, stack)
    Delta(d) => self.resume_delta(f, d, stack)
    Ev(_, _) => Halt(Stuck("a machine that would not settle"))
  }
}

// ---------------------------------------------------------------------------
// Expressions

///|
/// Start evaluating an expression: answer at once where the rule needs no
/// sub-expression, and otherwise push what remains and evaluate the first.
///
/// This is `eval_expr`'s match, with each recursive call replaced by a frame.
/// The rules are the same rules and the order is the same order; what changed
/// is where the "and then" lives.
async fn Interp::step_expr(
  self : Interp,
  e : @ast.Expr,
  env : Env,
  stack : Array[Frame],
) -> Ctl noraise {
  match e {
    // eval-var
    Name(id~, ..) =>
      match env.get(id) {
        Some(v) => Rv(v)
        None => Halt(Stuck("the unbound name '" + id + "'"))
      }
    // eval-literal
    Constant(value~, ..) =>
      match value {
        Int(n) => Rv(Int(n))
        Float(d) => Rv(Float(d))
        Str(s) => Rv(Str(s))
        Bool(b) => Rv(Bool(b))
        None => Rv(Value::None)
        _ => Halt(Stuck("a literal the sieve should have rejected"))
      }
    // eval-lambda
    Lambda(args~, body~, ..) =>
      Rv(
        Lam({
          env,
          params: args.args.map(fn(p) { p.arg }),
          defaults: literal_defaults(args),
          body,
          in_module: self.in_module,
        }),
      )
    // eval-unop
    UnaryOp(op~, operand~, ..) => {
      stack.push(UnOp(op~, at=e))
      Ev(operand, env)
    }
    // eval-binop
    BinOp(left~, op~, right~, ..) => {
      stack.push(BinRight(op~, right~, env~, at=e))
      Ev(left, env)
    }
    // eval-and-*, eval-or-*
    BoolOp(op~, values~, ..) => {
      stack.push(Bool(op~, values~, next=1, env~))
      Ev(values[0], env)
    }
    Compare(left~, ops~, comparators~, ..) => {
      stack.push(CmpLeft(ops~, comparators~, env~, at=e))
      Ev(left, env)
    }
    // eval-cond-true, eval-cond-false
    IfExp(cond~, body~, or_else~, ..) => {
      stack.push(IfExp(body~, or_else~, env~))
      Ev(cond, env)
    }
    // eval-list, eval-tuple
    List(elts~, ..) => self.start_items(elts, env, MakeList, stack)
    Tuple(elts~, ..) => self.start_items(elts, env, MakeTuple, stack)
    // eval-dict
    Dict(keys~, values~, ..) =>
      step_dict(
        { keys, values, next: 0, key: "", has_key: false, pairs: [], env, },
        stack,
      )
    // eval-list-comp, eval-dict-comp
    ListComp(elt~, generators~, ..) =>
      step_comp(
        {
          first: elt,
          second: None,
          generators,
          levels: [],
          out: [],
          pairs: [],
          key: "",
          base: env,
        },
        stack,
      )
    DictComp(key~, value~, generators~, ..) =>
      step_comp(
        {
          first: key,
          second: Some(value),
          generators,
          levels: [],
          out: [],
          pairs: [],
          key: "",
          base: env,
        },
        stack,
      )
    JoinedStr(parts~, ..) => step_fstring(parts, 0, StringBuilder(), env, stack)
    // eval-attr-module, eval-attr-object, eval-attr-missing
    Attribute(value~, attr~, ..) => {
      stack.push(Attr(attr~, at=e))
      Ev(value, env)
    }
    // eval-subscript
    Subscript(value~, slice~, ..) => {
      stack.push(SubOn(slice~, env~, at=e))
      Ev(value, env)
    }
    Call(func~, args~, keywords~, ..) =>
      self.step_call(func, args, keywords, env, e, stack)
    _ => Halt(Stuck("expression " + e.kind_name()))
  }
}

///|
/// Begin a run of sub-expressions.
async fn Interp::start_items(
  self : Interp,
  exprs : Array[@ast.Expr],
  env : Env,
  then_ : Then,
  stack : Array[Frame],
) -> Ctl noraise {
  self.step_items({ exprs, next: 0, acc: [], env, then_, }, stack)
}

///|
/// The next sub-expression of a run, or -- when they are all in -- whatever
/// the run was for.
async fn Interp::step_items(
  self : Interp,
  job : Collect,
  stack : Array[Frame],
) -> Ctl noraise {
  if job.next < job.exprs.length() {
    let e = job.exprs[job.next]
    job.next += 1
    stack.push(Items(job))
    return Ev(e, job.env)
  }
  match job.then_ {
    MakeList => Rv(List(job.acc))
    MakeTuple => Rv(Tuple(job.acc))
    // eval-constr: the class was looked up rather than evaluated, so the
    // fields are all that was waiting on the arguments.
    DoCtor(entry~, positional~, kwnames~, at~) =>
      match
        entry.field_map(
          job.acc[:positional].to_owned(),
          kwnames,
          job.acc[positional:].to_owned(),
        ) {
        Some(fields) => Rv(Obj(entry, @value.env_of(fields)))
        None => {
          self.record(at.span())
          Halt(Aborts(TypeError))
        }
      }
    DoMethod(recv~, attr~, at~) => {
      let o = call_method(recv, attr, job.acc)
      if o is Aborts(_) {
        self.record(at.span())
      }
      outcome_ctl(o)
    }
    DoCall(callee~, at~) => self.enter(callee, job.acc, Some(at), stack)
  }
}

///|
/// An `Outcome` as a control state.
fn outcome_ctl(o : Outcome) -> Ctl {
  match o {
    Val(v) => Rv(v)
    other => Halt(other)
  }
}

///|
/// A dictionary display, one key or value at a time.
fn step_dict(job : DictJob, stack : Array[Frame]) -> Ctl {
  if job.next >= job.values.length() {
    return Rv(Dict(@value.entries([], job.pairs)))
  }
  match job.keys[job.next] {
    None => Halt(Stuck("dictionary unpacking"))
    Some(k) => {
      stack.push(DictPairs(job))
      Ev(k, job.env)
    }
  }
}

///|
/// An f-string, one piece at a time: literal text is written straight out and
/// a hole is evaluated.
fn step_fstring(
  parts : Array[@ast.FStringPart],
  from : Int,
  acc : StringBuilder,
  env : Env,
  stack : Array[Frame],
) -> Ctl {
  let mut i = from
  while i < parts.length() {
    match parts[i] {
      Text(t) => {
        acc.write_string(t)
        i += 1
      }
      Hole(value~, ..) => {
        stack.push(FString(parts~, next=i, acc~, env~))
        return Ev(value, env)
      }
    }
  }
  Rv(Str(acc.to_string()))
}

// ---------------------------------------------------------------------------
// Calls

///|
/// Start a call expression: decide which of the four shapes it is, and put the
/// first thing that has to be evaluated in front of the machine.
///
/// The order is `eval_call`'s order and for its reasons: a constructor looks
/// the class up rather than evaluating it, and a method call on a builtin is
/// decided before the callee is evaluated as an expression, because there is
/// no callee to evaluate -- `xs.append` is not a value.
async fn Interp::step_call(
  self : Interp,
  func : @ast.Expr,
  args : Array[@ast.Expr],
  keywords : Array[@ast.Keyword],
  env : Env,
  at : @ast.Expr,
  stack : Array[Frame],
) -> Ctl noraise {
  match self.resolve_class(func, env) {
    Some(entry) => {
      let exprs = args.copy()
      let kwnames : Array[String] = []
      for k in keywords {
        match k.arg {
          Some(a) => {
            kwnames.push(a)
            exprs.push(k.value)
          }
          None => return Halt(Stuck("`**` in a constructor call"))
        }
      }
      self.start_items(
        exprs,
        env,
        DoCtor(entry~, positional=args.length(), kwnames~, at~),
        stack,
      )
    }
    None => {
      // A method call on a builtin value, under a profile that has them.
      // The receiver is evaluated first and the arguments after it, which is
      // the order `func` then `args` already produced.
      if self.profile.has(BuiltinMethods) &&
        func is Attribute(value=recv, attr~, ..) {
        stack.push(MethodOn(attr~, args~, keywords~, env~, at~))
        return Ev(recv, env)
      }
      stack.push(CallOn(args~, keywords~, env~, at~))
      Ev(func, env)
    }
  }
}

///|
/// Enter a callee with its arguments: the one place a guest call becomes a
/// frame rather than a host frame.
///
/// A lambda's body is an expression and a definition's is a sequence, so the
/// two push different things on top of the boundary; a primitive answers
/// without a boundary at all, because there is nothing to return from.
///
/// `max_depth` is checked here and means what it says now -- how deep a GUEST
/// may go. It used to be a guess about the host's stack, re-measured whenever
/// the evaluator changed shape, because the evaluator's shape decided it.
async fn Interp::enter(
  self : Interp,
  callee : Value,
  actual : Array[Value],
  /// The call expression, for the aborts with no nearer span. `None` when the
  /// call came from outside the machine -- an embedder calling `apply` -- and
  /// there is no expression to point at.
  at : @ast.Expr?,
  stack : Array[Frame],
) -> Ctl noraise {
  match callee {
    Prim(p) => {
      let o = self.call_primitive(p, actual)
      if o is Aborts(_) && at is Some(node) {
        self.record(node.span())
      }
      return outcome_ctl(o)
    }
    Lam(_) | Def(_) => ()
    // eval-call-nonfun
    _ => {
      if at is Some(node) {
        self.record(node.span())
      }
      return Halt(Aborts(TypeError))
    }
  }
  self.depth += 1
  if self.depth > self.max_depth {
    self.depth -= 1
    return Halt(Stuck("a call stack deeper than \{self.max_depth}"))
  }
  match callee {
    Lam(c) => {
      let bound = match arguments(c.params.length(), c.defaults, actual) {
        Some(vs) => vs
        None => {
          self.depth -= 1
          if at is Some(node) {
            self.record(node.span())
          }
          return Halt(Aborts(TypeError))
        }
      }
      stack.push(CallBoundary(caller=self.in_module))
      // The body runs in the module it was WRITTEN in, not the one calling it,
      // so that an abort inside it is reported against the right file.
      self.in_module = c.in_module
      Ev(c.body, bind(c.env, c.params, bound))
    }
    Def(c) => {
      let d = c.region[c.index]
      let (params, args_node, body) = match d {
        FunctionDef(args~, body~, ..) =>
          (args.args.map(fn(p) { p.arg }), args, body)
        _ => {
          self.depth -= 1
          return Halt(Stuck("a definition closure over something else"))
        }
      }
      let defaults = if args_node.defaults.is_empty() {
        []
      } else {
        literal_defaults(args_node)
      }
      let bound = match arguments(params.length(), defaults, actual) {
        Some(vs) => vs
        None => {
          self.depth -= 1
          if at is Some(node) {
            self.record(node.span())
          }
          return Halt(Aborts(TypeError))
        }
      }
      // Calling one function of a mutual region rebinds the WHOLE region in
      // the callee's environment, which is what lets its siblings name each
      // other.
      let region_env = region_bindings(c.env, c.region, c.in_module)
      let inner = bind(region_env, params, bound)
      stack.push(CallBoundary(caller=self.in_module))
      self.in_module = c.in_module
      self.start_seq(@analysis.statements(body)[:], inner, stack)
    }
    _ => {
      self.depth -= 1
      Halt(Aborts(TypeError))
    }
  }
}

///|
/// The arguments a call really binds, or `None` for an arity the function has
/// no shape for.
///
/// The no-defaults path is the one every PurePy program takes and costs
/// nothing: no allocation, no walk.
fn arguments(
  arity : Int,
  defaults : Array[Value],
  actual : Array[Value],
) -> Array[Value]? {
  if actual.length() == arity {
    return Some(actual)
  }
  if defaults.is_empty() {
    return None
  }
  fill_defaults(arity, defaults, actual)
}

// ---------------------------------------------------------------------------
// Statements

///|
/// Begin a statement sequence.
fn Interp::start_seq(
  self : Interp,
  items : ArrayView[@analysis.Statement],
  env : Env,
  stack : Array[Frame],
) -> Ctl {
  self.step_seq({ items, next: 0, env, delta: @value.empty_env(), }, stack)
}

///|
/// The next statement of a sequence, or the bindings the sequence made.
fn Interp::step_seq(self : Interp, job : SeqJob, stack : Array[Frame]) -> Ctl {
  if job.next >= job.items.length() {
    return Delta(job.delta)
  }
  let item = job.items[job.next]
  job.next += 1
  stack.push(Seq(job))
  self.step_statement(item, job.env, stack)
}

///|
/// One statement: `eval_statement` and `eval_stmt`, with each recursive call
/// replaced by a frame.
fn Interp::step_statement(
  self : Interp,
  item : @analysis.Statement,
  env : Env,
  stack : Array[Frame],
) -> Ctl {
  match item {
    // eval-def: a whole region at once, each definition closing over the
    // environment the region starts in.
    Region(defs) => {
      let entries : Array[(String, Value)] = []
      for i, d in defs {
        match d {
          FunctionDef(name~, ..) =>
            entries.push(
              (
                name,
                Value::Def({
                  env,
                  region: defs,
                  index: i,
                  in_module: self.in_module,
                }),
              ),
            )
          _ => ()
        }
      }
      Delta(@value.env_of(entries))
    }
    Single(s) => step_stmt(s, env, stack)
  }
}

///|
fn step_stmt(s : @ast.Stmt, env : Env, stack : Array[Frame]) -> Ctl {
  match s {
    // eval-pass
    Pass(..) => Delta(@value.empty_env())
    // eval-assign
    Assign(targets~, value~, ..) => {
      stack.push(StAssign(target=targets[0]))
      Ev(value, env)
    }
    // eval-expr-stmt
    ExprStmt(value~, ..) => {
      stack.push(StExpr)
      Ev(value, env)
    }
    // eval-return, eval-return-none
    Return(value~, ..) =>
      match value {
        None => Ret(Value::None)
        Some(e) => {
          stack.push(StReturn)
          Ev(e, env)
        }
      }
    // eval-assert and its four companions. The message is evaluated only when
    // the condition is False, and it must be a string.
    Assert(cond~, msg~, ..) => {
      stack.push(StAssert(at=s, msg~, env~))
      Ev(cond, env)
    }
    // eval-if, eval-if-none, eval-if-else, eval-else
    If(cond~, body~, or_else~, ..) => {
      stack.push(StIf(body~, or_else~, env~))
      Ev(cond, env)
    }
    // eval-match
    Match(subject~, cases~, ..) => {
      stack.push(StMatch(cases~, env~))
      Ev(subject, env)
    }
    // eval-class, eval-class-extend
    ClassDef(name~, bases~, ..) => {
      let base = if bases.is_empty() {
        None
      } else {
        match bases[0] {
          Name(id~, ..) => Some(id)
          _ => return Halt(Stuck("a base class that is not a name"))
        }
      }
      // The class entry carries the context its base can be resolved in. At
      // run time that context is built from the environment, where the base
      // class is already a value.
      let declaring = match base {
        None => @context.empty_context()
        Some(b) =>
          match env.get(b) {
            Some(Class(be)) =>
              @context.context_of([(b, @context.Entry::Class(be))])
            _ => return Halt(Stuck("a base class that is not a class"))
          }
      }
      let module_name = match env.get("__name__") {
        Some(Str(q)) => q
        _ => "__main__"
      }
      let entry : @context.ClassEntry = {
        context: declaring,
        name: module_name + "." + name,
        own_fields: @analysis.own_fields(s),
        base,
      }
      Delta(@value.env_of([(name, Value::Class(entry))]))
    }
    _ => Halt(Stuck("statement " + s.kind_name()))
  }
}

// ---------------------------------------------------------------------------
// Resuming a frame with a value

///|
/// A frame gets the value it was waiting for.
///
/// This is the other half of `step_expr`: each arm is the code that followed a
/// recursive call, now reached by resuming instead of by returning.
async fn Interp::resume_value(
  self : Interp,
  f : Frame,
  v : Value,
  stack : Array[Frame],
) -> Ctl noraise {
  match f {
    UnOp(op~, at~) => outcome_ctl(self.sited(at, @value.unop(op, v)))
    BinRight(op~, right~, env~, at~) => {
      stack.push(BinApply(op~, left=v, at~))
      Ev(right, env)
    }
    BinApply(op~, left~, at~) =>
      outcome_ctl(self.sited(at, @value.binop(op, left, v)))
    Bool(op~, values~, next~, env~) =>
      match v {
        Bool(b) => {
          // The operand that decides stops the run; the last one stands for
          // itself.
          let decides = if op is And { !b } else { b }
          if decides || next >= values.length() {
            Rv(Bool(b))
          } else {
            stack.push(Bool(op~, values~, next=next + 1, env~))
            Ev(values[next], env)
          }
        }
        _ => Halt(Stuck("'" + op.symbol() + "' applied to " + v.kind_name()))
      }
    CmpLeft(ops~, comparators~, env~, at~) => {
      stack.push(CmpRight(ops~, comparators~, next=0, left=v, env~, at~))
      Ev(comparators[0], env)
    }
    CmpRight(ops~, comparators~, next~, left~, env~, at~) => {
      // A chain stops at the first False, and each operand is evaluated once:
      // the one just compared becomes the left of the next comparison rather
      // than being evaluated again.
      let o = self.sited(at, @value.compare(ops[next], left, v))
      match o {
        Val(Bool(true)) =>
          if next + 1 >= ops.length() {
            Rv(Bool(true))
          } else {
            stack.push(
              CmpRight(ops~, comparators~, next=next + 1, left=v, env~, at~),
            )
            Ev(comparators[next + 1], env)
          }
        _ => outcome_ctl(o)
      }
    }
    IfExp(body~, or_else~, env~) =>
      match v {
        Bool(true) => Ev(body, env)
        Bool(false) => Ev(or_else, env)
        _ => Halt(Stuck("a conditional expression on " + v.kind_name()))
      }
    Items(job) => {
      job.acc.push(v)
      self.step_items(job, stack)
    }
    DictPairs(job) =>
      // Keys and values alternate: the first arrival of a pair is its key and
      // the second is its value.
      if !job.has_key {
        match v {
          Str(s) => {
            job.key = s
            job.has_key = true
            stack.push(DictPairs(job))
            Ev(job.values[job.next], job.env)
          }
          _ => Halt(Stuck("a dict key of type " + v.kind_name()))
        }
      } else {
        job.pairs.push((job.key, v))
        job.has_key = false
        job.next += 1
        step_dict(job, stack)
      }
    Attr(attr~, at~) => outcome_ctl(self.attribute_of(v, attr, at))
    SubOn(slice~, env~, at~) =>
      match slice {
        Slice(lower~, upper~, step~, ..) =>
          self.step_slice(
            { obj: v, bounds: [lower, upper, step], next: 0, acc: [], env, at, },
            stack,
          )
        _ => {
          stack.push(SubBy(obj=v, at~))
          Ev(slice, env)
        }
      }
    SubBy(obj~, at~) => outcome_ctl(self.sited(at, @value.getitem(obj, v)))
    Slice(job) => {
      job.acc.push(Some(v))
      self.step_slice(job, stack)
    }
    FString(parts~, next~, acc~, env~) => {
      let conversion = match parts[next] {
        Hole(conversion~, ..) => conversion
        Text(_) => None
      }
      let rendered = if conversion is Some('r') { v.repr() } else { v.str() }
      match rendered {
        Some(t) => {
          acc.write_string(t)
          step_fstring(parts, next + 1, acc, env, stack)
        }
        // A closure, a module or a class has no printable form, and an
        // f-string is a print by another name.
        None => Halt(Stuck("formatting " + v.kind_name()))
      }
    }
    CallOn(args~, keywords~, env~, at~) => {
      // A keyword argument on a call that is not a constructor: the grammar
      // has no rule for one, and the checker does not look at it either.
      if !keywords.is_empty() {
        return Halt(
          Stuck("a keyword argument on a call that is not a constructor"),
        )
      }
      self.start_items(args, env, DoCall(callee=v, at~), stack)
    }
    MethodOn(attr~, args~, keywords~, env~, at~) =>
      match v {
        // A module or an object has its own attribute rule and reaches it
        // unchanged: `math.sqrt(2)` and `p.field(...)` are not method calls on
        // a builtin, and the receiver is already evaluated, so they finish
        // here rather than going round again.
        Mod(_, _) | ModStub(_) | Obj(_, _) => {
          if !keywords.is_empty() {
            return Halt(
              Stuck("a keyword argument on a call that is not a constructor"),
            )
          }
          match self.attribute_of(v, attr, at) {
            Val(callee) =>
              self.start_items(args, env, DoCall(callee~, at~), stack)
            other => Halt(other)
          }
        }
        _ => {
          if !keywords.is_empty() {
            return Halt(Stuck("a keyword argument on a method call"))
          }
          self.start_items(args, env, DoMethod(recv=v, attr~, at~), stack)
        }
      }
    // -- comprehensions ---------------------------------------------------
    CompIter(job) => self.comp_iter(job, v, stack)
    CompGuard(job~, index~) => comp_guard(job, index, v, stack)
    CompFirst(job) => comp_first(job, v, stack)
    CompSecond(job) => comp_second(job, v, stack)
    // -- statements -------------------------------------------------------
    StAssign(target~) =>
      match target {
        Name(id~, ..) => Delta(@value.env_of([(id, v)]))
        // Destructuring (#54), under a profile that opens it.
        Tuple(..) | List(..) => {
          let entries : Array[(String, Value)] = []
          match destructure(target, v, entries) {
            None => Delta(@value.env_of(entries))
            Some(why) => Halt(Stuck(why))
          }
        }
        _ => Halt(Stuck("an assignment target that is not a name"))
      }
    StExpr => Delta(@value.empty_env())
    StReturn => Ret(v)
    StAssert(at~, msg~, env~) =>
      match v {
        Bool(true) => Delta(@value.empty_env())
        Bool(false) =>
          match msg {
            None => {
              self.record(at.span())
              Halt(Aborts(AssertionError(None)))
            }
            Some(m) => {
              stack.push(StAssertMsg(at~))
              Ev(m, env)
            }
          }
        _ => Halt(Stuck("an assertion on " + v.kind_name()))
      }
    StAssertMsg(at~) =>
      match v {
        Str(w) => {
          self.record(at.span())
          Halt(Aborts(AssertionError(Some(w))))
        }
        _ => Halt(Stuck("an assertion message of type " + v.kind_name()))
      }
    StIf(body~, or_else~, env~) =>
      match v {
        Bool(true) => self.start_seq(@analysis.statements(body)[:], env, stack)
        Bool(false) =>
          if or_else.is_empty() {
            Delta(@value.empty_env())
          } else {
            self.start_seq(@analysis.statements(or_else)[:], env, stack)
          }
        _ => Halt(Stuck("an if condition on " + v.kind_name()))
      }
    // eval-match: the result carries the pattern's bindings as well as the
    // body's, composed in that order.
    StMatch(cases~, env~) =>
      match self.dispatch(env, v, cases) {
        FellThrough => Delta(@value.empty_env())
        DispatchStuck(op) => Halt(Stuck(op))
        Taken(bindings, body) => {
          stack.push(StMatchBody(bindings~))
          self.start_seq(
            @analysis.statements(body)[:],
            @value.override_env(env, bindings),
            stack,
          )
        }
      }
    // A frame that wanted a statement result, handed a value: only a call
    // boundary can be here, and only because a body ran off its end.
    _ => Rv(v)
  }
}

///|
/// A frame gets the bindings a statement made.
fn Interp::resume_delta(
  self : Interp,
  f : Frame,
  d : Env,
  stack : Array[Frame],
) -> Ctl {
  match f {
    Seq(job) => {
      // A sequence's answer is what the SEQUENCE bound, and each statement
      // runs in what the ones before it left.
      job.delta = @value.override_env(job.delta, d)
      job.env = @value.override_env(job.env, d)
      self.step_seq(job, stack)
    }
    StMatchBody(bindings~) => Delta(@value.override_env(bindings, d))
    // A body that ran off its end returns None, which is `eval-call-fallthrough`.
    CallBoundary(caller~) => {
      self.in_module = caller
      self.depth -= 1
      Rv(Value::None)
    }
    _ => Delta(d)
  }
}

///|
/// A slice's bounds, in source order, with an omitted one skipped rather than
/// given a value.
fn Interp::step_slice(
  self : Interp,
  job : SliceJob,
  stack : Array[Frame],
) -> Ctl {
  while job.next < job.bounds.length() {
    let b = job.bounds[job.next]
    job.next += 1
    match b {
      Some(e) => {
        stack.push(Slice(job))
        return Ev(e, job.env)
      }
      // An omitted bound is not `None` the PurePy value: `xs[:2]` and
      // `xs[None:2]` are different programs, so the absence survives to
      // `getslice` rather than being given a default here.
      None => job.acc.push(None)
    }
  }
  outcome_ctl(
    self.sited(
      job.at,
      @value.getslice(job.obj, {
        lower: job.acc[0],
        upper: job.acc[1],
        step: job.acc[2],
      }),
    ),
  )
}

// ---------------------------------------------------------------------------
// Comprehensions

///|
/// Where a comprehension is: the innermost open generator's environment, or
/// the enclosing one when none is open yet.
fn CompJob::here(self : CompJob) -> Env {
  match self.levels.last() {
    Some(level) =>
      @value.override_env(
        level.outer,
        @value.env_of([(level.name, level.items[level.index])]),
      )
    None => self.base
  }
}

///|
/// Decide what a comprehension does next.
///
/// Either open the next generator, or -- with all of them open and bound --
/// evaluate the element. `eval_quals` did this by recursing once per
/// generator and once per item; here the open generators are `levels`, so the
/// element expression can contain a call without the host stack knowing.
fn step_comp(job : CompJob, stack : Array[Frame]) -> Ctl {
  if job.levels.length() < job.generators.length() {
    let g = job.generators[job.levels.length()]
    stack.push(CompIter(job))
    return Ev(g.iter, job.here())
  }
  stack.push(CompFirst(job))
  Ev(job.first, job.here())
}

///|
/// A generator's iterable arrived: open the level, or finish at once when
/// there is nothing to draw from.
fn Interp::comp_iter(
  self : Interp,
  job : CompJob,
  v : Value,
  stack : Array[Frame],
) -> Ctl {
  let g = job.generators[job.levels.length()]
  let name = match g.target {
    Name(id~, ..) => id
    _ => return Halt(Stuck("a comprehension target that is not a name"))
  }
  let items = match @value.iter(v) {
    Some(xs) => xs
    // eval-qual-generator-nonseq
    None => {
      self.record(g.iter.span())
      return Halt(Aborts(TypeError))
    }
  }
  job.levels.push({ name, items, index: 0, outer: job.here(), })
  comp_enter(job, stack)
}

///|
/// Stand at the innermost level's current item, or climb out of a level that
/// has run out.
fn comp_enter(job : CompJob, stack : Array[Frame]) -> Ctl {
  for ;; {
    match job.levels.last() {
      // Every generator ran to the end: the comprehension is its answer.
      None =>
        return match job.second {
          None => Rv(List(job.out))
          Some(_) => Rv(Dict(@value.entries([], job.pairs)))
        }
      Some(level) =>
        if level.index >= level.items.length() {
          job.levels.pop() |> ignore
          // The level below moves on to its next item, and if there is none it
          // is popped too, which is what this loop is for.
          match job.levels.last() {
            Some(below) => below.index += 1
            None => ()
          }
        } else {
          // The conditions of THIS generator are checked before the ones after
          // it, which is the order `eval_quals` checked them in.
          return comp_guard_from(job, 0, stack)
        }
    }
  }
}

///|
/// The guards of the innermost level, in order.
fn comp_guard_from(job : CompJob, from : Int, stack : Array[Frame]) -> Ctl {
  let g = job.generators[job.levels.length() - 1]
  if from < g.ifs.length() {
    stack.push(CompGuard(job~, index=from))
    return Ev(g.ifs[from], job.here())
  }
  step_comp(job, stack)
}

///|
/// A guard answered.
fn comp_guard(
  job : CompJob,
  index : Int,
  v : Value,
  stack : Array[Frame],
) -> Ctl {
  match v {
    Bool(true) => comp_guard_from(job, index + 1, stack)
    Bool(false) => comp_next(job, stack)
    _ => Halt(Stuck("a comprehension guard on " + v.kind_name()))
  }
}

///|
/// Move the innermost level to its next item.
fn comp_next(job : CompJob, stack : Array[Frame]) -> Ctl {
  match job.levels.last() {
    Some(level) => level.index += 1
    None => ()
  }
  comp_enter(job, stack)
}

///|
/// The element of a list comprehension, or the key of a dict one.
fn comp_first(job : CompJob, v : Value, stack : Array[Frame]) -> Ctl {
  match job.second {
    None => {
      job.out.push(v)
      comp_next(job, stack)
    }
    Some(value) =>
      match v {
        Str(s) => {
          job.key = s
          stack.push(CompSecond(job))
          Ev(value, job.here())
        }
        _ => Halt(Stuck("a dict key of type " + v.kind_name()))
      }
  }
}

///|
/// The value of a dict comprehension.
fn comp_second(job : CompJob, v : Value, stack : Array[Frame]) -> Ctl {
  job.pairs.push((job.key, v))
  comp_next(job, stack)
}
