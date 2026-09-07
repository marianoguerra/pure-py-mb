# Every operator and delimiter Python 3.12 spells, and the ones whose longest
# match is what decides the split: `**=` before `**` before `*`.
a = 1 + 2 - 3 * 4 / 5 // 6 % 7 ** 8
b = a @ a
c = ~a & a | a ^ a << a >> a
d = a < a <= a > a >= a == a != a
e = (a, [a], {a: a}, {a})
a += 1
a -= 1
a *= 1
a /= 1
a //= 1
a %= 1
a **= 1
a &= 1
a |= 1
a ^= 1
a >>= 1
a <<= 1
a @= a


def f(x: int, *args, y=1, **kwargs) -> int:
    return x


g = lambda x: x
h = ...
i = a if a else a
j = [x for x in (1, 2) if x]
k = {"a": 1}["a"]
m = a.real
n = [1, 2, 3][0:2:1]
if (o := 3) > 2:
    pass
