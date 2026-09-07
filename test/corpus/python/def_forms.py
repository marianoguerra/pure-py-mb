# Every parameter form, in every order the grammar allows.
def a():
    pass


def b(x):
    pass


def c(x, y):
    pass


def d(x=1):
    pass


def e(x, y=1, z=2):
    pass


def f(*args):
    pass


def g(**kwargs):
    pass


def h(x, *args, y, **kwargs):
    pass


def i(x, *, y):
    pass


def j(x, /, y):
    pass


def k(x, /, y, *, z):
    pass


def m(x: int, y: str = "a") -> bool:
    return True


def n(*, x=1, y=2):
    pass


def o(x, /, *args, y=1, **kw):
    pass


async def p():
    await q()


async def q():
    async with r() as x:
        async for y in x:
            pass


def r():
    return [x async for x in q()]


def deco(f):
    return f


@deco
def s():
    pass


@deco
@deco
def t():
    pass


@deco(1)
def u():
    pass
