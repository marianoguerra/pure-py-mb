#!/usr/bin/env python3
"""CPython's opinion of what our printer writes.

`ast.dump(ast.parse(unparse(f)))` must equal `ast.dump(ast.parse(f))` for
every source in the suite and the corpus: not only does our own parser read
back what we wrote, CPython does, and gets the same tree.

Needs Python 3 and the built CLI. `tools/unparse_check.sh` is the hermetic
half, and is what CI gates on.
"""

import ast
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMPL = ROOT / "_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"

GREEN, RED, RESET = "\033[32m", "\033[31m", "\033[0m"

# CPython's `Constant` carries `kind='u'` for a `u"..."` literal. This port
# does not record it: the prefix is a Python 2 compatibility spelling, the two
# literals are the same string, and neither the reference checker nor the
# semantics ever asks. So it is normalised away here rather than compared, and
# written down as a known divergence.
KIND_U = re.compile(r", kind='u'")


def main() -> None:
    if not IMPL.exists():
        sys.exit(f"{IMPL}: not built")
    files = sorted(
        [p for p in (ROOT / "test" / "conformance").rglob("*.py")
         if "__pycache__" not in p.parts]
        + list((ROOT / "test" / "corpus" / "python").rglob("*.py"))
    )
    ok = 0
    bad = []
    for f in files:
        source = f.read_text(encoding="utf-8-sig")
        try:
            want = KIND_U.sub('', ast.dump(ast.parse(source)))
        except SyntaxError:
            continue
        out = subprocess.run([str(IMPL), "unparse", str(f)],
                             capture_output=True, text=True, check=False)
        if out.returncode != 0:
            bad.append((f, "our printer refused it"))
            continue
        try:
            got = KIND_U.sub('', ast.dump(ast.parse(out.stdout)))
        except SyntaxError as e:
            bad.append((f, f"CPython cannot parse what we wrote: {e}"))
            continue
        if got == want:
            ok += 1
        else:
            bad.append((f, "the tree changed"))
    mark = GREEN + "✓" + RESET if not bad else RED + "✗" + RESET
    print(f"{mark} unparse (CPython)  {ok}/{ok + len(bad)}")
    for f, why in bad[:5]:
        print(f"    {f.relative_to(ROOT)}: {why}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
