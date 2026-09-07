# Every simple statement, and the assignment forms.
import sys
import os.path
import sys as system
from math import pi
from math import pi as PI, e
from math import (sqrt, floor)
from . import sibling
from .. import parent
from .relative import thing
from typing import *

x = 1
x = y = z = 2
x, y = 1, 2
(x, y) = 1, 2
[x, y] = 1, 2
x, *y = 1, 2, 3
x += 1
x -= 1
x *= 2
x /= 2
x //= 2
x %= 2
x **= 2
x &= 1
x |= 1
x ^= 1
x >>= 1
x <<= 1
x: int = 1
y: int
obj = sys
obj.path = 1
[1, 2][0]
del x
del x, y
assert True
assert True, "message"
pass
raise
raise ValueError
raise ValueError("x") from None
print(1); print(2)


def g():
    global obj
    return


def h():
    y = 1

    def inner():
        nonlocal y
        y = 2

    inner()
    return y
