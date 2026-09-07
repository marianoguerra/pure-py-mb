# f-strings arrive from `tokenize` in pieces and are collapsed back into one
# token on both sides. The nested-quote form is Python 3.12's (PEP 701).
name = "world"
d = {"k": 1}
a = f"hello {name}"
b = f"{d['k']}"
c = F"{name!r:>10}"
e = f"literal {{braces}} and {name}"
g = rf"raw {name}\n"
h = fR"raw {name}"
i = f"""triple {name}
across lines"""
j = f"nested {f'inner {name}'}"
k = f""
