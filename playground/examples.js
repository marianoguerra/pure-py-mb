// The gallery. Each example is one thing the library does, and together they
// are meant to be the whole of it: what PurePy accepts, what it refuses and
// when, what a run prints, and what a host can hand a guest.
//
// A source may hold several modules, separated by a line beginning
// `# module: NAME`. The first chunk is `__main__` unless it says otherwise.
//
// `expect` is what the example DOES -- one of `finished`, `exited`,
// `terminated`, `undefined`, `refused` or `not-yet`. `tools/check_examples.mjs
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
print(-7 // 2, -7 % 2, 7 % -2)
print(7 / 2, 4 / 2)
print(0.1 + 0.2)
print(1e16, 1e15, 1e-5)
`,
      },
      {
        name: 'Strings and containers',
        note:
          "A string is a sequence of code points, so `len` and indexing " +
          "count characters and not bytes. A container prints its elements " +
          "with `repr`.",
        expect: 'finished',
        src: `s = "héllo"
print(len(s), s[0], s[-1])
print("bc" in "abcd")
xs = [1, "a", (2, 3), {"k": 1.5}, None, True]
print(xs)
print(xs[2], len(xs))
d = {"one": 1, "two": 2}
print(d["one"], "two" in d, len(d))
`,
      },
      {
        name: 'Functions and recursion',
        note:
          'Recursion is how a PurePy program loops, and a list is taken ' +
          'apart by index rather than by slicing, which is one of the ' +
          'things the language has not defined yet.',
        expect: 'finished',
        src: `def factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

def total(xs, i):
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
        src: `def even(n):
    if n == 0:
        return True
    return odd(n - 1)

def odd(n):
    if n == 0:
        return False
    return even(n - 1)

print(even(10), odd(10))
`,
      },
      {
        name: 'Closures',
        note:
          "A lambda captures the environment it was made in. Because nothing " +
          "is ever reassigned after being captured, what it sees cannot change.",
        expect: 'finished',
        src: `factor = 3
triple = lambda n: n * factor
print(triple(7))

def adder(k):
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
        src: `xs = [1, 2, 3, 4, 5]
print([n * n for n in xs])
print([n for n in xs if n % 2 == 0])
print([a * b for a in [1, 2] for b in [10, 20]])
print({k: len(k) for k in ["a", "bb", "ccc"]})
print([c for c in "abc"])
`,
      },
      {
        name: 'Dataclasses and matching',
        note:
          "The one class form PurePy has, and the pattern language that goes " +
          "with it. A constructor pattern matches a subclass and binds the " +
          "pattern class's fields, so the Point3 case has to come first.",
        expect: 'finished',
        src: `from dataclasses import dataclass
from typing import Any

@dataclass
class Point:
    x: Any
    y: Any

@dataclass
class Point3(Point):
    z: Any

def describe(v):
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
print(describe([1, 2]), describe(None))
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
from typing import Any
from dataclasses import dataclass

@dataclass
class Point:
    x: Any
    y: Any

def flip(p):
    return Point(p.y, p.x)

# module: __main__
import math
from geometry import Point, flip

p = Point(3, 4)
print(p, flip(p))
print(math.sqrt(p.x * p.x + p.y * p.y))
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
          "only reach through the call.",
        expect: 'finished',
        src: `from host import VERSION, log, now, count

print(VERSION)
log("the guest is running")
print("the host says the time is", now())
print(count("clicks"), count("clicks"), count("other"))
log("and it is done")
`,
      },
      {
        name: 'The host refusing',
        note:
          "A host answers with a value, with one of the semantics' own " +
          "terminations, or with nothing it can do. `fail` chooses " +
          "`KeyError`; calling `log` with two arguments is a shape the host " +
          "does not recognise, and that is undefined rather than an error " +
          "the host invented.",
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
print(sys.argv[0], sys.argv[1])
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
        src: `xs = [1, 2, 3]
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
        src: `xs = [1, 2, 3]
xs[0] = 9
`,
      },
      {
        name: 'Not definitely assigned',
        note:
          "A name has to be bound on every path that reaches it. Assigning " +
          "in one branch only is not enough -- add an `else` and it is " +
          "accepted.",
        expect: 'refused',
        src: `c = True
if c:
    x = 1
print(x)
`,
      },
      {
        name: 'Reassigning a captured name',
        note:
          "This is the rule that makes closures behave without mutable " +
          "cells: once a statement has captured a name, nothing after it may " +
          "rebind that name. The report shows both places.",
        expect: 'refused',
        src: `x = 5

def show():
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
        src: `v = 1
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
from typing import Any

@dataclass
class Point:
    x: Any
    y: Any

p = Point(1, 2, 3)
`,
      },
      {
        name: 'Planned, not yet here',
        note:
          "Some Python the specification means to allow and has not defined " +
          "yet. These are refused with the issue that tracks them, which is " +
          "a different answer from “never”.",
        expect: 'not-yet',
        src: `a = 1
b = 2
c = 3
print(a < b < c)
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
        src: `n = 3
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
        name: 'Undefined: truthiness',
        note:
          "Python decides `if 5:` by truthiness. PurePy has no rule for a " +
          "condition that is not a bool, so the run has no answer -- and " +
          "this implementation says so rather than guessing Python's.",
        expect: 'undefined',
        src: `if 5:
    print("Python would print this")
`,
      },
      {
        name: 'Undefined: comparing unlike things',
        note:
          "Equality is partial and short-circuits, so which pair it reaches " +
          "first decides whether there is an answer. The second line has one; " +
          "the third does not.",
        expect: 'undefined',
        src: `print([1, "a"] == [2, 3])
print(1 == "a")
`,
      },
      {
        name: 'Undefined: no such attribute',
        note:
          "The attributes of a built-in value are undefined, which is what " +
          "makes list mutation unreachable rather than merely discouraged.",
        expect: 'undefined',
        src: `xs = [1, 2]
xs.append(3)
`,
      },
      {
        name: 'Undefined: a pattern that does not apply',
        note:
          "The pattern rules are narrower than “anything else fails”. A tuple " +
          "pattern against a number is an honest no-match; a LIST pattern " +
          "against a tuple is covered by no rule at all, and there is no " +
          "answer. Swap the two calls to see the difference.",
        expect: 'undefined',
        src: `def first(v):
    match v:
        case [a, b]:
            return a
        case _:
            return "not a list of two"

print(first(7))
print(first((1, 2)))
`,
      },
      {
        name: 'Not stopping',
        note:
          "No check can rule out a program that runs forever. Recursion is " +
          "bounded instead, and the bound belongs to the host: a browser tab " +
          "holds far fewer frames than a native thread, so this page sets it " +
          "to 250 -- measured by calling the very module this page loads " +
          "until the engine threw, which is about 780 deep.",
        expect: 'undefined',
        src: `def forever(n):
    return forever(n + 1)

print(forever(0))
`,
      },
    ],
  },
];
