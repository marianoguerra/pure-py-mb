#!/usr/bin/env python3
"""The `tokens` oracle: our tokenizer against CPython's `tokenize`.

Compares the two streams token for token -- kind, text, and start and end
line:column of every one -- over every source in the conformance suite and in
`test/corpus/python/`.

Hermetic, like the rest: `test/golden/tokens.index` holds a SHA-1 of CPython's
answer per file, so a run needs neither `tools/pytokens.py` nor a Python that
can parse the file. `--regen` rewrites the index, and `--python` compares
against a freshly computed answer instead of the index, which is how a
disagreement is read.

A file CPython's tokenizer REJECTS is recorded as `!error` alone. The message
is not compared here: CPython's tokenizer messages are tuples with positions,
ours are the parser's `parse error:` text, and the place that comparison
belongs is the `parse` oracle, where the reference checker fixes the wording.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUITE = ROOT / "test" / "conformance"
CORPUS = ROOT / "test" / "corpus" / "python"
INDEX = ROOT / "test" / "golden" / "tokens.index"
DEFAULT_IMPL = ROOT / "_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
PYTOKENS = ROOT / "tools" / "pytokens.py"

GREEN, RED, DIM, RESET = "\033[32m", "\033[31m", "\033[2m", "\033[0m"


def sources() -> list[pathlib.Path]:
    files = [p for p in SUITE.rglob("*.py") if "__pycache__" not in p.parts]
    files += [p for p in CORPUS.rglob("*.py")] if CORPUS.exists() else []
    return sorted(files)


def rel(p: pathlib.Path) -> str:
    return str(p.relative_to(ROOT))


def python_answer(path: pathlib.Path) -> str:
    out = subprocess.run(
        [sys.executable, str(PYTOKENS), str(path)],
        capture_output=True, text=True, check=False,
    )
    if out.returncode != 0:
        return "!error\n"
    if out.stdout.startswith("!error"):
        return "!error\n"
    return out.stdout


def our_answer(impl: pathlib.Path, path: pathlib.Path) -> str:
    out = subprocess.run(
        [str(impl), "tokens", str(path)], capture_output=True, text=True, check=False
    )
    if out.returncode != 0 or out.stdout.startswith("!error"):
        return "!error\n"
    return out.stdout


def digest(text: str) -> str:
    return hashlib.sha1(text.encode()).hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--impl", type=pathlib.Path, default=DEFAULT_IMPL)
    ap.add_argument("--regen", action="store_true", help="rewrite the index from CPython")
    ap.add_argument("--python", action="store_true",
                    help="compare against a fresh CPython answer, not the index")
    ap.add_argument("--filter", default=None)
    ap.add_argument("--show", type=int, default=3)
    ap.add_argument("--no-ratchet", action="store_true", help="report, do not gate")
    ap.add_argument("--regen-policy", action="store_true",
                    help="move the floor to this run's result")
    args = ap.parse_args()

    files = [p for p in sources() if not args.filter or args.filter in rel(p)]

    if args.regen:
        INDEX.parent.mkdir(parents=True, exist_ok=True)
        rows = [f"{rel(p)}\t{digest(python_answer(p))}\n" for p in sources()]
        INDEX.write_text(
            "# tokens: sha1 of CPython's token stream per file, in the format\n"
            "# tools/pytokens.py prints; regenerate with tools/tokdiff.py --regen\n"
            + "".join(rows)
        )
        print(f"wrote {rel(INDEX)} ({len(rows)} files)")
        return

    if not args.impl.exists():
        sys.exit(f"{args.impl}: not built; run `moon build --target native`")

    index = {}
    if not args.python:
        if not INDEX.exists():
            sys.exit(f"{rel(INDEX)}: missing; run tools/tokdiff.py --regen")
        for line in INDEX.read_text().splitlines():
            if line and not line.startswith("#"):
                k, v = line.split("\t")
                index[k] = v

    failures = []
    passed = 0
    for p in files:
        ours = our_answer(args.impl, p)
        if args.python:
            theirs = python_answer(p)
            same = ours == theirs
        else:
            want = index.get(rel(p))
            if want is None:
                failures.append((rel(p), "no index entry", "", ""))
                continue
            same = digest(ours) == want
            theirs = ""
        if same:
            passed += 1
        else:
            failures.append((rel(p), "stream differs", ours, theirs))

    total = len(files)
    mark = GREEN + "✓" + RESET if passed == total else RED + "✗" + RESET
    print(f"{mark} tokens   {passed}/{total}")
    for name, why, ours, theirs in failures[: args.show]:
        print(f"    {name}: {why}")
        if theirs:
            a, b = ours.splitlines(), theirs.splitlines()
            for i in range(max(len(a), len(b))):
                x = a[i] if i < len(a) else "<none>"
                y = b[i] if i < len(b) else "<none>"
                if x != y:
                    print(f"      {DIM}line {i + 1}: ours {x}{RESET}")
                    print(f"      {DIM}          cpython {y}{RESET}")
                    break
    if len(failures) > args.show:
        print(f"    ... and {len(failures) - args.show} more")

    # The same ratchet the other oracles are held to, and the same file.
    policy_path = ROOT / "test" / "conform-policy.json"
    policy = json.loads(policy_path.read_text())
    if args.regen_policy:
        policy.setdefault("floors", {})["tokens"] = passed
        policy.setdefault("totals", {})["tokens"] = total
        policy_path.write_text(json.dumps(policy, indent=2, sort_keys=True) + "\n")
        print(f"wrote {rel(policy_path)}")
        return
    if args.filter or args.python or args.no_ratchet:
        sys.exit(0 if passed == total else 1)
    floor = policy.get("floors", {}).get("tokens", 0)
    if passed < floor:
        print(f"  {RED}regression{RESET}: {passed} < floor {floor}")
        sys.exit(1)
    if passed > floor:
        print(f"  unrecorded improvement: {passed} > floor {floor}; "
              f"rerun with --regen-policy and commit the change")
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
