d = {"a": 1, "b": 2}
print(d.get("a"), d.get("z"), d.get("z", 0), d.get("b", 99))
print(list(d.keys()))
print(list(d.values()))
print(list(d.items()))
print(len(list(d.keys())))
