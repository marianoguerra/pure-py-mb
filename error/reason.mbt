///|
/// Why a module is not well formed.
///
/// One arm per class in the reference's `reasons.py`, carrying the same
/// fields, and `message` reproduces the Python f-strings character for
/// character: these are the `.error.expected` files of the conformance suite's
/// static buckets, so the wording is fixed by the oracle and not by taste.
pub(all) enum Reason {
  DuplicateFieldName(name~ : String, cls~ : String)
  UnknownBaseClass(base~ : String)
  InheritedFieldClash(field~ : String, base~ : String)
  DuplicateClassName(name~ : String, in_module~ : String)
  UnassignedVariable(name~ : String)
  CapturedReassignment(name~ : String)
  SelfCaptureAssignment(name~ : String)
  CapturedGeneratorVariable(name~ : String)
  UnreachableStatement
  ConstructorArityMismatch(cls~ : String, expected~ : Int, got~ : Int)
  UnknownConstructorKeyword(cls~ : String, expected_fields~ : Array[String])
  PatternArityMismatch(cls~ : String, expected~ : Int, got~ : Int)
  UnknownClassInPattern(cls~ : String)
  UnknownFieldInPattern(cls~ : String, expected_fields~ : Array[String])
  DuplicatePatternKeyword(cls~ : String)
  DuplicateDictKey(key~ : String)
  NonlinearPattern(index~ : Int)
  UnreachableCase(index~ : Int, subsumed_by~ : Int)
  DuplicateMutualName(name~ : String)
  NonTopLevelImport
  ImportAfterStatement
  SubmoduleNameClash(name~ : String, submodule~ : String)
  SubmoduleNotImported(q~ : String)
  UnassignedMember(x~ : String, q~ : String)
  TopLevelReturn
  EmptyFromImport
  UnknownModule(q~ : String)
  UnknownMember(x~ : String, q~ : String)
  ModuleAsValue(name~ : String)
  OwnDescendantImport(q~ : String, q0~ : String)
  ClassAsValue(name~ : String)
} derive(Eq, Debug)

///|
/// The message, exactly as `reasons.py` writes it.
pub fn Reason::message(self : Reason) -> String {
  match self {
    DuplicateFieldName(name~, cls~) =>
      "duplicate field name '\{name}' in class '\{cls}'"
    UnknownBaseClass(base~) =>
      "base class '\{base}' is not declared in this module"
    InheritedFieldClash(field~, base~) =>
      "field '\{field}' clashes with inherited field from '\{base}'"
    DuplicateClassName(name~, in_module~) =>
      "duplicate class name '\{name}' in module '\{in_module}'"
    UnassignedVariable(name~) => "'\{name}' is not definitely assigned"
    CapturedReassignment(name~) =>
      "'\{name}' captured by previous statement, reassigned here"
    SelfCaptureAssignment(name~) => "'\{name}' captured by right-hand side"
    CapturedGeneratorVariable(name~) =>
      "'\{name}' bound by a generator, captured by a lambda"
    UnreachableStatement => "unreachable statement"
    ConstructorArityMismatch(cls~, expected~, got~) =>
      "constructor for '\{cls}' expects \{expected} arguments, got \{got}"
    UnknownConstructorKeyword(cls~, expected_fields~) =>
      "constructor keywords for '\{cls}' must be " + expected_fields.join(", ")
    PatternArityMismatch(cls~, expected~, got~) =>
      "pattern for '\{cls}' expects \{expected} sub-patterns, got \{got}"
    UnknownClassInPattern(cls~) => "'\{cls}' is not a declared class"
    UnknownFieldInPattern(cls~, expected_fields~) =>
      "pattern keywords for '\{cls}' must be " + expected_fields.join(", ")
    DuplicatePatternKeyword(cls~) => "duplicate keyword in pattern for '\{cls}'"
    DuplicateDictKey(key~) => "duplicate key '\{key}' in dict pattern"
    NonlinearPattern(index~) => "repeated variable in pattern \{index}"
    UnreachableCase(index~, subsumed_by~) =>
      "case \{index} unreachable: subsumed by case \{subsumed_by}"
    DuplicateMutualName(name~) => "duplicate name '\{name}' in mutual region"
    NonTopLevelImport => "import only allowed at module top level"
    ImportAfterStatement => "imports must precede all other statements"
    SubmoduleNameClash(name~, submodule~) =>
      "binding '\{name}' clashes with submodule '\{submodule}'"
    SubmoduleNotImported(q~) => "submodule '\{q}' is not imported"
    UnassignedMember(x~, q~) =>
      "member '\{x}' of module '\{q}' is not definitely assigned"
    TopLevelReturn =>
      "top-level return not allowed (module body must not return)"
    EmptyFromImport => "empty name list"
    // Python's `repr` of the name, which is what `{q!r}` writes.
    UnknownModule(q~) => "unknown module " + @basic.py_repr(q)
    UnknownMember(x~, q~) =>
      "module " + @basic.py_repr(q) + " has no member " + @basic.py_repr(x)
    ModuleAsValue(name~) =>
      "'\{name}' refers to a module; modules are not first-class values"
    OwnDescendantImport(q~, q0~) =>
      "'\{q}' is a descendant of the importing module '\{q0}'; import it with a from-import"
    ClassAsValue(name~) =>
      "'\{name}' refers to a class; classes are not first-class values"
  }
}

///|
/// A short, stable code for a reason, for `--error-format json` and for a
/// person searching: `purepy::unassigned-variable`.
pub fn Reason::code(self : Reason) -> String {
  let name = match self {
    DuplicateFieldName(..) => "duplicate-field-name"
    UnknownBaseClass(..) => "unknown-base-class"
    InheritedFieldClash(..) => "inherited-field-clash"
    DuplicateClassName(..) => "duplicate-class-name"
    UnassignedVariable(..) => "unassigned-variable"
    CapturedReassignment(..) => "captured-reassignment"
    SelfCaptureAssignment(..) => "self-capture-assignment"
    CapturedGeneratorVariable(..) => "captured-generator-variable"
    UnreachableStatement => "unreachable-statement"
    ConstructorArityMismatch(..) => "constructor-arity-mismatch"
    UnknownConstructorKeyword(..) => "unknown-constructor-keyword"
    PatternArityMismatch(..) => "pattern-arity-mismatch"
    UnknownClassInPattern(..) => "unknown-class-in-pattern"
    UnknownFieldInPattern(..) => "unknown-field-in-pattern"
    DuplicatePatternKeyword(..) => "duplicate-pattern-keyword"
    DuplicateDictKey(..) => "duplicate-dict-key"
    NonlinearPattern(..) => "nonlinear-pattern"
    UnreachableCase(..) => "unreachable-case"
    DuplicateMutualName(..) => "duplicate-mutual-name"
    NonTopLevelImport => "non-top-level-import"
    ImportAfterStatement => "import-after-statement"
    SubmoduleNameClash(..) => "submodule-name-clash"
    SubmoduleNotImported(..) => "submodule-not-imported"
    UnassignedMember(..) => "unassigned-member"
    TopLevelReturn => "top-level-return"
    EmptyFromImport => "empty-from-import"
    UnknownModule(..) => "unknown-module"
    UnknownMember(..) => "unknown-member"
    ModuleAsValue(..) => "module-as-value"
    OwnDescendantImport(..) => "own-descendant-import"
    ClassAsValue(..) => "class-as-value"
  }
  "purepy::" + name
}
