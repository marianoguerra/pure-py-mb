# The conformance suite

Copied verbatim from the reference repository, `test/` of
[pure-py/pure-py-spec](https://github.com/pure-py/pure-py-spec) at the commit
pinned in [`tools/reference.json`](../../tools/reference.json). **Do not edit
anything here**: `just suite-sync` re-copies it, and a local change would make
the port agree with a suite nobody else has.

A test's path is its specification, and `run-all.py` (the reference's own
runner, kept here for reference) reads it. `tools/conform.py` in this
repository drives our command-line tool through the same logic.

287 tests: 224 module-level sources and 63 program-level directories.
