///|
/// Why a module is not well formed.
///
/// One arm per class in the reference's `reasons.py`, carrying the same
/// fields, and `message` reproduces the Python f-strings character for
/// character: these are the `.error.expected` files of the conformance suite's
/// static buckets, so the wording is fixed by the oracle and not by taste.
///
/// A type in a message is carried already RENDERED, as the string `render`
/// in `lib/types` makes of it: this package sits below the type checker and
/// knows nothing of types but how they read.
pub(all) enum Reason {
  DuplicateField(x~ : String, c~ : String)
  UndefinedVariable(x~ : String)
  UnassignedVariable(x~ : String)
  PossiblyUnassigned(x~ : String)
  UnboundName(x~ : String)
  Redeclaration(x~ : String)
  UndeclaredAssignment(x~ : String)
  AssignmentBeforeDeclaration(x~ : String)
  Reassignment(x~ : String)
  MaybeAssigned(x~ : String)
  CapturedGeneratorVariable(x~ : String)
  UnreachableStatement
  ConstructorArityMismatch(c~ : String, expected~ : Int32, got~ : Int32)
  UnknownConstructorKeyword(c~ : String, xs~ : Array[String])
  PatternArityMismatch(c~ : String, expected~ : Int32, got~ : Int32)
  NotPredefinedName(x~ : String)
  NotClass(q~ : String)
  UnknownFieldInPattern(c~ : String, xs~ : Array[String])
  DuplicatePatternKeyword(c~ : String)
  DuplicateDictKey(w~ : String)
  NonlinearPattern(x~ : String)
  DuplicateMember(x~ : String, q~ : String)
  SubmoduleNotImported(q~ : String)
  UnassignedMember(x~ : String, q~ : String)
  TopLevelReturn
  UnknownModule(q~ : String)
  UnknownMember(x~ : String, q~ : String)
  ModuleAsValue(q~ : String)
  ImportOfContainedModule(q~ : String, q_~ : String, from_import~ : String)
  PredefinedNameAsValue(q~ : String)
  ClassAsValue(q~ : String)
  NoBinaryOverload(op~ : String, sigma~ : String, sigma_~ : String)
  NoUnaryOverload(op~ : String, sigma~ : String)
  NotCallable(tau~ : String)
  CallArityMismatch(expected~ : Int32, given~ : Int32)
  TypeMismatch(expected~ : String, actual~ : String)
  LambdaTypeMismatch(expected~ : String, arity~ : Int32?)
  NotSubscriptable(tau~ : String)
  TupleIndexOutOfRange(index~ : BigInt, length~ : Int32)
  UnreachableCase(index~ : Int32)
  SequenceKindMismatch(kind~ : String, tau~ : String)
  NotIterable(tau~ : String)
  UnknownField(c~ : String, x~ : String)
  NotSynthesised
  NoAttributes(tau~ : String)
  MissingReturn(x~ : String, tau~ : String)
  /// Not the reference's: a method a profile's table does not have, on a
  /// value of a type that has methods under that profile.
  UnknownMethod(tau~ : String, x~ : String)
} derive(Eq, Debug)

///|
/// The message, exactly as `reasons.py` writes it.
pub fn Reason::message(self : Reason) -> String {
  match self {
    DuplicateField(x~, c~) => "duplicate field '\{x}' in class '\{c}'"
    UndefinedVariable(x~) => "'\{x}' is not defined"
    UnassignedVariable(x~) => "'\{x}' is declared but not yet assigned"
    PossiblyUnassigned(x~) => "'\{x}' is not definitely assigned"
    UnboundName(x~) => "'\{x}' is unbound"
    Redeclaration(x~) => "'\{x}' is already declared"
    UndeclaredAssignment(x~) => "'\{x}' is assigned but never declared"
    AssignmentBeforeDeclaration(x~) =>
      "'\{x}' is assigned before its declaration"
    Reassignment(x~) => "'\{x}' is already assigned"
    MaybeAssigned(x~) => "'\{x}' may already be assigned"
    CapturedGeneratorVariable(x~) =>
      "'\{x}' bound by generator, captured by lambda"
    UnreachableStatement => "unreachable statement"
    ConstructorArityMismatch(c~, expected~, got~) =>
      "constructor for '\{c}' expects \{expected} arguments, got \{got}"
    UnknownConstructorKeyword(c~, xs~) =>
      "constructor keywords for '\{c}' must be " + xs.join(", ")
    PatternArityMismatch(c~, expected~, got~) =>
      "pattern for '\{c}' expects \{expected} sub-patterns, got \{got}"
    NotPredefinedName(x~) => "'\{x}' is not bound as a predefined name"
    NotClass(q~) => "'\{q}' is not a declared class"
    UnknownFieldInPattern(c~, xs~) =>
      "pattern keywords for '\{c}' must be " + xs.join(", ")
    DuplicatePatternKeyword(c~) => "duplicate keyword in pattern for '\{c}'"
    DuplicateDictKey(w~) => "duplicate key '\{w}' in dict pattern"
    NonlinearPattern(x~) => "repeated variable '\{x}' in pattern"
    DuplicateMember(x~, q~) =>
      "duplicate member of module '\{q}': it defines '\{x}' and also has submodule '\{q}.\{x}'"
    SubmoduleNotImported(q~) => "submodule '\{q}' is not imported"
    UnassignedMember(x~, q~) =>
      "member '\{x}' of module '\{q}' is not definitely assigned"
    TopLevelReturn =>
      "top-level return not allowed (module body must not return)"
    UnknownModule(q~) => "unknown module '\{q}'"
    UnknownMember(x~, q~) => "module '\{q}' has no member '\{x}'"
    ModuleAsValue(q~) =>
      "'\{q}' refers to a module; modules are not first-class values"
    ImportOfContainedModule(q~, q_~, from_import~) =>
      "'\{q}' is contained in importing module '\{q_}'; plain import not allowed, write '\{from_import}'"
    PredefinedNameAsValue(q~) =>
      "'\{q}' is usable only in annotations or as a decorator"
    ClassAsValue(q~) =>
      "'\{q}' refers to a class; classes are not first-class values"
    NoBinaryOverload(op~, sigma~, sigma_~) =>
      "no overload of '\{op}' at operand types \{sigma} and \{sigma_}"
    NoUnaryOverload(op~, sigma~) =>
      "no overload of '\{op}' at operand type \{sigma}"
    NotCallable(tau~) => "values of type \{tau} cannot be called"
    CallArityMismatch(expected~, given~) =>
      "call expects \{expected} arguments, given \{given}"
    TypeMismatch(expected~, actual~) =>
      "expected type \{expected}, given \{actual}"
    LambdaTypeMismatch(expected~, arity~) => {
      let given = match arity {
        None => "a lambda"
        Some(n) =>
          "a lambda of \{n} parameter" + (if n == 1 { "" } else { "s" })
      }
      "expected type \{expected}, given \{given}"
    }
    NotSubscriptable(tau~) => "values of type \{tau} cannot be subscripted"
    TupleIndexOutOfRange(index~, length~) =>
      "index \{index} out of range for tuple of length \{length}"
    UnreachableCase(index~) => "case \{index} is unreachable"
    SequenceKindMismatch(kind~, tau~) =>
      "\{kind} pattern requires values of \{kind} type, not \{tau}"
    NotIterable(tau~) => "values of type \{tau} cannot be iterated"
    UnknownField(c~, x~) => "class '\{c}' has no field '\{x}'"
    NotSynthesised => "cannot infer type of this expression"
    NoAttributes(tau~) => "values of type \{tau} have no attributes"
    MissingReturn(x~, tau~) =>
      "'\{x}' declares result type \{tau} but does not always return"
    UnknownMethod(tau~, x~) => "values of type \{tau} have no method '\{x}'"
  }
}

///|
/// A short, stable code for a reason, for `--error-format json` and for a
/// person searching: `purepy::unassigned-variable`.
pub fn Reason::code(self : Reason) -> String {
  let name = match self {
    DuplicateField(..) => "duplicate-field"
    UndefinedVariable(..) => "undefined-variable"
    UnassignedVariable(..) => "unassigned-variable"
    PossiblyUnassigned(..) => "possibly-unassigned"
    UnboundName(..) => "unbound-name"
    Redeclaration(..) => "redeclaration"
    UndeclaredAssignment(..) => "undeclared-assignment"
    AssignmentBeforeDeclaration(..) => "assignment-before-declaration"
    Reassignment(..) => "reassignment"
    MaybeAssigned(..) => "maybe-assigned"
    CapturedGeneratorVariable(..) => "captured-generator-variable"
    UnreachableStatement => "unreachable-statement"
    ConstructorArityMismatch(..) => "constructor-arity-mismatch"
    UnknownConstructorKeyword(..) => "unknown-constructor-keyword"
    PatternArityMismatch(..) => "pattern-arity-mismatch"
    NotPredefinedName(..) => "not-predefined-name"
    NotClass(..) => "not-class"
    UnknownFieldInPattern(..) => "unknown-field-in-pattern"
    DuplicatePatternKeyword(..) => "duplicate-pattern-keyword"
    DuplicateDictKey(..) => "duplicate-dict-key"
    NonlinearPattern(..) => "nonlinear-pattern"
    DuplicateMember(..) => "duplicate-member"
    SubmoduleNotImported(..) => "submodule-not-imported"
    UnassignedMember(..) => "unassigned-member"
    TopLevelReturn => "top-level-return"
    UnknownModule(..) => "unknown-module"
    UnknownMember(..) => "unknown-member"
    ModuleAsValue(..) => "module-as-value"
    ImportOfContainedModule(..) => "import-of-contained-module"
    PredefinedNameAsValue(..) => "predefined-name-as-value"
    ClassAsValue(..) => "class-as-value"
    NoBinaryOverload(..) => "no-binary-overload"
    NoUnaryOverload(..) => "no-unary-overload"
    NotCallable(..) => "not-callable"
    CallArityMismatch(..) => "call-arity-mismatch"
    TypeMismatch(..) => "type-mismatch"
    LambdaTypeMismatch(..) => "lambda-type-mismatch"
    NotSubscriptable(..) => "not-subscriptable"
    TupleIndexOutOfRange(..) => "tuple-index-out-of-range"
    UnreachableCase(..) => "unreachable-case"
    SequenceKindMismatch(..) => "sequence-kind-mismatch"
    NotIterable(..) => "not-iterable"
    UnknownField(..) => "unknown-field"
    NotSynthesised => "not-synthesised"
    NoAttributes(..) => "no-attributes"
    MissingReturn(..) => "missing-return"
    UnknownMethod(..) => "unknown-method"
  }
  "purepy::" + name
}

///|
#deprecated(skip_current_package=true)
#doc(hidden)
pub extend Reason with Eq::{not_equal, equal}

///|
#deprecated(skip_current_package=true)
#doc(hidden)
pub extend Reason with Debug::{to_repr}
