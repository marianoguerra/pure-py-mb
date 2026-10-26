// The gallery. Each example is one thing the library does, and together they
// are meant to be the whole of it: what PurePy accepts, what it refuses and
// when, what a run prints, and what a host can hand a guest.
//
// A source may hold several modules, separated by a line beginning
// `# module: NAME`. The first chunk is `__main__` unless it says otherwise.
//
// `expect` is what the example DOES -- one of `finished`, `exited`,
// `terminated`, `undefined` or `refused`. `tools/check_examples.mjs
// --expect` runs every example through the playground's own wasm module and
// fails if one has drifted from what its note claims, which is the only thing
// that keeps a page full of prose honest.
export const GROUPS = [
  {
    label: 'Running',
    items: [
      {
        name: 'Hello, world',
        note: 'The smallest program there is.',
        expect: 'finished',
        src: `print("Hello, world!")\n`,
      },
      {
        name: 'Numbers',
        note:
          "Integers are unbounded and `//` and `%` floor, so they take the " +
          "sign of the divisor. `/` always gives a float, and a float prints " +
          "the way Python prints it.",
        expect: 'finished',
        src: `print(2 ** 100)
print([-7 // 2, -7 % 2, 7 % -2])
print([7 / 2, 4 / 2])
print(0.1 + 0.2)
print([1e16, 1e15, 1e-5])
`,
      },
      {
        name: 'Strings and containers',
        note:
          "A string is a sequence of code points, so `len` and indexing " +
          "count characters and not bytes. A container prints its elements " +
          "with `repr`. `print` takes one argument, so several things are " +
          "printed as a list of them.",
        expect: 'finished',
        src: `s: str = "héllo"
print([len(s), s[0], s[-1]])
print("bc" in "abcd")
xs: list[int | str | tuple[int, int] | dict[str, float] | None | bool] = [1, "a", (2, 3), {"k": 1.5}, None, True]
print(xs)
print(len(xs))
d: dict[str, int] = {"one": 1, "two": 2}
print([d["one"], len(d)])
print("two" in d)
`,
      },
      {
        name: 'Functions and recursion',
        note:
          'Recursion is how a PurePy program loops, and a list is taken ' +
          'apart by index rather than by slicing, which is one of the ' +
          'things the language has not defined yet. Every parameter and ' +
          'every result has a type.',
        expect: 'finished',
        src: `def factorial(n: int) -> int:
    if n <= 1:
        return 1
    return n * factorial(n - 1)

def total(xs: list[int], i: int) -> int:
    if i == len(xs):
        return 0
    return xs[i] + total(xs, i + 1)

print(factorial(20))
print(total([3, 1, 4, 1, 5], 0))
`,
      },
      {
        name: 'Mutual recursion',
        note:
          "A run of consecutive `def`s is one mutual region: each may name " +
          "the others, and calling one rebinds the whole region.",
        expect: 'finished',
        src: `def even(n: int) -> bool:
    if n == 0:
        return True
    return odd(n - 1)

def odd(n: int) -> bool:
    if n == 0:
        return False
    return even(n - 1)

print([even(10), odd(10)])
`,
      },
      {
        name: 'Closures',
        note:
          "A lambda captures the environment it was made in. Because nothing " +
          "is ever reassigned after being captured, what it sees cannot change. " +
          "A lambda has no type of its own, so it takes the one it is " +
          "checked against.",
        expect: 'finished',
        src: `from typing import Callable

factor: int = 3
triple: Callable[[int], int] = lambda n: n * factor
print(triple(7))

def adder(k: int) -> Callable[[int], int]:
    return lambda n: n + k

print(adder(10)(5))
`,
      },
      {
        name: 'Comprehensions',
        note:
          "Over a list, a string or a dictionary's keys, with as many " +
          "clauses and conditions as you like.",
        expect: 'finished',
        src: `xs: list[int] = [1, 2, 3, 4, 5]
print([n * n for n in xs])
print([n for n in xs if n % 2 == 0])
print([a * b for a in [1, 2] for b in [10, 20]])
print({k: len(k) for k in ["a", "bb", "ccc"]})
s: str = "abc"
print([c for c in s])
`,
      },
      {
        name: 'Dataclasses and matching',
        note:
          "The one class form PurePy has, and the pattern language that goes " +
          "with it. A constructor pattern matches a subclass and binds the " +
          "pattern class's fields, so the Point3 case has to come first. The " +
          "checker knows which cases a value can reach, from its type.",
        expect: 'finished',
        src: `from dataclasses import dataclass

@dataclass
class Point:
    x: int
    y: int

@dataclass
class Point3(Point):
    z: int

def describe(v: Point | dict[str, str] | list[int] | None) -> str:
    match v:
        case Point3(a, b, c):
            return "a point in space"
        case Point(0, 0):
            return "the origin"
        case Point(a, b):
            return "a point in the plane"
        case {"kind": k}:
            return k
        case [a, b]:
            return "a list of two"
        case _:
            return "something else"

print(Point(1, 2))
print(Point3(1, 2, 3))
print(describe(Point(0, 0)))
print(describe(Point(1, 2)))
print(describe(Point3(1, 2, 3)))
print(describe({"kind": "a dictionary"}))
print([describe([1, 2]), describe(None)])
`,
      },
      {
        name: 'Modules',
        note:
          "Several modules in one box, separated by `# module:` lines. " +
          "Imports come first in a module, and every module a statement can " +
          "name is loaded before that statement runs.",
        expect: 'finished',
        src: `# module: geometry
from dataclasses import dataclass

@dataclass
class Point:
    x: int
    y: int

def flip(p: Point) -> Point:
    return Point(p.y, p.x)

# module: __main__
import geometry
from geometry import Point, flip

p: Point = Point(3, 4)
print([p, flip(p)])
print(round(geometry.Point(1, 2).x / 2))
`,
      },
    ],
  },
  {
    label: 'Embedding',
    items: [
      {
        name: 'Calling the host',
        note:
          "The `host` module does not exist in PurePy: this page supplies " +
          "it. `log` reaches the host's own pane, `now` is a fixed instant, " +
          "and `count` keeps state on the host's side that the guest can " +
          "only reach through the call. The host declares each function's " +
          "type, so the guest's calls are checked like any others.",
        expect: 'finished',
        src: `from host import VERSION, log, now, count

print(VERSION)
log("the guest is running")
print(["the host says the time is", now()])
print([count("clicks"), count("clicks"), count("other")])
log("and it is done")
`,
      },
      {
        name: 'The host refusing',
        note:
          "A host answers with a value, with one of the semantics' own " +
          "terminations, or with nothing it can do. `fail` chooses " +
          "`KeyError`, and the run ends there.",
        expect: 'terminated',
        src: `from host import log, fail

log("before")
print(fail())
print("never reached")
`,
      },
      {
        name: 'Arguments',
        note:
          "`sys.argv` is whatever the host says it is; this page says " +
          "`playground.py --demo`.",
        expect: 'finished',
        src: `import sys

print(len(sys.argv))
print([sys.argv[0], sys.argv[1]])
`,
      },
    ],
  },
  {
    label: 'Refused before it runs',
    items: [
      {
        name: 'Not PurePy: a loop',
        note:
          "The sieve refuses what the language excludes on sight, and says " +
          "which construct and where. Loops are out because recursion is in.",
        expect: 'refused',
        src: `xs: list[int] = [1, 2, 3]
for x in xs:
    print(x)
`,
      },
      {
        name: 'Not PurePy: mutation',
        note:
          "Item assignment, attribute assignment, augmented assignment and " +
          "`del` are all excluded, and each has its own message. Try " +
          "deleting the first line to see the next one.",
        expect: 'refused',
        src: `xs: list[int] = [1, 2, 3]
xs[0] = 9
`,
      },
      {
        name: 'Not definitely assigned',
        note:
          "A variable is declared with its type, and has to be assigned on " +
          "every path that reaches a use. Assigning in one branch only is " +
          "not enough -- add an `else` and it is accepted.",
        expect: 'refused',
        src: `c: bool = True
x: int
if c:
    x = 1
print(x)
`,
      },
      {
        name: 'Assigning twice',
        note:
          "A PurePy variable is declared once and assigned once. That is " +
          "what makes closures behave without mutable cells: there is no " +
          "later value for a function that read the name to miss.",
        expect: 'refused',
        src: `x: int = 5

def show() -> int:
    return x

x = 6
print(show())
`,
      },
      {
        name: 'A case that can never run',
        note:
          "A pattern an earlier case already covers is refused, and the " +
          "report points at both.",
        expect: 'refused',
        src: `v: int = 1
match v:
    case a:
        print("anything")
    case 1:
        print("one")
`,
      },
      {
        name: 'A constructor of the wrong shape',
        note:
          "Arity and keywords are checked against the class's fields, " +
          "inherited first.",
        expect: 'refused',
        src: `from dataclasses import dataclass

@dataclass
class Point:
    x: int
    y: int

p: Point = Point(1, 2, 3)
`,
      },
      {
        name: 'A type error',
        note:
          "PurePy is typed: every function says what it takes and what it " +
          "gives, and a call is checked against that before anything runs.",
        expect: 'refused',
        src: `def double(n: int) -> int:
    return n * 2

print(double("two"))
`,
      },
      {
        name: 'No truthiness',
        note:
          "Python decides `if 5:` by truthiness. PurePy has no truthiness: a " +
          "condition is a bool, and the checker says so before the run.",
        expect: 'refused',
        src: `if 5:
    print("Python would print this")
`,
      },
      {
        name: 'No methods',
        note:
          "The attributes of a built-in value are not PurePy's, which is what " +
          "makes list mutation unreachable rather than merely discouraged.",
        expect: 'refused',
        src: `xs: list[int] = [1, 2]
xs.append(3)
`,
      },
    ],
  },
  {
    label: 'Ends without an answer',
    items: [
      {
        name: 'Aborting',
        note:
          "The terminations are the ones Python raises in the same place: " +
          "division by zero, an index out of range, a missing key, a failed " +
          "assertion.",
        expect: 'terminated',
        src: `print("before")
print(1 // 0)
`,
      },
      {
        name: 'Assertions',
        note: 'An assertion message is evaluated only when the check fails.',
        expect: 'terminated',
        src: `n: int = 3
assert n > 0, "n must be positive"
print("checked")
assert n > 10, "n is too small"
`,
      },
      {
        name: 'Exiting',
        note: '`sys.exit` ends the run with a status and prints nothing more.',
        expect: 'exited',
        src: `import sys

print("working")
sys.exit(2)
print("never reached")
`,
      },
      {
        name: 'Undefined: nan inside a container',
        note:
          "A well-typed program can still reach an operation with no rule. " +
          "`nan == nan` is False, but whether a list holding nan equals " +
          "itself is a question Python answers by identity, and PurePy " +
          "values have none -- so the run has no answer, and this " +
          "implementation says so rather than guessing Python's.",
        expect: 'undefined',
        src: `inf: float = 1e309
nan: float = inf - inf
print(nan == nan)
print([nan] == [nan])
`,
      },
      {
        name: 'Undefined: a bool against a number',
        note:
          "A literal pattern compares with `==`, and Python's `True == 1` is " +
          "a coercion PurePy does not make. The first call has an answer; the " +
          "second does not.",
        expect: 'undefined',
        src: `def kind(v: bool | int) -> str:
    match v:
        case 1:
            return "one"
        case _:
            return "something else"

print(kind(1))
print(kind(True))
`,
      },
      {
        name: 'Not stopping',
        note:
          "No check can rule out a program that runs forever. Recursion is " +
          "bounded instead, by a limit the embedder chooses -- this page " +
          "picks 250 so the answer arrives while you are looking at it. The " +
          "bound used to belong to the host, because the evaluator recursed " +
          "and a browser tab holds far fewer frames than a native thread. It " +
          "keeps its continuation on the heap now, so a runaway costs an " +
          "array of frames and not the tab.",
        expect: 'undefined',
        src: `def forever(n: int) -> int:
    return forever(n + 1)

print(forever(0))
`,
      },
    ],
  },
];
