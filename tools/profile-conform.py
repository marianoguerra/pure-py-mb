#!/usr/bin/env python3
"""The conformance harness for PROFILES, where the reference cannot be the oracle.

`tools/conform.py` drives our CLI against the reference checker's own answers.
That works because everything it tests is PurePy, and the reference decides
what PurePy is. A profile is the case the reference has no answer for: it
accepts what the reference refuses, so pointing the reference at a profile
corpus would only reproduce the refusal.

But a profile is not off the map. **Every profile feature is outside the PurePy
specification and inside Python**, which is the whole reason it is worth
adding, and CPython is already this project's oracle for what a run prints. So
the oracle for a profile is CPython, and the harness that uses it is this one.

Three questions per file, and the first is the one that makes this a profile
test rather than a Python test:

  1. **Still refused by default.** `pure-py check FILE` under `core` gives the
     exit code and message in `FILE.core.expected`. A profile that leaked into
     the default would pass questions 2 and 3 and fail this one. (The
     REFERENCE's answer for these forms is pinned separately, by `conform.py`
     over the vendored `semantically-valid/pending/` files; this pins that our
     own corpus is still opt-in.)
  2. **Accepted under the profile.** `pure-py --profile P check FILE` exits 0,
     so the sieve gate and the checker agree.
  3. **Agrees with CPython.** `pure-py --profile P run FILE` prints what
     `python3 FILE` prints. This is the conformance claim, and it is the same
     standard `conform.py`'s `run` oracle holds PurePy to.

A file under `refused/` asks the OPPOSITE of 2 and 3: it must stay refused
under every profile there is, with the message in `FILE.core.expected`. That is
the corpus form of "no profile lifts a prohibition" -- `for`, `while`, `try`,
`raise`, `del`, `+=`, item and attribute assignment -- which is the claim
everything in `docs/embedding.mbt.md` rests on and the one worth testing from
the outside rather than only in a unit test.

`test/profile-policy.json` is a ratchet that fails from both sides, exactly as
`test/conform-policy.json` does, and it is a SEPARATE file on purpose: a
profile must never be able to move a PurePy floor.

    tools/profile-conform.py
    tools/profile-conform.py --regen         # rewrite the .expected files
    tools/profile-conform.py --regen-policy  # move the floors

`--regen` writes `FILE.expected` from **python3** and `FILE.core.expected`
from our CLI under `core`. The first is an oracle and the second is a
snapshot; the docstring above says which is which so a regeneration is not
mistaken for agreement.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORPUS = ROOT / "test" / "profile"
POLICY = ROOT / "test" / "profile-policy.json"
DEFAULT_IMPL = (
    ROOT / "_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
)

GREEN, RED, YELLOW, DIM, RESET = (
    "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m",
)

REFUSED = "refused"


def run(cmd: list[str]) -> tuple[int, str]:
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def profiles() -> list[str]:
    """Every profile with a corpus: one directory per name under test/profile."""
    if not CORPUS.exists():
        return []
    return sorted(d.name for d in CORPUS.iterdir() if d.is_dir() and d.name != REFUSED)


def sources(d: pathlib.Path) -> list[pathlib.Path]:
    return sorted(d.glob("*.py"))


def strip_path(line: str, path: pathlib.Path) -> str:
    """Our CLI prints an absolute path; the expectation should not hold one."""
    return line.replace(str(path), path.name).strip()


class Report:
    def __init__(self, label: str) -> None:
        self.label, self.rows, self.bad = label, 0, []

    def add(self, key: str, why: str | None) -> None:
        self.rows += 1
        if why:
            self.bad.append((key, why))

    def show(self, limit: int) -> bool:
        ok = self.rows - len(self.bad)
        mark = GREEN + "✓" + RESET if not self.bad else RED + "✗" + RESET
        print(f"{mark} {self.label:<22} {ok}/{self.rows}")
        for key, why in self.bad[:limit]:
            print(f"    {DIM}{key}{RESET}: {why}")
        if len(self.bad) > limit:
            print(f"    {DIM}... and {len(self.bad) - limit} more{RESET}")
        return not self.bad


# --------------------------------------------------------------------------


def check_core(impl: pathlib.Path, src: pathlib.Path) -> str | None:
    """Question 1: still refused by default."""
    want_file = src.with_suffix(".core.expected")
    if not want_file.exists():
        return "no .core.expected; run --regen"
    code, out = run([str(impl), "check", str(src)])
    got = f"{code}: {strip_path(out, src)}"
    want = want_file.read_text().strip()
    return None if got == want else f"under core got {got!r}, want {want!r}"


def check_profile(impl: pathlib.Path, src: pathlib.Path, profile: str) -> str | None:
    """Question 2: accepted under the profile."""
    code, out = run([str(impl), "--profile", profile, "check", str(src)])
    if code != 0:
        return f"refused under --profile {profile}: {strip_path(out, src)}"
    return None


def run_against_python(impl: pathlib.Path, src: pathlib.Path, profile: str) -> str | None:
    """Question 3: agrees with CPython."""
    want_file = src.with_suffix(".expected")
    if not want_file.exists():
        return "no .expected; run --regen"
    code, out = run([str(impl), "--profile", profile, "run", str(src)])
    if code != 0:
        return f"run exited {code}: {strip_path(out, src)}"
    want = want_file.read_text()
    if out != want:
        return f"printed {out!r}, CPython printed {want!r}"
    return None


def stays_refused(impl: pathlib.Path, src: pathlib.Path, names: list[str]) -> str | None:
    """A prohibition, under every profile there is."""
    want_file = src.with_suffix(".core.expected")
    if not want_file.exists():
        return "no .core.expected; run --regen"
    want = want_file.read_text().strip()
    for name in ["core", *names]:
        code, out = run([str(impl), "--profile", name, "check", str(src)])
        got = f"{code}: {strip_path(out, src)}"
        if got != want:
            return f"under --profile {name} got {got!r}, want {want!r}"
    return None


# --------------------------------------------------------------------------


def regen(impl: pathlib.Path) -> None:
    names = profiles()
    for name in [*names, REFUSED]:
        d = CORPUS / name
        if not d.exists():
            continue
        for src in sources(d):
            code, out = run([str(impl), "check", str(src)])
            src.with_suffix(".core.expected").write_text(
                f"{code}: {strip_path(out, src)}\n"
            )
            if name == REFUSED:
                continue
            p = subprocess.run(
                [sys.executable, str(src)], capture_output=True, text=True
            )
            if p.returncode != 0:
                print(f"{YELLOW}! {src.name}: python3 exited {p.returncode}{RESET}")
                print(p.stderr.strip())
                continue
            src.with_suffix(".expected").write_text(p.stdout)
    print("regenerated: .core.expected from our CLI, .expected from python3")


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--impl", type=pathlib.Path, default=DEFAULT_IMPL)
    ap.add_argument("--show", type=int, default=5, help="failures to print per oracle")
    ap.add_argument("--regen", action="store_true")
    ap.add_argument("--regen-policy", action="store_true")
    args = ap.parse_args()

    if not args.impl.exists():
        print(f"pure-py binary not built: {args.impl}\n  just build")
        return 1
    if args.regen:
        regen(args.impl)
        return 0

    names = profiles()
    if not names:
        print(f"no profile corpus under {CORPUS}")
        return 1

    reports = []
    for name in names:
        opt_in = Report(f"{name}: still opt-in")
        accepts = Report(f"{name}: accepted")
        agrees = Report(f"{name}: agrees with CPython")
        for src in sources(CORPUS / name):
            key = src.name
            opt_in.add(key, check_core(args.impl, src))
            accepts.add(key, check_profile(args.impl, src, name))
            agrees.add(key, run_against_python(args.impl, src, name))
        reports += [opt_in, accepts, agrees]

    refused_dir = CORPUS / REFUSED
    if refused_dir.exists():
        rep = Report("prohibited: stays refused")
        for src in sources(refused_dir):
            rep.add(src.name, stays_refused(args.impl, src, names))
        reports.append(rep)

    ok = True
    for r in reports:
        ok &= r.show(args.show)

    # The ratchet, on the same two-sided terms as the PurePy one.
    policy = json.loads(POLICY.read_text()) if POLICY.exists() else {"floors": {}}
    floors = policy.setdefault("floors", {})
    counts = {r.label: r.rows - len(r.bad) for r in reports}
    totals = {r.label: r.rows for r in reports}
    if args.regen_policy:
        policy["floors"] = counts
        policy["totals"] = totals
        policy["note"] = (
            "A ratchet, not a target, and separate from test/conform-policy.json "
            "on purpose: a profile must never be able to move a PurePy floor. "
            "Rerun with --regen-policy and commit the moved floor in the change "
            "that earned it."
        )
        POLICY.write_text(json.dumps(policy, indent=2, sort_keys=True) + "\n")
        print("floors moved")
        return 0
    for label, got in counts.items():
        floor = floors.get(label)
        if floor is None:
            print(f"{YELLOW}! {label}: no floor recorded; --regen-policy{RESET}")
            ok = False
        elif got < floor:
            print(f"{RED}! {label}: {got} is below the floor of {floor}{RESET}")
            ok = False
        elif got > floor:
            print(f"{YELLOW}! {label}: {got} is above the floor of {floor}; "
                  f"--regen-policy{RESET}")
            ok = False
    total = sum(counts.values())
    print(f"\n{total}/{sum(totals.values())} across {len(reports)} question(s)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
