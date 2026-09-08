// The COMMAND, in a module of its own so that a consumer who wants the
// library does not fetch a renderer, and a person who wants the tool can have
// it without the library's test fixtures.
//
// It is the thing the conformance harness drives: its exit codes are part of
// the specification (`implementation-plan.md` §2.1) and not a convenience,
// because the suite compares this binary with the reference's own scripts.
//
// Built with `--target native`, because the harness runs it once per test.
name = "marianoguerra/pure-py-cli"

version = "0.9.0"

readme = "README.md"

repository = "https://github.com/marianoguerra/pure-py-mb"

license = "Apache-2.0"

keywords = [ "python", "parser", "interpreter", "purepy", "cli" ]

import {
  "marianoguerra/error-report@0.1.0",
  "marianoguerra/pure-py@0.9.0",
  "moonbitlang/x@0.5.1",
}

description = "The pure-py command: tokenize, parse, check and run PurePy"
