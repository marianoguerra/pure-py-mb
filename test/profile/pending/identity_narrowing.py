from dataclasses import dataclass

@dataclass
class P:
    x: int

def f(x: int | None) -> int:
    if x is None:
        return 0
    return x + 1

def g(x: int | None) -> int:
    if x is not None:
        return x
    return 0

def h(x: int | None) -> bool:
    return x is not None and x > 1

def k(x: int | None) -> bool:
    return x is None or x > 1

def m(x: int | None) -> int:
    return 0 if x is None else x

def n(x: int | None) -> int:
    assert x is not None
    return x

def o(x: int | None) -> int:
    if not (x is None):
        return x
    return 0

def p(x: int | None, y: int | None) -> int:
    if x is None or y is None:
        return 0
    return x + y

def q(x: int) -> bool:
    return x is None

def r(x: P | None) -> int:
    if None is x:
        return 0
    return x.x

def s(ys: list[int | None]) -> list[int]:
    return [y + 1 for y in ys if y is not None]

def t(x: int | None) -> int:
    if x is None:
        return 0
    elif x > 3:
        return x
    else:
        return -x

def u(c: bool, x: int | None) -> int:
    y: int
    if c:
        if x is None:
            return 0
        y = x
    else:
        y = 5
    return y + x if x is not None else y

def v(x: int | None, y: int | None) -> int:
    if x is None:
        return 0
    elif y is None:
        return 1
    return x + y

print([f(None), f(2), g(None), g(3)])
print([h(None), h(2), k(None), k(0)])
print([m(None), m(4), n(5), o(None), o(6)])
print([p(None, 1), p(1, 2), q(1), r(None), r(P(7))])
print(s([1, None, 3]))
print([t(None), t(5), t(2), u(True, 3), u(False, None), v(1, 2), v(1, None)])
