#!/usr/bin/env python3
"""The `ast` oracle: our parse tree against CPython's.

Compares the canonical dump (`ast::dump`, `tools/pyast_dump.py`) over every
source in the conformance suite and in `test/corpus/python/`, with and without
positions.

Hermetic: `test/golden/ast.index` and `test/golden/ast-pos.index` hold a SHA-1
of CPython's dump per file. `--regen` rewrites them; `--python` compares
against a freshly computed dump instead, which is how a disagreement is read.

A file CPython refuses to parse is recorded as `!error` alone. The message is
not compared here -- the `parse` oracle compares the reference checker's
wording, which is the one that matters.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUITE = ROOT / "test" / "conformance"
CORPUS = ROOT / "test" / "corpus" / "python"
DEFAULT_IMPL = ROOT / "_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
PYAST = ROOT / "tools" / "pyast_dump.py"
POLICY = ROOT / "test" / "conform-policy.json"

GREEN, RED, DIM, RESET = "\033[32m", "\033[31m", "\033[2m", "\033[0m"


def sources() -> list[pathlib.Path]:
    files = [p for p in SUITE.rglob("*.py") if "__pycache__" not in p.parts]
    files += list(CORPUS.rglob("*.py")) if CORPUS.exists() else []
    return sorted(files)


def rel(p: pathlib.Path) -> str:
    return str(p.relative_to(ROOT))


def python_answer(path: pathlib.Path, pos: bool) -> str:
    cmd = [sys.executable, str(PYAST), str(path)] + (["--pos"] if pos else [])
    out = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if out.returncode != 0 or out.stdout.startswith("!error"):
        return "!error\n"
    return out.stdout


def our_answer(impl: pathlib.Path, path: pathlib.Path, pos: bool) -> str:
    cmd = [str(impl), "dump", str(path)] + (["--pos"] if pos else [])
    out = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if out.returncode != 0 or out.stdout.startswith("!error"):
        return "!error\n"
    return out.stdout


def digest(text: str) -> str:
    return hashlib.sha1(text.encode()).hexdigest()


def index_path(pos: bool) -> pathlib.Path:
    return ROOT / "test" / "golden" / ("ast-pos.index" if pos else "ast.index")


def oracle_name(pos: bool) -> str:
    return "ast-pos" if pos else "ast"


def run_one(args, pos: bool) -> tuple[int, int]:
    files = [p for p in sources() if not args.filter or args.filter in rel(p)]
    index = {}
    if not args.python:
        path = index_path(pos)
        if not path.exists():
            sys.exit(f"{rel(path)}: missing; run tools/astdiff.py --regen")
        for line in path.read_text().splitlines():
            if line and not line.startswith("#"):
                k, v = line.split("\t")
                index[k] = v

    failures = []
    passed = 0
    for p in files:
        ours = our_answer(args.impl, p, pos)
        theirs = ""
        if args.python:
            theirs = python_answer(p, pos)
            same = ours == theirs
        else:
            want = index.get(rel(p))
            if want is None:
                failures.append((rel(p), "no index entry", "", ""))
                continue
            same = digest(ours) == want
        if same:
            passed += 1
        else:
            failures.append((rel(p), "tree differs", ours, theirs))

    total = len(files)
    mark = GREEN + "✓" + RESET if passed == total else RED + "✗" + RESET
    print(f"{mark} {oracle_name(pos):8} {passed}/{total}")
    for name, why, ours, theirs in failures[: args.show]:
        print(f"    {name}: {why}")
        if theirs:
            diff = list(difflib.unified_diff(
                theirs.splitlines(), ours.splitlines(),
                fromfile="cpython", tofile="ours", lineterm="", n=1))
            for line in diff[:12]:
                print(f"      {DIM}{line}{RESET}")
    if len(failures) > args.show:
        print(f"    ... and {len(failures) - args.show} more")
    return passed, total


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--impl", type=pathlib.Path, default=DEFAULT_IMPL)
    ap.add_argument("--regen", action="store_true")
    ap.add_argument("--python", action="store_true",
                    help="compare against a fresh CPython dump, not the index")
    ap.add_argument("--pos", action="store_true", help="only the positioned oracle")
    ap.add_argument("--no-pos", action="store_true", help="only the plain oracle")
    ap.add_argument("--filter", default=None)
    ap.add_argument("--show", type=int, default=3)
    ap.add_argument("--no-ratchet", action="store_true")
    ap.add_argument("--regen-policy", action="store_true")
    args = ap.parse_args()

    if args.regen:
        for pos in (False, True):
            path = index_path(pos)
            path.parent.mkdir(parents=True, exist_ok=True)
            rows = [f"{rel(p)}\t{digest(python_answer(p, pos))}\n" for p in sources()]
            path.write_text(
                f"# {oracle_name(pos)}: sha1 of CPython's tree per file, in the format\n"
                "# tools/pyast_dump.py prints; regenerate with tools/astdiff.py --regen\n"
                + "".join(rows))
            print(f"wrote {rel(path)} ({len(rows)} files)")
        return

    if not args.impl.exists():
        sys.exit(f"{args.impl}: not built; run `moon build --target native`")

    modes = [False, True]
    if args.pos:
        modes = [True]
    if args.no_pos:
        modes = [False]

    policy = json.loads(POLICY.read_text())
    failed = False
    for pos in modes:
        passed, total = run_one(args, pos)
        name = oracle_name(pos)
        if args.regen_policy:
            policy.setdefault("floors", {})[name] = passed
            policy.setdefault("totals", {})[name] = total
            continue
        if args.filter or args.python or args.no_ratchet:
            failed = failed or passed != total
            continue
        floor = policy.get("floors", {}).get(name, 0)
        if passed < floor:
            print(f"  {RED}regression{RESET}: {passed} < floor {floor}")
            failed = True
        elif passed > floor:
            print(f"  unrecorded improvement: {passed} > floor {floor}; "
                  f"rerun with --regen-policy and commit the change")
            failed = True

    if args.regen_policy:
        POLICY.write_text(json.dumps(policy, indent=2, sort_keys=True) + "\n")
        print(f"wrote {rel(POLICY)}")
        return
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
