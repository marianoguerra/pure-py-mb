# The two forms that only appear in certain positions.
xs = [1, 2, 3]
if (n := len(xs)) > 2:
    print(n)

while (m := len(xs)) > 0:
    break

ys = [y := 5]
print(y)
zs = [*xs, *ys]
ws = (*xs,)
d = {**{}, "a": 1}


def f(*args, **kwargs):
    return args


f(*xs, **d)
a, *b = xs
*a, b = xs
[a, *b] = xs
