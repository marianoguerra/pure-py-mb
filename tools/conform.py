#!/usr/bin/env python3
"""The conformance harness: our CLI against the PurePy reference.

The suite under `test/conformance/` is the reference's own, copied verbatim.
`test/conformance/run-all.py` drives the reference's Python scripts; this
script drives OUR command-line tool the same way, so the two can be compared
directly.

Four oracles, three of them golden-file comparisons and one verdict-driven:

  parse    `pure-py parse FILE`         vs test/golden/parse.txt
  check    `pure-py check FILE`         vs test/golden/check.txt
  program  `pure-py check-program main.py` vs test/golden/program.txt
  run      `pure-py run ...`            vs the suite's own .expected files

The goldens are the REFERENCE's answers -- exit code and message, for every
one of the suite's .py files, not only the ones the reference's runner
asserts on. They are committed, so `conform.py` needs neither Python's `ast`
nor the `reference/` checkout. Regenerating them does:

  tools/conform.py --reference --regen      needs reference/ (see fetch-reference.sh)

`test/conform-policy.json` is a ratchet: each oracle has a floor, and a run
fails when it drops BELOW the floor (a regression) or rises ABOVE it (an
improvement nobody recorded). `--regen-policy` moves the floors to what the
run actually achieved; the diff is the review artifact.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUITE = ROOT / "test" / "conformance"
GOLDEN = ROOT / "test" / "golden"
POLICY = ROOT / "test" / "conform-policy.json"
REFERENCE = ROOT / "reference"
DEFAULT_IMPL = ROOT / "_build" / "native" / "debug" / "build" / "cmd" / "pure-py" / "pure-py.exe"

GREEN, RED, YELLOW, DIM, RESET = (
    "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m",
)

MODULE_LEVEL, PROGRAM_LEVEL = "module-level", "program-level"
MAIN = "main.py"

# Exit codes, ours and the reference's (implementation-plan.md 2.1).
OK, PROHIBITED, NOT_YET, ILL_FORMED, ILL_FORMED_PROGRAM, STUCK = 0, 1, 2, 3, 4, 5

# The two module-level tests that Python rejects dynamically but PurePy leaves
# undefined rather than aborting: `assert 0` (the condition is not a bool) and
# an attribute reference on a number. They exit 5, not 1.
STUCK_PYTHON_ERRORS = {
    "module-level/python-error/dynamic/assert_falsy.py",
    "module-level/python-error/dynamic/attr_non_object.py",
}


# --------------------------------------------------------------------------
# Running things


@dataclass
class Result:
    code: int
    out: str
    err: str

    @property
    def output(self) -> str:
        return self.out + self.err


def run(cmd: list[str], cwd: pathlib.Path | None = None, stdin: str = "") -> Result:
    p = subprocess.run(
        cmd, cwd=cwd, input=stdin, capture_output=True, text=True, check=False
    )
    return Result(p.returncode, p.stdout, p.stderr)


def strip_prefix(line: str, name: str) -> str:
    """The reference prints `<name>: ok` and `<name>:L:C: msg`. The golden
    records only what follows the name, so it does not depend on how the file
    was addressed."""
    line = line.rstrip("\n")
    return line[len(name):] if line.startswith(name) else line


# --------------------------------------------------------------------------
# The suite


def module_files() -> list[str]:
    """Every module-level source, helpers included, suite-relative."""
    return sorted(
        str(p.relative_to(SUITE))
        for p in (SUITE / MODULE_LEVEL).rglob("*.py")
        if "__pycache__" not in p.parts
    )


def program_files() -> list[str]:
    return sorted(
        str(p.relative_to(SUITE))
        for p in (SUITE / PROGRAM_LEVEL).rglob("*.py")
        if "__pycache__" not in p.parts
    )


def all_files() -> list[str]:
    return module_files() + program_files()


def program_dirs() -> list[str]:
    return sorted(
        str(p.parent.relative_to(SUITE))
        for p in (SUITE / PROGRAM_LEVEL).rglob(MAIN)
    )


def module_tests() -> list[str]:
    """The module-level files the reference's runner asserts on: everything
    but the `helpers/` fixtures."""
    return [f for f in module_files() if "helpers" not in pathlib.Path(f).parts]


def verdict_parts(rel: str) -> tuple[str, ...]:
    """The directories between `module-level/` and the file: the test's
    specification, exactly as run-all.py reads it."""
    return pathlib.PurePosixPath(rel).parent.parts[1:]


# --------------------------------------------------------------------------
# Commands, for either implementation


class Impl:
    """Our CLI, or the reference's scripts under the same four names."""

    def __init__(self, path: pathlib.Path | None, reference: bool) -> None:
        self.reference = reference
        self.path = path
        if reference:
            for script in ("syntax.py", "check_module.py", "check_program.py"):
                if not (REFERENCE / "src" / script).exists():
                    sys.exit(
                        f"reference/src/{script} is missing; run tools/fetch-reference.sh"
                    )
        elif path is None or not path.exists():
            sys.exit(f"{path}: not built; run `moon build --target native`")

    def parse(self, rel: str) -> Result:
        if self.reference:
            return run(["python3", str(REFERENCE / "src" / "syntax.py"), rel], cwd=SUITE)
        return run([str(self.path), "parse", rel], cwd=SUITE)

    def check(self, rel: str) -> Result:
        if self.reference:
            return run(
                ["python3", str(REFERENCE / "src" / "check_module.py"), rel], cwd=SUITE
            )
        return run([str(self.path), "check", rel], cwd=SUITE)

    def check_program(self, d: str) -> Result:
        cwd = SUITE / d
        if self.reference:
            return run(
                ["python3", str(REFERENCE / "src" / "check_program.py"), MAIN], cwd=cwd
            )
        return run([str(self.path), "check-program", MAIN], cwd=cwd)

    def run_module(self, rel: str) -> Result:
        return run([str(self.path), "run", pathlib.PurePosixPath(rel).name],
                   cwd=SUITE / pathlib.PurePosixPath(rel).parent)

    def run_program(self, d: str) -> Result:
        return run([str(self.path), "run", MAIN], cwd=SUITE / d)


# --------------------------------------------------------------------------
# Goldens


def read_golden(name: str) -> dict[str, tuple[int, str]]:
    path = GOLDEN / f"{name}.txt"
    if not path.exists():
        sys.exit(f"{path}: missing; run tools/conform.py --reference --regen")
    out: dict[str, tuple[int, str]] = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        key, code, tail = line.split("\t", 2)
        out[key] = (int(code), tail)
    return out


def write_golden(name: str, rows: list[tuple[str, int, str]], header: str) -> None:
    GOLDEN.mkdir(parents=True, exist_ok=True)
    body = "".join(f"{k}\t{c}\t{t}\n" for k, c, t in rows)
    (GOLDEN / f"{name}.txt").write_text(f"# {header}\n{body}")


def one_line(text: str) -> str:
    """The reference's scripts answer in one line. Anything more is a Python
    traceback, which is not an answer and must not become a golden."""
    lines = [l for l in text.strip().splitlines() if l.strip()]
    if len(lines) > 1:
        raise RuntimeError("multi-line output:\n" + text.strip()[:400])
    return lines[0] if lines else ""


def golden_rows(impl: Impl, name: str) -> list[tuple[str, int, str]]:
    """The reference's answer for every file, as `pure-py` is specified to
    report it.

    One adjustment, in `check`: `check_module.py` does not run the sieve, so on
    a file with a prohibited construct it walks a node it has no case for and
    raises. `pure-py check` runs the sieve first and reports its verdict (§2.1),
    so the golden for such a file is the SIEVE's answer -- which is what the
    reference's own runner asserts, since it never calls `check` on a file
    `parse` rejected."""
    rows = []
    if name == "parse":
        for rel in all_files():
            r = impl.parse(rel)
            rows.append((rel, r.code, strip_prefix(one_line(r.output), rel)))
    elif name == "check":
        for rel in all_files():
            r = impl.parse(rel)
            if r.code == OK:
                r = impl.check(rel)
            rows.append((rel, r.code, strip_prefix(one_line(r.output), rel)))
    elif name == "program":
        for d in program_dirs():
            r = impl.check_program(d)
            rows.append((d, r.code, one_line(r.output)))
    return rows


# --------------------------------------------------------------------------
# The oracles


@dataclass
class Report:
    name: str
    passed: int = 0
    total: int = 0
    failures: list[str] = field(default_factory=list)

    def add(self, label: str, why: str | None) -> None:
        self.total += 1
        if why is None:
            self.passed += 1
        else:
            # One failure is one line: a report of two hundred is unreadable
            # otherwise, and the detail is a `--filter` away.
            flat = " ".join(why.split())
            if len(flat) > 150:
                flat = flat[:147] + "..."
            self.failures.append(f"{label}: {flat}")


def golden_oracle(impl: Impl, name: str, keys: list[str], call, key_of) -> Report:
    golden = read_golden(name)
    rep = Report(name)
    for key in keys:
        want = golden.get(key)
        if want is None:
            rep.add(key, "no golden entry")
            continue
        r = call(key)
        got_tail = key_of(r, key)
        if r.code != want[0]:
            rep.add(key, f"exit {r.code}, want {want[0]} ({got_tail.strip() or '-'})")
        elif got_tail != want[1]:
            rep.add(key, f"message {got_tail!r}, want {want[1]!r}")
        else:
            rep.add(key, None)
    return rep


def oracle_parse(impl: Impl) -> Report:
    return golden_oracle(
        impl, "parse", all_files(), impl.parse,
        lambda r, k: strip_prefix(r.output.strip(), k),
    )


def oracle_check(impl: Impl) -> Report:
    return golden_oracle(
        impl, "check", all_files(), impl.check,
        lambda r, k: strip_prefix(r.output.strip(), k),
    )


def oracle_program(impl: Impl) -> Report:
    return golden_oracle(
        impl, "program", program_dirs(), impl.check_program,
        lambda r, k: r.output.strip(),
    )


def sibling(rel: str, suffix: str) -> pathlib.Path:
    p = SUITE / rel
    return p.with_suffix(suffix)


def expect_run_output(r: Result, expected: pathlib.Path) -> str | None:
    if r.code != 0:
        return f"exit {r.code}: {r.err.strip()[:120]}"
    want = expected.read_text()
    if r.out != want:
        return f"output {r.out!r}, want {want!r}"
    return None


def expect_abort(r: Result, rel: str, exception: pathlib.Path) -> str | None:
    want = exception.read_text().strip()
    if r.code != 1:
        return f"exit {r.code}, want 1 ({want})"
    if want not in r.err:
        return f"stderr {r.err.strip()!r}, want to contain {want!r}"
    out_expected = sibling(rel, ".output.expected")
    if out_expected.exists() and r.out != out_expected.read_text():
        return f"output before {want}: {r.out!r}"
    return None


def expect_stuck(r: Result) -> str | None:
    if r.code != STUCK:
        return f"exit {r.code}, want 5 (stuck): {r.output.strip()[:120]}"
    if "stuck" not in r.err:
        return f"stderr {r.err.strip()!r}, want to name the undefined operation"
    return None


def oracle_run(impl: Impl) -> Report:
    """The verdict-driven oracle: what a test's path says must happen when the
    program is actually evaluated."""
    rep = Report("run")
    for rel in module_tests():
        parts = verdict_parts(rel)
        verdict = parts[0]
        stage = parts[1] if len(parts) > 1 else None
        pending = parts[-1] == "pending"
        expected = sibling(rel, ".expected")
        exception = sibling(rel, ".exception.expected")

        if verdict == "semantically-valid":
            if pending:
                continue  # the sieve rejects it; nothing to run
            rep.add(rel, expect_run_output(impl.run_module(rel), expected))
        elif verdict == "excluded":
            if stage == "syntactic":
                continue  # rejected before evaluation
            if stage == "static" and not pending:
                continue  # rejected by the checker
            # static/pending, dynamic and dynamic-semantic: accepted, then
            # the semantics has no rule for what happens next.
            rep.add(rel, expect_stuck(impl.run_module(rel)))
        elif verdict == "python-error":
            if stage == "dynamic":
                r = impl.run_module(rel)
                if rel in STUCK_PYTHON_ERRORS:
                    rep.add(rel, expect_stuck(r))
                else:
                    rep.add(rel, expect_abort(r, rel, exception))
            # static, static/pending and syntactic-only: Python's business.

    for d in program_dirs():
        expected_exit = int((SUITE / d / "expected_exit").read_text().strip())
        if expected_exit != 0:
            continue  # rejected by check-program; the `program` oracle has it
        r = impl.run_program(d)
        if d.startswith(f"{PROGRAM_LEVEL}/python-error"):
            # A program the checker accepts but Python aborts: the kind it
            # aborts with is in `main.exception.expected`, as at module level.
            rep.add(d, expect_abort(r, f"{d}/{MAIN}", SUITE / d / "main.exception.expected"))
        else:
            rep.add(d, expect_run_output(r, SUITE / d / "expected"))
    return rep


ORACLES = {
    "parse": oracle_parse,
    "check": oracle_check,
    "program": oracle_program,
    "run": oracle_run,
}


# --------------------------------------------------------------------------
# The ratchet


def load_policy() -> dict:
    if POLICY.exists():
        return json.loads(POLICY.read_text())
    return {"floors": {}}


def save_policy(policy: dict) -> None:
    POLICY.write_text(json.dumps(policy, indent=2, sort_keys=True) + "\n")


# --------------------------------------------------------------------------


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("phase", nargs="?", default="all",
                    choices=[*ORACLES, "all"], help="which oracle to run")
    ap.add_argument("--impl", type=pathlib.Path, default=DEFAULT_IMPL,
                    help="the pure-py binary under test")
    ap.add_argument("--reference", action="store_true",
                    help="drive the reference's Python scripts instead")
    ap.add_argument("--regen", action="store_true",
                    help="write test/golden/*.txt from the implementation being driven")
    ap.add_argument("--regen-policy", action="store_true",
                    help="move the ratchet's floors to this run's results")
    ap.add_argument("--filter", default=None, help="only tests whose name contains this")
    ap.add_argument("--show", type=int, default=5, help="how many failures to print")
    ap.add_argument("--no-ratchet", action="store_true", help="report, do not gate")
    args = ap.parse_args()

    impl = Impl(args.impl, args.reference)

    if args.regen:
        if not args.reference:
            print(f"{YELLOW}note{RESET}: regenerating goldens from {args.impl}, "
                  f"not from the reference")
        for name in ("parse", "check", "program"):
            rows = golden_rows(impl, name)
            source = "reference" if args.reference else str(args.impl.name)
            write_golden(name, rows,
                         f"{name}: exit code and message from the {source}, "
                         f"one line per test; regenerate with tools/conform.py "
                         f"--reference --regen")
            print(f"wrote test/golden/{name}.txt ({len(rows)} rows)")
        return

    if args.reference and args.phase == "run":
        sys.exit("the reference has no interpreter; `run` needs --impl")

    names = list(ORACLES) if args.phase == "all" else [args.phase]
    policy = load_policy()
    floors = policy.setdefault("floors", {})
    failed_gate = False
    reports = []

    for name in names:
        if args.reference and name == "run":
            continue
        rep = ORACLES[name](impl)
        if args.filter:
            rep.failures = [f for f in rep.failures if args.filter in f]
        reports.append(rep)
        floor = floors.get(name, 0)
        mark = GREEN + "✓" + RESET if rep.passed == rep.total else RED + "✗" + RESET
        print(f"{mark} {name:8} {rep.passed}/{rep.total}"
              f"{'' if rep.passed == rep.total else f'  ({len(rep.failures)} failing)'}")
        for f in rep.failures[: args.show]:
            print(f"    {DIM}{f}{RESET}")
        if len(rep.failures) > args.show:
            print(f"    {DIM}... and {len(rep.failures) - args.show} more{RESET}")
        if args.regen_policy:
            floors[name] = rep.passed
        elif not args.no_ratchet:
            if rep.passed < floor:
                print(f"  {RED}regression{RESET}: {rep.passed} < floor {floor}")
                failed_gate = True
            elif rep.passed > floor:
                print(f"  {YELLOW}unrecorded improvement{RESET}: {rep.passed} > floor "
                      f"{floor}; rerun with --regen-policy and commit the change")
                failed_gate = True

    total = sum(r.total for r in reports)
    passed = sum(r.passed for r in reports)
    print(f"\n{passed}/{total} across {len(reports)} oracle(s)")

    if args.regen_policy:
        # Merge, not replace: the token and tree oracles live in their own
        # scripts and record their totals in the same file.
        policy.setdefault("totals", {}).update({r.name: r.total for r in reports})
        save_policy(policy)
        print(f"wrote {POLICY.relative_to(ROOT)}")
        return
    sys.exit(1 if failed_gate else 0)


if __name__ == "__main__":
    main()
