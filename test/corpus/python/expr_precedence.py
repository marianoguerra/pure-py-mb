# Every binary level, and the two places precedence is counter-intuitive:
# `**` binds tighter than unary minus on its left and looser on its right,
# and a chained comparison is one node with several operators.
a, b, c, d = 1, 2, 3, 4
p = a | b ^ c & d
q = a << b >> c
r = a + b * c - d / a // b % c
s = -a ** b
t = a ** -b
u = a ** b ** c
v = -a * -b
w = ~a + ~b
x = not a
y = not not a
z = a < b <= c > d >= a == b != c
aa = a in [b] not in [c]
bb = a is b is not c
cc = not a in [b]
dd = (a + b) * c
ee = a + (b * c)
ff = -(a ** b)
gg = a @ b
