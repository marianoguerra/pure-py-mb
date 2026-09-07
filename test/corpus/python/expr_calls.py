# Every argument form, and the trailer chain.
def f(*args, **kwargs):
    return args


xs = [1, 2]
d = {"k": 1}
f()
f(1)
f(1, 2)
f(1, x=2)
f(*xs)
f(**d)
f(1, *xs, y=2, **d)
f(x for x in xs)
f((x for x in xs))
f(x for x in xs if x)
f(1)(2)(3)
f(1).real
f(1)[0]
f[0](1).real[2]
print(f(1, 2), sep="", end="\n")
