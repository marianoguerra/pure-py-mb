# Indentation, continuation, comments and blank lines: everything that decides
# where NEWLINE, NL, INDENT and DEDENT go.
def outer():
    if True:
        x = 1

        # a comment inside a block, at the block's indentation
        y = 2
    else:

        x = 3
    return x


total = (1 +
         2 +
         # a comment inside brackets
         3)

joined = 1 + \
    2

nested = [
    [1, 2],
    {3: [4]},
]


class C:
    def a(self):
        pass

    def b(self):
        if True:
            pass
