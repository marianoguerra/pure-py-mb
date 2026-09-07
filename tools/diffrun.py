#!/usr/bin/env python3
"""Run generated PurePy programs against CPython, the oracle for `run`.

The conformance suite is 136 programs somebody wrote. This is the other half:
programs nobody wrote. `test/fuzzgen` builds random trees, prints them as
source, and this compares what `pure-py run` does with what `python3` does.

Three gates decide whether a program counts, in this order:

  * **the checker.** A module `pure-py check` rejects is discarded. The
    generator is not trying to emit well-formed PurePy -- it is trying to emit
    variety, and the validator is what turns variety into a usable sample.
  * **`stuck`.** Exit 5 means the semantics has no rule for what the program
    did. That is an ANSWER, not a failure: PurePy is a subset, and every
    `excluded/` test in the conformance suite ends this way. Skipped.
  * **the allow list**, which is empty. Every divergence it once held was a
    defect: a `TypeError` this port raised where Python raises none. See
    `ALLOWED` below before adding one back.

What is left must match: the same standard output, and the same termination
kind where both end in one. The kind alone, not the message -- that is what
`.exception.expected` holds and what the suite compares.

A failure is SHRUNK before it is reported: `fuzzgen shrink` prints the simpler
trees, each is re-tested, and the smallest one that still diverges is what
gets printed. A forty line random program is not a bug report.

    tools/diffrun.py --count 300 --seed 7
    tools/diffrun.py --count 300 --seed 7 --keep /tmp/out   # save the failures
"""

from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMPL = ROOT / "_build/native/debug/build/marianoguerra/pure-py-cli/pure-py/pure-py.exe"
GEN = ROOT / "_build/native/debug/build/marianoguerra/pure-py-dev/test/fuzzgen/fuzzgen.exe"
SEP = "# ---8<---"

GREEN, RED, YELLOW, DIM, RESET = (
    "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m",
)

# Nothing is allowed to differ.
#
# There was a list here, and emptying it was the point. Every entry named a
# place this port aborted with a `TypeError` Python does not raise -- string
# concatenation, `%` on a string, a bool in arithmetic -- and each turned out
# to be a defect rather than a decision, because a termination kind is
# "named after the exception the same program raises under Python in the same
# circumstances". An implementation that has no rule says `stuck`, which this
# skips; one that claims an exception has to be right about it.
#
# If a genuine divergence ever needs recording, put it here with the decision
# it follows from -- and match it NARROWLY. The shape a deliberate divergence
# shares with a real bug is "aborted where CPython kept going", which is
# exactly what the string-concatenation defect looked like.
ALLOWED: dict[str, str] = {}


def run(cmd: list[str], cwd: pathlib.Path) -> tuple[int, str, str]:
    p = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=20,
    )
    return p.returncode, p.stdout, p.stderr


def programs(seed: int, count: int) -> list[str]:
    p = subprocess.run(
        [str(GEN), "gen", str(seed), str(count)],
        capture_output=True, text=True, check=True,
    )
    return [b for b in p.stdout.split(SEP + "\n") if b.strip()]


def shrinks(source: str) -> list[str]:
    """The generator's shrink candidates. The program goes in as an argument,
    not a path: `fuzzgen` links neither the filesystem nor the process, and
    `tools/boundary-check.sh` is what keeps it that way."""
    p = subprocess.run(
        [str(GEN), "shrink", source], capture_output=True, text=True,
    )
    if p.returncode != 0:
        return []
    return [b for b in p.stdout.split(SEP + "\n") if b.strip()]


# The last line of a traceback, ours and Python's: `TypeError` on its own, or
# `TypeError: unsupported operand ...`. Only the name is compared.
KIND = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(?::|$)")


def kind_of(stderr: str, stdout: str) -> str | None:
    for stream in (stderr, stdout):
        lines = [ln for ln in stream.splitlines() if ln.strip()]
        for ln in reversed(lines):
            if ln.startswith(" ") or ln.startswith("Traceback"):
                continue
            m = KIND.match(ln.strip())
            if m and m.group(1).endswith(("Error", "Exit", "Exception")):
                return m.group(1)
            break
    return None


class Outcome:
    """What a run amounted to: its output, and the kind it ended with."""

    def __init__(self, out: str, kind: str | None, stuck: bool = False):
        self.out, self.kind, self.stuck = out, kind, stuck

    def __eq__(self, other: object) -> bool:
        assert isinstance(other, Outcome)
        return self.out == other.out and self.kind == other.kind

    def __str__(self) -> str:
        if self.stuck:
            return f"stuck: {self.kind}"
        tail = f" !{self.kind}" if self.kind else ""
        return f"{self.out!r}{tail}"


def ours(d: pathlib.Path) -> Outcome:
    code, out, err = run([str(IMPL), "run", "main.py"], d)
    if code == 5:
        return Outcome(out, (err or out).strip(), stuck=True)
    return Outcome(out, kind_of(err, out) if code else None)


def theirs(d: pathlib.Path) -> Outcome:
    code, out, err = run([sys.executable, "main.py"], d)
    return Outcome(out, kind_of(err, out) if code else None)


def classify(source: str, a: Outcome, b: Outcome) -> str | None:
    """Which deliberate divergence this is, if it is one of them."""
    del source, a, b
    return None


def diverges(d: pathlib.Path, source: str) -> tuple[str, Outcome, Outcome] | None:
    """None when the program agrees, is undefined here, or the checker
    discarded it. The allow list is deliberately NOT consulted: shrinking has
    to be free to walk through a program that will turn out to be an allowed
    divergence, or it stops at the first one and reports the unshrunk mess
    instead."""
    (d / "main.py").write_text(source)
    if run([str(IMPL), "check", "main.py"], d)[0] != 0:
        return None  # the validator discarded it
    a, b = ours(d), theirs(d)
    if a.stuck or a == b:
        return None
    return (source, a, b)


def shrink(d: pathlib.Path, found: tuple[str, Outcome, Outcome]):
    """The smallest program reachable by dropping statements and simplifying
    expressions that still diverges. Every candidate is re-run against the
    oracle, so a shrink can only ever hand back a program that still fails --
    and it is the shrunk one the allow list gets to judge, where the signature
    is a line long and means what it says."""
    best = found
    changed = True
    while changed:
        changed = False
        for cand in shrinks(best[0]):
            got = diverges(d, cand)
            if got is not None and len(cand) < len(best[0]):
                best, changed = got, True
                break
    return best


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keep", type=pathlib.Path,
                    help="directory to write the failing programs into")
    ap.add_argument("--no-allow", action="store_true",
                    help="report the deliberate divergences too")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    for path, what in ((IMPL, "pure-py"), (GEN, "fuzzgen")):
        if not path.exists():
            sys.exit(f"{what} is not built; run `moon build --target native`")

    allow = not args.no_allow
    stats = {"generated": 0, "discarded": 0, "stuck": 0, "allowed": 0,
             "agreed": 0, "diverged": 0}
    reasons: dict[str, int] = {}
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        d = pathlib.Path(tmp)
        for source in programs(args.seed, args.count):
            stats["generated"] += 1
            (d / "main.py").write_text(source)
            if run([str(IMPL), "check", "main.py"], d)[0] != 0:
                stats["discarded"] += 1
                continue
            a, b = ours(d), theirs(d)
            if a.stuck:
                stats["stuck"] += 1
                continue
            if a == b:
                stats["agreed"] += 1
                continue
            # Shrink first: the allow list judges the minimal program, where
            # what it is looking at is one line and unambiguous.
            found = shrink(d, (source, a, b))
            why = classify(*found)
            if allow and why is not None:
                stats["allowed"] += 1
                reasons[why] = reasons.get(why, 0) + 1
                continue
            stats["diverged"] += 1
            failures.append(found)

    if not args.quiet:
        print(
            f"{stats['generated']} generated, "
            f"{stats['discarded']} discarded by the checker, "
            f"{stats['stuck']} undefined, "
            f"{stats['allowed']} allowed to differ"
        )
        for why, n in sorted(reasons.items()):
            print(f"  {DIM}{n:4} {why}: {ALLOWED[why]}{RESET}")
    verdict = f"{stats['agreed']} agreed with CPython, {stats['diverged']} did not"
    if failures:
        print(f"{RED}✗{RESET} {verdict}")
        for i, (source, a, b) in enumerate(failures):
            print(f"\n{DIM}{'-' * 70}{RESET}")
            print(source.rstrip())
            print(f"  {RED}pure-py{RESET}: {a}")
            print(f"  {GREEN}cpython{RESET}: {b}")
            if args.keep:
                args.keep.mkdir(parents=True, exist_ok=True)
                (args.keep / f"fail{i}.py").write_text(source)
        if args.keep:
            print(f"\nwritten to {args.keep}")
        return 1
    print(f"{GREEN}✓{RESET} {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
