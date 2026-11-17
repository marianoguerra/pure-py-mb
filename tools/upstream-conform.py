#!/usr/bin/env python3
"""The specification's own conformance runner, against our CLI.

`tools/conform.py` compares us with the reference checker, message for
message, through goldens. This asks the question the specification asks of
any implementation, with its own runner (`purepy-conformance`, spec v0.24+):
the type checker's exit status and, with `--check-messages`, that its output
contains the expected error; the interpreter's output, and exit 4 on exactly
the `undefined` tests. It is the contract in the specification's README, not
a reimplementation of it.

The runner reads its suite from its package; this points it at the vendored
copy under `test/conformance/` instead, which `just suite-sync` keeps
byte-identical, so the run is about the suite this repository commits.

Needs `reference-checker/` (`just reference-fetch`) for the runner itself.

Usage: tools/upstream-conform.py [--impl PATH] [runner options...]
"""

from __future__ import annotations

import contextlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUITE = ROOT / "test" / "conformance"
CHECKER = ROOT / "reference-checker"
DEFAULT_IMPL = (
    ROOT / "_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
)


def main() -> None:
    args = sys.argv[1:]
    impl = DEFAULT_IMPL
    if args[:1] == ["--impl"]:
        impl, args = pathlib.Path(args[1]).resolve(), args[2:]
    if not impl.exists():
        sys.exit(f"{impl}: not built; run `moon build --target native`")
    if not (CHECKER / "purepy_conformance" / "__init__.py").exists():
        sys.exit("reference-checker/ is missing; run tools/fetch-reference.sh")
    sys.path.insert(0, str(CHECKER))
    import purepy_conformance as pc

    @contextlib.contextmanager
    def vendored():
        yield SUITE

    pc.suite = vendored
    pc.main([
        "--type-checker", f"{impl} check-program",
        "--check-messages",
        *args,
        f"{impl} run",
    ])


if __name__ == "__main__":
    main()
