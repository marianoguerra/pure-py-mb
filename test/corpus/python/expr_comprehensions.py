# Comprehensions of all four kinds, several clauses, several conditions, and
# the nesting that decides which `for` sees which name.
xs = [1, 2, 3]
ys = [4, 5]
a = [x for x in xs]
b = [x for x in xs if x]
c = [x for x in xs if x if x > 1]
d = [x + y for x in xs for y in ys]
e = [[y for y in xs] for x in ys]
f = {x: x for x in xs}
g = {x: y for x in xs for y in ys if x != y}
h = {x for x in xs}
i = (x for x in xs)
j = [x for x in xs if (y := x) > 1]
k = [lambda: x for x in xs]
m = [x for x in [y for y in xs]]
