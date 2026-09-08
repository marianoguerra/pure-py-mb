// The DEVELOPMENT module. Never published; it exists so that the conformance
// harness, the corpora, the documentation and the playground depend on the
// two published modules the way an outside consumer would -- through their
// public API only, which is what keeps that API honest.
//
// It holds everything a consumer should not have to download: the reference's
// own conformance suite, the goldens generated from it, the corpora the token
// and tree oracles compare against, the porting tools, and the playground.
// That is 832 files and half a megabyte, and none of it belongs in a package.
//
// "Never published" is a rule, not a mechanism: `moon.mod` has no `private`
// field, so a bare `moon publish` HERE would upload the whole tree under this
// name. Always `just publish-dry` and `just publish`, which can only address
// the two real modules.
name = "marianoguerra/pure-py-dev"

version = "0.0.0"

import {
  "marianoguerra/error-report@0.1.0",
  "marianoguerra/pure-py@0.5.0",
  "marianoguerra/pure-py-cli@0.5.0",
  "moonbitlang/x@0.5.1",
}

license = "Apache-2.0"

preferred_target = "wasm"

description = "Development module for pure-py-mb: conformance suite, goldens, tools, docs and playground"
