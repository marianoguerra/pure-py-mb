# Class headers, bodies and decorators.
def deco(c):
    return c


class A:
    pass


class B():
    pass


class C(A):
    pass


class D(A, B):
    pass


class E(A, metaclass=type):
    pass


class F(**{}):
    pass


@deco
class G:
    x: int = 1

    def m(self):
        return self.x

    class Inner:
        pass
