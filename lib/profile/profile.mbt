///|
/// What a caller may opt in to on top of PurePy.
///
/// PurePy is a subset of Python and a specification, and this module ships it
/// exactly. But an embedder is not always writing to the specification: one
/// wants `a and b and c`, another wants a `str` with methods, and forking the
/// library to get either is a bad trade. A `Profile` is how they ask.
///
/// Three things about it are load-bearing.
///
///   * **`core` is the default everywhere.** Every function that takes a
///     profile takes it as an optional argument defaulting to `core`, so a
///     caller who never heard of profiles gets PurePy, message for message and
///     verdict for verdict. That is not a courtesy: `test/golden/` and
///     `test/conform-policy.json` are the reference checker's answers, and a
///     profile that moved one of them would have broken the thing being ported.
///
///   * **A profile only ever ADDS.** It is built from `core` by adding
///     features, so there is no way to spell a SUBSET of PurePy with one, and a
///     program accepted under a poorer profile is accepted under a richer one.
///
///   * **A profile may open a `not_yet` gate and may not lift a
///     `prohibited` one.** The sieve says "not yet" to a form the specification
///     intends to have and says "prohibited" to one it excludes on purpose --
///     `for`, `while`, `try`, `raise`, `del`, `+=`, item and attribute
///     assignment. The second list is what makes PurePy pure, and no profile
///     touches it. See `lib/sieve/sieve.mbt`, where the two have separate
///     helpers for exactly this reason.
///
/// This package is a LEAF: it imports nothing from the library, not even
/// `value` or `ast`. It has to be, because the checker's `context` and the
/// evaluator's `value` both consult a profile and `value` imports `context`.
/// `tools/boundary-check.sh` asserts it.

///|
/// A feature PurePy does not have and a profile may add.
///
/// The doc comment on each arm cites the upstream issue the sieve cites, so
/// the two can be read together.
///
/// Arms are APPENDED, never inserted: the derived `Compare` is tag order, and
/// tag order is the order `Profile::features` answers in. Adding one is
/// additive for a caller who builds a profile and breaking for one who matches
/// a `Feature` exhaustively, which is the usual trade for an open enum.
pub(all) enum Feature {
  /// `a and b and c`: three or more operands in one boolean expression (#82).
  ChainedBoolean
  /// `1 < x < 10`: more than one operator in one comparison (#82).
  ChainedComparison
  /// `x is None`, `x is not None` (#81). PurePy values have no identity, so
  /// this is defined against `None` -- which is a singleton in Python and the
  /// only thing `is` is reliably asked about -- and undefined elsewhere.
  Identity
  /// `xs[1:]`, `s[::-1]` (#59). Slicing is total where indexing is partial: a
  /// bound past the end clamps rather than aborting.
  Slicing
  /// `a, b = 1, 2`, and the nested `a, (b, c) = ...` (#54). `*rest` is not
  /// part of it: a starred expression is prohibited outright, so a target
  /// under this feature is always exact in its arity.
  ///
  /// A destructuring COMPREHENSION target -- `[a for a, b in items]` -- cites
  /// the same issue and is a separate gate, still closed: it binds through
  /// `eval_quals` rather than through an assignment, so it is its own rule.
  DestructuringAssignment
  /// Builtins beyond `print`, `len` and `range`: `abs`, `min`, `max`, `sum`,
  /// `sorted`, `str`, `int`, `list` and the rest of
  /// `@context.extra_builtin_names`.
  ///
  /// No syntax changes. Every one of them is pure, and none of them coerces:
  /// where Python would answer by truthiness or by treating a `bool` as a
  /// number, this is undefined, because PurePy is.
  ExtraBuiltins
  /// The non-mutating methods of `str`, `list`, `tuple` and `dict`:
  /// `"a".upper()`, `s.split(",")`, `xs.index(x)`, `d.get(k)`.
  ///
  /// Methods are not first class. `"a".upper()` is a rule about the CALL, and
  /// `f = "a".upper` stays the undefined operation it has always been -- a
  /// bound method would be a new kind of value, needing a `repr`, an `eq` and
  /// an ordering the specification does not define.
  ///
  /// Only methods that answer with a NEW value are here. `append`, `sort`,
  /// `update` and the rest of Python's mutating half are absent, and absent is
  /// the same undefined operation an unknown attribute has always been. It
  /// could not be otherwise: a `Value` is immutable and has no identity, so a
  /// mutating method has nothing to write to.
  BuiltinMethods
  /// `def f(x=1)` and `lambda x=1: x` (#56), where the default is a LITERAL
  /// int, float, str, bool or `None`.
  ///
  /// The restriction is what makes the feature small. Python evaluates a
  /// default once, when the `def` is executed, and that is observable: a
  /// default of `print("hi")` prints once however often `f` is called. This
  /// evaluator has nowhere to put a once -- calling one function of a mutual
  /// region rebinds the whole region, so a `Def` closure is rebuilt per call
  /// -- so a general default would have to be evaluated at the wrong time.
  /// A literal has no side effect and reads no name, so WHEN it is evaluated
  /// cannot be observed, and the question goes away instead of being answered
  /// wrongly. A default that is not a literal stays refused.
  DefaultArguments
  /// `f"the answer is {x}"` (#55), with `!r` and `!s` conversions.
  ///
  /// A format spec -- the `>10` of `f"{x:>10}"` -- is a language of its own,
  /// and this does not implement it. Nor the `f"{x=}"` debug form, which
  /// prints the source of the expression alongside its value. Both are still
  /// refused, and named in the message so it is clear which half was missing.
  FStrings
} derive(Eq, Compare, Hash, Debug)

///|
/// The name a `--profile` flag prints and a person reads.
pub fn Feature::name(self : Feature) -> String {
  match self {
    ChainedBoolean => "chained-boolean"
    ChainedComparison => "chained-comparison"
    Identity => "identity"
    Slicing => "slicing"
    DestructuringAssignment => "destructuring-assignment"
    ExtraBuiltins => "extra-builtins"
    BuiltinMethods => "builtin-methods"
    DefaultArguments => "default-arguments"
    FStrings => "f-strings"
  }
}

// ---------------------------------------------------------------------------

///|
/// Which superset of PurePy a caller opted in to.
///
/// A sorted set, because that is how the rest of this codebase gets a
/// deterministic order out of a set: `features` iterates it, and what
/// `pure-py profiles` prints has to be the same twice.
///
/// The field is readable, as every `pub struct` in this library is, but there
/// is no way to CONSTRUCT one except from `core` by `adding`. That is the
/// property worth having: a `Profile` is always a superset of PurePy, never a
/// subset, and no caller can spell one that takes something away.
///
/// `Eq` is derived because "did the caller ask for the same language I did?"
/// is a fair question; `Debug` because a failing test should be able to say
/// which profile it had. `adding` rather than `with` only because `with` is a
/// keyword.
pub struct Profile {
  features : @sorted_set.SortedSet[Feature]
} derive(Eq, Debug)

///|
/// PurePy exactly as specified: no feature at all, and the default of every
/// function in this library that takes a profile.
///
/// A `let` rather than a `fn`, as `@analysis.empty` is, so that the default
/// argument on a dozen public functions allocates nothing.
pub let core : Profile = { features: @sorted_set.SortedSet::new(), }

///|
/// Whether this profile has a feature. The one question the sieve, the checker
/// and the evaluator ask.
pub fn Profile::has(self : Profile, f : Feature) -> Bool {
  self.features.contains(f)
}

///|
/// This profile with more features. Stacking is this and nothing else.
pub fn Profile::adding(self : Profile, fs : Array[Feature]) -> Profile {
  let mut s = self.features
  for f in fs {
    s = s.add(f)
  }
  { features: s, }
}

///|
/// Every feature this profile has, in tag order.
pub fn Profile::features(self : Profile) -> Array[Feature] {
  self.features.iter().collect()
}

///|
/// Whether every feature of `other` is a feature of this one.
///
/// What "builds on top of" means, as a question that can be asked rather than a
/// claim in a comment.
pub fn Profile::contains(self : Profile, other : Profile) -> Bool {
  for f in other.features {
    if !self.features.contains(f) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// The named profiles, each built from the one below it.

///|
/// The features upstream has already committed to, as far as they are
/// implemented here.
///
/// Everything in it is a form the sieve refuses today with an issue number --
/// `not yet supported (#82)` and its neighbours -- which makes it the profile
/// with the least to lose: upstream intends to make these core, so this SHRINKS
/// as each one lands rather than drifting away from the specification.
///
/// It grows one feature per commit until it covers the whole table in
/// `implementation-plan.md` § "After the plan: the pending features". Ask it
/// what it holds -- `Profile::features`, or `pure-py profiles` -- rather than
/// assuming a feature from that table is in it yet.
pub fn pending() -> Profile {
  core.adding([
    ChainedBoolean,
    ChainedComparison,
    Identity,
    Slicing,
    DestructuringAssignment,
    DefaultArguments,
    FStrings,
  ])
}

///|
/// A profile by the name a `--profile` flag or a playground selector uses.
/// `pending`, and a larger set of builtin functions.
///
/// Nothing here is syntax: a program written against this profile parses as
/// PurePy and would be refused only for the NAMES it uses. That makes it the
/// cheapest superset to reason about, and the one an embedder most often
/// wants -- three builtins is a small language to write in.
pub fn builtins() -> Profile {
  pending().adding([ExtraBuiltins])
}

///|
/// `builtins`, and the non-mutating methods of the builtin types.
///
/// The largest superset here, and the one that makes PurePy read like Python
/// rather than like a calculator: `",".join(parts)`, `s.split()`,
/// `d.get(k, 0)`.
///
/// It does not make anything mutable. Every method it adds answers with a new
/// value, because a `Value` is immutable and has no identity, so there is
/// nothing a mutating one could write to -- see `lib/value/method.mbt`.
pub fn methods() -> Profile {
  builtins().adding([BuiltinMethods])
}

///|
pub fn by_name(name : String) -> Profile? {
  match name {
    "core" | "purepy" => Some(core)
    "pending" => Some(pending())
    "builtins" => Some(builtins())
    "methods" => Some(methods())
    _ => None
  }
}

///|
/// Every name `by_name` answers to, in the order they stack.
pub let names : Array[String] = ["core", "pending", "builtins", "methods"]

///|
/// Which named profile accepts a form the sieve refused, if any does.
///
/// Keyed on the feature STRING the sieve passes to `not_yet`, because
/// `@error.Kind::NotYetSupported` already carries it and nothing else names the
/// rule. That is also why this lives here and not in `lib/error`: a hint about
/// profiles is a rendering concern, and `Diagnostic::message` is compared
/// against the reference checker's output word for word.
///
/// The caller decides whether to show it. A run that asked for no profile
/// should print what it printed before profiles existed.
pub fn accepted_by(feature : String) -> String? {
  match feature {
    "chained boolean operator"
    | "chained comparison"
    | "identity operator (is/is not)"
    | "slicing"
    | "destructuring assignment"
    | "default arguments"
    | "f-strings" => Some("pending")
    _ => None
  }
}
