#!/usr/bin/env python3
"""The reference's sieve alone, on one file: what `pure-py parse` answers.

The reference's command line (`purepy --check`) runs the whole checker; its
sieve has no command of its own, so this calls it the way the checker does
(`check_program.check_module`, up to the parse) and prints its verdict in the
checker's format, with the checker's exit code.

Usage: PYTHONPATH=reference-checker python3 tools/ref_parse.py FILE
"""

import importlib
import pathlib
import sys

from purepy import syntax

# Not `from purepy import check_program`: the package re-exports the module's
# function of that name, which shadows the module.
check_program = importlib.import_module("purepy.check_program")


def main() -> None:
    path = pathlib.Path(sys.argv[1])
    try:
        syntax.parse_module(path.read_text(), str(path), check_program.MAIN)
        d = None
    except syntax.ParserRejects as e:
        d = check_program.diagnostic(e)
    print(check_program.format_diagnostic(d, path))
    sys.exit(check_program.exit_code(d))


if __name__ == "__main__":
    main()
