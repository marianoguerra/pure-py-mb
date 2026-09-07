# Implicit concatenation, every prefix, and f-strings kept whole.
name = "world"
a = "one" "two"
b = "one" 'two' """three"""
c = b"one" b"two"
d = r"raw" "cooked"
e = f"hello {name}"
f = "before" f"{name}" "after"
g = f"{name!r:>{10}}"
h = f'{name}'
i = f"""
{name}
"""
j = rf"{name}\n"
