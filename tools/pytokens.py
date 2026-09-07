#!/usr/bin/env python3
"""CPython's answer for the `tokens` oracle.

Prints one line per token, `L:C-L:C KIND text`, with `text` as Python `repr`
and columns in CODE POINTS (which is what `tokenize` reports; CPython's `ast`
counts UTF-8 bytes instead, and that difference is `Source::byte_col`).

Three adjustments, each of which `pure-py tokens` matches on its side:

  * ENCODING is dropped. It is a fact about the bytes, not about the program,
    and this port reads text.
  * An f-string arrives from `tokenize` as FSTRING_START, some MIDDLEs and
    OPs and expressions, then FSTRING_END. It is collapsed back into one
    FSTRING token spanning the whole literal, because PurePy's sieve rejects
    f-strings whole (issue #55) and the parser never looks inside one.
  * A trailing NEWLINE that `tokenize` synthesises for a file with no final
    newline is kept: so does this port.
"""

from __future__ import annotations

import io
import sys
import token as tok
import tokenize


def collapse(toks: list[tokenize.TokenInfo]) -> list[tuple]:
    out: list[tuple] = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.type == tok.ENCODING:
            i += 1
            continue
        if t.type == getattr(tok, "FSTRING_START", -1):
            depth = 0
            start, j = t.start, i
            while j < len(toks):
                u = toks[j]
                if u.type == getattr(tok, "FSTRING_START", -1):
                    depth += 1
                elif u.type == getattr(tok, "FSTRING_END", -1):
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            end = toks[j].end
            out.append((start, end, "FSTRING", None))
            i = j + 1
            continue
        name = tok.tok_name[t.type]
        out.append((t.start, t.end, name, t.string))
        i += 1
    return out


def main() -> None:
    path = sys.argv[1]
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8-sig")
    lines = text.splitlines(keepends=True)

    def segment(start: tuple[int, int], end: tuple[int, int]) -> str:
        if start[0] == end[0]:
            return lines[start[0] - 1][start[1] : end[1]] if start[0] <= len(lines) else ""
        first = lines[start[0] - 1][start[1] :]
        middle = "".join(lines[start[0] : end[0] - 1])
        last = lines[end[0] - 1][: end[1]] if end[0] <= len(lines) else ""
        return first + middle + last

    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError) as e:
        print(f"!error {e}")
        return

    for start, end, name, string in collapse(toks):
        if string is None:
            string = segment(start, end)
        print(f"{start[0]}:{start[1]}-{end[0]}:{end[1]} {name} {string!r}")


if __name__ == "__main__":
    main()
