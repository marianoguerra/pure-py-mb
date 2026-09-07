#!/usr/bin/env python3
"""Mutate the corpus and check that nothing crashes or hangs.

The front end has to survive input nobody wrote. This takes each source in
the suite and the corpus, mutates it -- deleting, duplicating, transposing and
inserting bytes, and cutting it short -- and runs `pure-py tokens`, `dump` and
`check` over the result. Three things are asserted:

  * the process does not crash. Exit codes 0 through 5 are answers; a signal,
    or any other code, is a defect;
  * it does not hang. A mutation that takes more than a few seconds is a
    defect whatever it produces;
  * a rejection carries a position. `!error <path>:<line>:<col>: ...` is what
    the front end promises, and a bare message means something raised where
    nothing was meant to.

Opt-in and seeded: `tools/fuzz.py --count 10000 --seed 7`. A failure prints
the mutation to a file so it can be replayed.
"""

from __future__ import annotations

import argparse
import pathlib
import random
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMPL = ROOT / "_build/native/debug/build/cmd/pure-py/pure-py.exe"
GREEN, RED, RESET = "\033[32m", "\033[31m", "\033[0m"

# What the command line promises. Anything else is a defect.
ANSWERS = {0, 1, 2, 3, 4, 5}


def corpus() -> list[bytes]:
    files = [
        p for p in (ROOT / "test").rglob("*.py") if "__pycache__" not in p.parts
    ]
    return [p.read_bytes() for p in files]


def mutate(rng: random.Random, data: bytes) -> bytes:
    out = bytearray(data)
    for _ in range(rng.randint(1, 6)):
        if not out:
            break
        i = rng.randrange(len(out))
        choice = rng.randrange(6)
        if choice == 0:
            del out[i]
        elif choice == 1:
            out.insert(i, rng.randrange(256))
        elif choice == 2:
            out[i] = rng.randrange(256)
        elif choice == 3 and i + 1 < len(out):
            out[i], out[i + 1] = out[i + 1], out[i]
        elif choice == 4:
            # Duplicate a run: a good way to make deeply nested brackets.
            j = min(len(out), i + rng.randint(1, 40))
            out[i:i] = out[i:j]
        else:
            del out[i:]
    return bytes(out)


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--count", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--timeout", type=float, default=10.0)
    ap.add_argument("--keep", type=pathlib.Path, default=pathlib.Path("/tmp"))
    args = ap.parse_args()

    if not IMPL.exists():
        sys.exit(f"{IMPL}: not built; run `moon build --target native`")

    rng = random.Random(args.seed)
    sources = corpus()
    scratch = args.keep / "purepy-fuzz.py"
    failures = 0

    for n in range(args.count):
        data = mutate(rng, rng.choice(sources))
        scratch.write_bytes(data)
        for command in ("tokens", "dump", "check"):
            try:
                p = subprocess.run(
                    [str(IMPL), command, str(scratch)],
                    capture_output=True, timeout=args.timeout, check=False,
                )
            except subprocess.TimeoutExpired:
                keep = args.keep / f"purepy-fuzz-hang-{n}.py"
                keep.write_bytes(data)
                print(f"{RED}hang{RESET}: {command} on {keep}")
                failures += 1
                continue
            if p.returncode not in ANSWERS:
                keep = args.keep / f"purepy-fuzz-crash-{n}.py"
                keep.write_bytes(data)
                print(f"{RED}exit {p.returncode}{RESET}: {command} on {keep}")
                failures += 1
                continue
            text = p.stdout.decode("utf-8", "replace")
            if text.startswith("!error") and ":" not in text.split("\n")[0][7:]:
                keep = args.keep / f"purepy-fuzz-nopos-{n}.py"
                keep.write_bytes(data)
                print(f"{RED}no position{RESET}: {command} on {keep}: "
                      f"{text.splitlines()[0]}")
                failures += 1

    mark = GREEN + "✓" + RESET if not failures else RED + "✗" + RESET
    print(f"{mark} fuzz {args.count - failures}/{args.count} mutations clean "
          f"(seed {args.seed})")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
