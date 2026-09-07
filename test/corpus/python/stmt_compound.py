# Every compound statement, with and without its optional clauses.
xs = [1, 2, 3]

if xs:
    pass
elif not xs:
    pass
else:
    pass

if xs:
    pass

while xs:
    break
else:
    pass

for x in xs:
    continue
else:
    pass

for i, j in [(1, 2)]:
    pass

for [i, j] in [(1, 2)]:
    pass

try:
    pass
except ValueError:
    pass
except (TypeError, KeyError) as e:
    pass
except:
    pass
else:
    pass
finally:
    pass

try:
    pass
finally:
    pass

try:
    pass
except* ValueError:
    pass

with open("f") as fh:
    pass

with open("a") as a, open("b") as b:
    pass

with (open("a") as a, open("b") as b):
    pass

with open("a"):
    pass

if xs: pass
while False: break
for x in xs: pass
