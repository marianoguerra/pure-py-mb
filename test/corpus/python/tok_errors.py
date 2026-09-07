# Identifiers that are nearly string prefixes, and string prefixes that are
# nearly identifiers. `rb` is a prefix; `rbx` is a name.
r = 1
b = 2
f = 3
u = 4
rb = 5
fr = 6
br7 = 7
uu = "not a prefix pair"
print(r, b, f, u, rb, fr, br7, uu)
match = 1
case = 2
type = 3
_ = 4
print(match, case, type, _)


def match_stmt(x):
    match x:
        case 1:
            return "one"
        case _:
            return "other"
