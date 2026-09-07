# `and` binds tighter than `or`; runs of the same operator flatten into one
# node with several values; `not` sits between them.
a, b, c, d = 1, 2, 3, 4
p = a or b or c
q = a and b and c
r = a or b and c
s = (a or b) and c
t = not a or b
u = not (a or b)
v = a if b else c
w = a if b else c if d else a
x = (a if b else c) if d else a
y = lambda: 1
z = lambda p, q: p + q
aa = lambda p, q=1: p + q
bb = lambda *args, **kw: args
cc = lambda p: lambda q: p + q
dd = a or (lambda: b)()
