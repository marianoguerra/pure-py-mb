t: tuple[int, str, bool] = (1, "a", True)
a: tuple[str, bool] = t[1:]
b: tuple[int, str] = t[:2]
c: tuple[bool, str, int] = t[::-1]
d: tuple[str, bool] = t[1:10]
e: tuple[str, bool] = t[-2:]
f: tuple[int, bool] = t[::2]
g: tuple[int, str] = t[-10:2]
h: tuple[bool, str] = t[2:0:-1]
i: tuple[bool, int] = t[::-2]
print([a, b, c, d, e])
print([f, g, h, i])
print(t[5:])
print(len(t[1:]))
u: tuple[int, int, int] = (1, 2, 3)
print(u[1:] + (4,))
