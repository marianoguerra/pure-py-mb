def greet(name, greeting="hello", excited=False, pad=None):
    return [greeting, name, excited, pad]

print(greet("a"))
print(greet("a", "hi"))
print(greet("a", "hi", True))
print(greet("a", "hi", True, "x"))

def area(w, h=2.5):
    return w * h

print(area(4), area(4, 3.0))

f = lambda x, y=10: x + y
print(f(1), f(1, 2))

def only_defaults(a=1, b="two"):
    return [a, b]

print(only_defaults(), only_defaults(9), only_defaults(9, "!"))

def mutual_even(n, step=1):
    if n == 0:
        return True
    return mutual_odd(n - step)

def mutual_odd(n, step=1):
    if n == 0:
        return False
    return mutual_even(n - step)

print(mutual_even(4), mutual_odd(4))
