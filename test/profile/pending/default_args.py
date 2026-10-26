from typing import Callable

def greet(name: str, greeting: str = "hello", excited: bool = False, pad: str | None = None) -> list[str | bool | None]:
    return [greeting, name, excited, pad]

print(greet("a"))
print(greet("a", "hi"))
print(greet("a", "hi", True))
print(greet("a", "hi", True, "x"))

def area(w: float, h: float = 2.5) -> float:
    return w * h

print([area(4), area(4, 3.0)])

f: Callable[[int], int] = lambda x, y=10: x + y
print(f(1))

def only_defaults(a: int = 1, b: str = "two") -> list[int | str]:
    return [a, b]

print([only_defaults(), only_defaults(9), only_defaults(9, "!")])

def mutual_even(n: int, step: int = 1) -> bool:
    if n == 0:
        return True
    return mutual_odd(n - step)

def mutual_odd(n: int, step: int = 1) -> bool:
    if n == 0:
        return False
    return mutual_even(n - step)

print([mutual_even(4), mutual_odd(4)])
