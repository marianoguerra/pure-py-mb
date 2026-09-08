x = 42
name = "world"
xs = [1, 2, 3]
d = {"k": "v"}

print(f"the answer is {x}")
print(f"hello {name}!")
print(f"{x} and {x + 1} and {x * 2}")
print(f"{{literal braces}} around {x}")
print(f"}}{x}{{")
print(f"{name!r} {name!s}")
print(f"{xs[1]} {d['k']}")
print(f"{xs[0:2]}")
print(f"nested {f'inner {x}'}")
print(f"")
print(f"no holes at all")
print(f"{x}{x}{x}")

def label(n, prefix="#"):
    return f"{prefix}{n}"

print(label(1), label(2, ">"))
print(f"a" "b" f"{x}")
print(f'single {x} quotes')
print(f"""triple {x} quoted""")
print(f"{1 < x < 100}")
