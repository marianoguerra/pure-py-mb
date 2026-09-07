// The PurePy port. One module; packages are directories, layered strictly
// (see `implementation-plan.md` §2 and `tools/boundary-check.sh`):
//
//   basic < token < lexer          error   ast < write
//                                    \      |
//                     parser ---------+-----+
//                     sieve, analysis, context, check, value, eval, program
//                     `.` (facade) < cmd/pure-py
//
// `marianoguerra/error-report` is named by `error/` and by the CLI's renderer
// and NOWHERE else: a diagnostic is a value of this module's own type and is
// turned into a report by one adapter function.
//
// `moonbitlang/x` is named by `program/` and `cmd/pure-py/` only -- they are
// the two places that touch the filesystem, the process and its arguments.
//
// The library is wasm-first; the CLI is built with `--target native` because
// the differential harness drives it as a process.
name = "marianoguerra/pure-py"

version = "0.1.0"

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
