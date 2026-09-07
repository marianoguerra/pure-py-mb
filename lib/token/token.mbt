///|
/// What a token is.
///
/// Deliberately close to what CPython's `tokenize` module reports, because the
/// token oracle compares the two stream for stream. The differences are the
/// ones this port needs and `tools/pytokens.py` undoes:
///
///   * A string literal's PREFIX is part of its kind, not something to be
///     re-derived from the text. `Bytes` and `FString` are separate kinds for
///     the same reason: the sieve rejects both, by name.
///   * `tokenize` splits an f-string into `FSTRING_START`, `FSTRING_MIDDLE`
///     and `FSTRING_END`; here it is one token whose text is the whole
///     literal, its parts left unparsed (issue #55).
///   * `tokenize` has no error token: it raises. `Error` exists so that a
///     stream can be reported as far as it got.
pub(all) enum TokenKind {
  /// An identifier or a keyword. Which of the two is the parser's business:
  /// `match`, `case`, `type` and `_` are keywords only in some positions.
  Name
  Number
  /// `prefix` is as written, lowercased: "", "r", "u".
  Str(prefix~ : String)
  /// `b`, `rb`, `br`, in the case they were written in, lowercased.
  Bytes(prefix~ : String)
  /// `f`, `rf`, `fr`.
  FString(prefix~ : String)
  /// An operator or a delimiter, by its spelling: "+", "**=", "->", ":=".
  Op(String)
  /// The end of a logical line.
  Newline
  /// The end of a line that is not a logical line: blank, comment-only, or
  /// inside brackets. `tokenize` calls it NL and the parser ignores it.
  NL
  Indent
  Dedent
  Comment
  EndMarker
  /// A lexical error, with the message CPython would raise.
  Error(String)
} derive(Eq, Debug)

///|
/// A token: what it is, how it was spelled, and where.
///
/// `text` is the source's own characters -- the lexeme, not a value. A number's
/// value and a string's value are computed on demand (`int_value`,
/// `str_value`), so that a token can be reported before it is interpreted.
pub(all) struct Token {
  kind : TokenKind
  text : String
  span : @basic.Span
} derive(Eq, Debug)

///|
/// The name `tokenize` reports for this token's type, which is what the token
/// oracle compares.
pub fn TokenKind::name(self : TokenKind) -> String {
  match self {
    Name => "NAME"
    Number => "NUMBER"
    Str(..) | Bytes(..) => "STRING"
    FString(..) => "FSTRING"
    Op(_) => "OP"
    Newline => "NEWLINE"
    NL => "NL"
    Indent => "INDENT"
    Dedent => "DEDENT"
    Comment => "COMMENT"
    EndMarker => "ENDMARKER"
    Error(_) => "ERROR"
  }
}

///|
/// Whether the parser sees this token at all. Comments, `NL` and the indent
/// tokens' bookkeeping are the tokenizer's business; the rest is the parser's.
pub fn TokenKind::is_trivia(self : TokenKind) -> Bool {
  match self {
    Comment | NL => true
    _ => false
  }
}

///|
/// Whether this token is the operator spelled `s`.
pub fn Token::is_op(self : Token, s : String) -> Bool {
  self.kind is Op(t) && t == s
}

///|
/// Whether this token is the identifier `s`. Keywords are `Name` tokens, so
/// this is how the parser asks about `if` as well as about a soft keyword.
pub fn Token::is_name(self : Token, s : String) -> Bool {
  self.kind is Name && self.text == s
}

///|
/// Whether this token is any string-like literal.
pub fn Token::is_string(self : Token) -> Bool {
  match self.kind {
    Str(..) | Bytes(..) | FString(..) => true
    _ => false
  }
}

///|
/// Python 3.12's reserved words. `tokenize` reports each as a NAME and leaves
/// the distinction to the parser, and so does this port.
pub let keywords : Array[String] = [
  "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
  "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global",
  "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
  "return", "try", "while", "with", "yield",
]

///|
/// The words that are keywords only where the grammar expects them: `match`
/// and `case` head their statements, `type` heads an alias, `_` is the
/// wildcard pattern. Everywhere else each is an ordinary identifier, so
/// `match = 1` is an assignment.
pub let soft_keywords : Array[String] = ["match", "case", "type", "_"]

///|
pub fn is_keyword(s : String) -> Bool {
  keywords.contains(s)
}
