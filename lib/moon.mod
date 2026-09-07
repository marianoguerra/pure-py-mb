// The LIBRARY, and the only thing most consumers want: the tokenizer, the
// parser, the sieve, the checker, the printer, the interpreter and the
// embedding interface.
//
// It lives in a directory of its own so that publishing it does not publish
// the conformance suite. `moon publish` packages a module's whole directory
// tree, and `moon.mod` has no way to leave part of it out -- `exclude`,
// `include` and `files` are all rejected -- so the only way to ship a
// library without its 832 test fixtures is for the library to be the module.
//
// Layering is strict and gated by `tools/boundary-check.sh` (see
// `implementation-plan.md` §2):
//
//   basic < token < lexer          error   ast < write
//                                    \      |
//                     parser ---------+-----+
//                     sieve, analysis, context, check, value, eval, program
//                     `.` (facade)
//
// `marianoguerra/error-report` is named by `error/` and nowhere else: a
// diagnostic is a value of this module's own type, and ONE function turns it
// into a report.
//
// `moonbitlang/x` is named by `program/` alone -- the one place that touches
// a filesystem, and only to turn a directory into a `SourceTree` value. An
// embedder that has its guest's code in hand never reaches it.
name = "marianoguerra/pure-py"

version = "0.2.0"

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/pure-py-mb"

license = "Apache-2.0"

keywords = [ "python", "parser", "interpreter", "purepy" ]

import {
  "marianoguerra/error-report@0.1.0",
  "moonbitlang/x@0.5.1",
}

preferred_target = "wasm"

description = "PurePy (a pure functional subset of Python 3.12): tokenizer, parser, checker and interpreter"
