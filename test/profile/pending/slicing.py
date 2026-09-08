xs = [0, 1, 2, 3, 4, 5]
s = "abcdef"
t = (0, 1, 2, 3)
print(xs[1:3], xs[:2], xs[3:], xs[:], xs[1:5:2])
print(xs[-2:], xs[:-2], xs[-4:-1], xs[::-1], xs[::2], xs[4:1:-1])
print(xs[10:], xs[:100], xs[5:2], xs[-100:100])
print(s[1:3], s[::-1], s[:0], s[2:])
print(t[1:3], t[::-1])
print(len(xs[:]), len(s[1:1]))
