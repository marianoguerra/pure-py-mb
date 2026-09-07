# Every numeric form the tokenizer must split correctly. `1.` then `.5` then
# `1e10` then `1_0.0_1e-1_0`: each is one NUMBER token, and `1.j` is too.
a = 0
b = 00
c = 09
d = 1_000
e = 0x_ff
f = 0XFF
g = 0o17
h = 0O17
i = 0b1_0
j = 0B11
k = 1e10
m = 1E10
n = 1e+10
o = 1e-10
p = 1.
q = .5
r = 1.5
s = 1_0.0_1e-1_0
t = 3j
u = 3J
v = 1.5j
w = 0.0
x = 1000000000000000000000000000000000
y = 1 .real
z = (1).real
