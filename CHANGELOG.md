# Changelog

## Unreleased

The first working version: PurePy's tokenizer, parser, sieve, checker,
printer and interpreter, with the conformance suite passing in full.

### What it does

- **Tokenizes** Python 3.12, matching CPython's `tokenize` token for token
  and column for column over 413 sources.
- **Parses** into a CPython-shaped tree, matching CPython's `ast` node for
  node and position for position over the same 413.
- **Prints** a tree back as Python that parses to the same tree, checked both
  through this parser and through CPython's.
- **Rejects** what PurePy excludes syntactically, reproducing the reference's
  message and position for every source in the suite.
- **Decides** module and program well-formedness, likewise.
- **Evaluates** modules and programs, matching CPython's output.

### Conformance

| oracle | result |
|---|---|
| tokens against CPython | 413/413 |
| trees against CPython, without positions | 413/413 |
| trees against CPython, with positions | 413/413 |
| the printer's round trip | 412/412 |
| `parse` against the reference | 392/392 |
| `check` against the reference | 392/392 |
| `check-program` against the reference | 63/63 |
| `run` against CPython | 136/136 |

### Decisions

Each is a judgement the specification leaves open, recorded where it is made:

- An operation the semantics leaves undefined **aborts**, with exit code 5 and
  the operation named, rather than falling back to Python's answer. Chapter 1
  allows either; aborting is what makes the suite's dynamically excluded
  bucket a checked claim.
- A module is **loaded once per run**. The spec needs no cache because loading
  is deterministic; what loading prints is not, and CPython prints once.
- **`typing` exposes `Any` alone.** Figure 2.7 of the spec also lists
  `Callable` and the reference checker does not; the reference is the oracle.
- **Arithmetic aborts `TypeError` when an operand is not a number**, which is
  the sentence in the spec's own table, so string concatenation aborts.
  Ordering has no such sentence, so a bool against an int is undefined
  instead. Nothing in the conformance suite reaches either.
- **Integers are `BigInt`** throughout, and an integer compares with a float
  exactly rather than through a conversion.
- **Strings are UTF-16 with a code-point view.** `len`, indexing, iteration
  and pattern matching all count code points, as Python does.
- **Identifier classes are approximated** by printability rather than the full
  XID tables; the conformance suite is ASCII.
- **`Constant.kind` is not recorded.** CPython sets it to `'u'` for a `u"..."`
  literal; nothing in PurePy asks, and the two literals are the same string.

### Packaging

The published module carries its conformance suite: `test/conformance/` is
the reference's own 392 sources, and `test/golden/` the reference's answers
for them. `moon.mod` has no way to leave them out, and they are what makes
the suite hermetic -- a consumer who wants to know what this port agrees with
has it in hand. The zip is about half a megabyte.
