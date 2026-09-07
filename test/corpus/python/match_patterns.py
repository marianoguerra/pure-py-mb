# The whole pattern grammar of PEP 634, including the one thing CPython's tree
# forgets: whether a sequence pattern was written with brackets or with
# parentheses.
class Point:
    x: int
    y: int


def f(v):
    match v:
        case 0:
            return "zero"
        case -1:
            return "minus one"
        case 1.5:
            return "float"
        case 1 + 2j:
            return "complex"
        case "s":
            return "string"
        case b"b":
            return "bytes"
        case None:
            return "none"
        case True:
            return "true"
        case False:
            return "false"
        case []:
            return "empty list"
        case [a]:
            return a
        case [a, b]:
            return a
        case [a, *rest]:
            return rest
        case [_, *_]:
            return "any two"
        case ():
            return "empty tuple"
        case (a,):
            return a
        case (a, b):
            return a
        case (a):
            return a
        case {}:
            return "empty dict"
        case {"k": a}:
            return a
        case {"k": a, **rest}:
            return rest
        case Point():
            return "origin"
        case Point(a, b):
            return a
        case Point(x=a):
            return a
        case Point(a, y=b):
            return b
        case Point() | None:
            return "either"
        case [1] | [2]:
            return "one or two"
        case Point() as p:
            return p
        case [a, b] as pair:
            return pair
        case a if a > 0:
            return a
        case _:
            return "other"


def g(v, w):
    match v, w:
        case 1, 2:
            return "pair"
        case _:
            return "no"


def h(v):
    match v:
        case Point(x=0, y=0):
            return "origin"
        case _:
            return None
