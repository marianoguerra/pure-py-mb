#!/usr/bin/env python3
"""The reference's sieve alone, on one file: what `pure-py parse` answers.

The reference's command line (`python -m purepy --check`) runs the whole
checker; its sieve has no command of its own since v0.22, so this calls it
the way the checker does, and prints its verdict in the checker's format.

Usage: PYTHONPATH=reference/src python3 tools/ref_parse.py FILE
"""

import sys

from purepy import syntax


def main() -> None:
    filename = sys.argv[1]
    with open(filename) as f:
        source = f.read()
    try:
        result = syntax.check_syntax_module(syntax.parse(source, filename))
    except SyntaxError as e:
        result = syntax.ParseError(e)
    print(syntax.format_result(result, filename))
    sys.exit(0 if result is None else result.exit_code)


if __name__ == "__main__":
    main()
