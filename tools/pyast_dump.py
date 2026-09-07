#!/usr/bin/env python3
"""CPython's answer for the `ast` oracle.

Prints the tree in the format `ast::dump` defines: one node per line, two
spaces of indentation per level, scalar fields on the node's line in ASDL
order, child fields introduced by name on their own line.

Two things this script has to reconstruct, because CPython's tree does not
carry them:

  * A sequence PATTERN's bracket. The spec distinguishes `case [a]:` from
    `case (a):`, and `ast` records `MatchSequence` for both; the bracket is
    read back out of the source segment, which is what `syntax.py` does.
  * CODE-POINT columns. CPython's `col_offset` counts UTF-8 bytes.

With `--pos`, every node that carries a position in CPython's tree gets
`@l:c-l:c`. `Module`, `arguments`, `comprehension`, `withitem` and
`match_case` carry none, and get none here either.
"""

from __future__ import annotations

import ast
import sys


class Dumper:
    def __init__(self, source: str, pos: bool) -> None:
        self.pos = pos
        self.out: list[str] = []
        self.lines = source.split("\n")

    # -- positions ---------------------------------------------------------

    def col(self, line: int, byte_col: int) -> int:
        """CPython counts UTF-8 bytes; we count code points."""
        if line - 1 >= len(self.lines):
            return byte_col
        text = self.lines[line - 1]
        raw = text.encode("utf-8")[:byte_col]
        return len(raw.decode("utf-8", errors="replace"))

    def at(self, node: ast.AST) -> str:
        if not self.pos:
            return ""
        lineno = getattr(node, "lineno", None)
        if lineno is None:
            return ""
        end_lineno = node.end_lineno or lineno
        a = self.col(lineno, node.col_offset)
        b = self.col(end_lineno, node.end_col_offset or 0)
        return f" @{lineno}:{a}-{end_lineno}:{b}"

    # -- emitting ----------------------------------------------------------

    def line(self, depth: int, text: str) -> None:
        self.out.append("  " * depth + text)

    def node(self, depth: int, kind: str, scalars: list[str], at: str = "") -> None:
        parts = " ".join(scalars)
        head = f"{kind} {parts}" if parts else kind
        self.line(depth, head + at)

    def field(self, depth: int, name: str, absent: bool = False) -> None:
        self.line(depth, f"{name}: -" if absent else f"{name}:")

    # -- scalars -----------------------------------------------------------

    @staticmethod
    def opt_id(v: str | None) -> str:
        return v if v is not None else "-"

    @staticmethod
    def id_list(names: list[str]) -> str:
        return "[" + " ".join(names) + "]"

    @staticmethod
    def literal(v: object) -> str:
        if v is Ellipsis:
            return "Ellipsis"
        return repr(v)


BINOPS = {
    ast.Add: "Add", ast.Sub: "Sub", ast.Mult: "Mult", ast.MatMult: "MatMult",
    ast.Div: "Div", ast.Mod: "Mod", ast.Pow: "Pow", ast.LShift: "LShift",
    ast.RShift: "RShift", ast.BitOr: "BitOr", ast.BitXor: "BitXor",
    ast.BitAnd: "BitAnd", ast.FloorDiv: "FloorDiv",
}
UNARYOPS = {ast.Invert: "Invert", ast.Not: "Not", ast.UAdd: "UAdd", ast.USub: "USub"}
CMPOPS = {
    ast.Eq: "Eq", ast.NotEq: "NotEq", ast.Lt: "Lt", ast.LtE: "LtE", ast.Gt: "Gt",
    ast.GtE: "GtE", ast.Is: "Is", ast.IsNot: "IsNot", ast.In: "In", ast.NotIn: "NotIn",
}
CTX = {ast.Load: "Load", ast.Store: "Store", ast.Del: "Del"}


def op_name(o: ast.AST) -> str:
    for table in (BINOPS, UNARYOPS, CMPOPS, CTX):
        if type(o) in table:
            return table[type(o)]
    raise AssertionError(f"unknown operator {o!r}")


class Walk(Dumper):
    # -- statements --------------------------------------------------------

    def stmts(self, depth: int, name: str, body: list[ast.stmt]) -> None:
        self.field(depth, name)
        for s in body:
            self.stmt(s, depth + 1)

    def exprs(self, depth: int, name: str, items: list[ast.expr]) -> None:
        self.field(depth, name)
        for e in items:
            self.expr(e, depth + 1)

    def child(self, depth: int, name: str, e: ast.expr) -> None:
        self.field(depth, name)
        self.expr(e, depth + 1)

    def opt_child(self, depth: int, name: str, e: ast.expr | None) -> None:
        if e is None:
            self.field(depth, name, absent=True)
        else:
            self.field(depth, name)
            self.expr(e, depth + 1)

    def stmt(self, s: ast.stmt, depth: int) -> None:
        d = depth + 1
        at = self.at(s)
        if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
            is_async = isinstance(s, ast.AsyncFunctionDef)
            self.node(depth, "FunctionDef",
                      [f"name={s.name}", f"is_async={is_async}"], at)
            self.field(d, "args")
            self.arguments(s.args, d + 1)
            self.stmts(d, "body", s.body)
            self.exprs(d, "decorator_list", s.decorator_list)
            self.opt_child(d, "returns", s.returns)
        elif isinstance(s, ast.ClassDef):
            self.node(depth, "ClassDef", [f"name={s.name}"], at)
            self.exprs(d, "bases", s.bases)
            self.field(d, "keywords")
            for k in s.keywords:
                self.keyword(k, d + 1)
            self.stmts(d, "body", s.body)
            self.exprs(d, "decorator_list", s.decorator_list)
        elif isinstance(s, ast.Return):
            self.node(depth, "Return", [], at)
            self.opt_child(d, "value", s.value)
        elif isinstance(s, ast.Delete):
            self.node(depth, "Delete", [], at)
            self.exprs(d, "targets", s.targets)
        elif isinstance(s, ast.Assign):
            self.node(depth, "Assign", [], at)
            self.exprs(d, "targets", s.targets)
            self.child(d, "value", s.value)
        elif isinstance(s, ast.AugAssign):
            self.node(depth, "AugAssign", [f"op={op_name(s.op)}"], at)
            self.child(d, "target", s.target)
            self.child(d, "value", s.value)
        elif isinstance(s, ast.AnnAssign):
            self.node(depth, "AnnAssign", [f"simple={bool(s.simple)}"], at)
            self.child(d, "target", s.target)
            self.child(d, "annotation", s.annotation)
            self.opt_child(d, "value", s.value)
        elif isinstance(s, (ast.For, ast.AsyncFor)):
            self.node(depth, "For", [f"is_async={isinstance(s, ast.AsyncFor)}"], at)
            self.child(d, "target", s.target)
            self.child(d, "iter", s.iter)
            self.stmts(d, "body", s.body)
            self.stmts(d, "orelse", s.orelse)
        elif isinstance(s, ast.While):
            self.node(depth, "While", [], at)
            self.child(d, "test", s.test)
            self.stmts(d, "body", s.body)
            self.stmts(d, "orelse", s.orelse)
        elif isinstance(s, ast.If):
            self.node(depth, "If", [], at)
            self.child(d, "test", s.test)
            self.stmts(d, "body", s.body)
            self.stmts(d, "orelse", s.orelse)
        elif isinstance(s, (ast.With, ast.AsyncWith)):
            self.node(depth, "With", [f"is_async={isinstance(s, ast.AsyncWith)}"], at)
            self.field(d, "items")
            for it in s.items:
                self.with_item(it, d + 1)
            self.stmts(d, "body", s.body)
        elif isinstance(s, ast.Match):
            self.node(depth, "Match", [], at)
            self.child(d, "subject", s.subject)
            self.field(d, "cases")
            for c in s.cases:
                self.match_case(c, d + 1)
        elif isinstance(s, ast.Raise):
            self.node(depth, "Raise", [], at)
            self.opt_child(d, "exc", s.exc)
            self.opt_child(d, "cause", s.cause)
        elif isinstance(s, (ast.Try, getattr(ast, "TryStar", ast.Try))):
            is_star = type(s).__name__ == "TryStar"
            self.node(depth, "Try", [f"is_star={is_star}"], at)
            self.stmts(d, "body", s.body)
            self.field(d, "handlers")
            for h in s.handlers:
                self.handler(h, d + 1)
            self.stmts(d, "orelse", s.orelse)
            self.stmts(d, "finalbody", s.finalbody)
        elif isinstance(s, ast.Assert):
            self.node(depth, "Assert", [], at)
            self.child(d, "test", s.test)
            self.opt_child(d, "msg", s.msg)
        elif isinstance(s, ast.Import):
            self.node(depth, "Import", [], at)
            self.field(d, "names")
            for a in s.names:
                self.alias(a, d + 1)
        elif isinstance(s, ast.ImportFrom):
            self.node(depth, "ImportFrom",
                      [f"module={self.opt_id(s.module)}", f"level={s.level or 0}"], at)
            self.field(d, "names")
            for a in s.names:
                self.alias(a, d + 1)
        elif isinstance(s, ast.Global):
            self.node(depth, "Global", [f"names={self.id_list(s.names)}"], at)
        elif isinstance(s, ast.Nonlocal):
            self.node(depth, "Nonlocal", [f"names={self.id_list(s.names)}"], at)
        elif isinstance(s, ast.Expr):
            self.node(depth, "Expr", [], at)
            self.child(d, "value", s.value)
        elif isinstance(s, ast.Pass):
            self.node(depth, "Pass", [], at)
        elif isinstance(s, ast.Break):
            self.node(depth, "Break", [], at)
        elif isinstance(s, ast.Continue):
            self.node(depth, "Continue", [], at)
        else:
            raise AssertionError(f"unhandled statement {type(s).__name__}")

    # -- expressions -------------------------------------------------------

    def expr(self, e: ast.expr, depth: int) -> None:
        d = depth + 1
        at = self.at(e)
        if isinstance(e, ast.BoolOp):
            self.node(depth, "BoolOp", [f"op={'And' if isinstance(e.op, ast.And) else 'Or'}"], at)
            self.exprs(d, "values", e.values)
        elif isinstance(e, ast.NamedExpr):
            self.node(depth, "NamedExpr", [], at)
            self.child(d, "target", e.target)
            self.child(d, "value", e.value)
        elif isinstance(e, ast.BinOp):
            self.node(depth, "BinOp", [f"op={op_name(e.op)}"], at)
            self.child(d, "left", e.left)
            self.child(d, "right", e.right)
        elif isinstance(e, ast.UnaryOp):
            self.node(depth, "UnaryOp", [f"op={op_name(e.op)}"], at)
            self.child(d, "operand", e.operand)
        elif isinstance(e, ast.Lambda):
            self.node(depth, "Lambda", [], at)
            self.field(d, "args")
            self.arguments(e.args, d + 1)
            self.child(d, "body", e.body)
        elif isinstance(e, ast.IfExp):
            self.node(depth, "IfExp", [], at)
            self.child(d, "test", e.test)
            self.child(d, "body", e.body)
            self.child(d, "orelse", e.orelse)
        elif isinstance(e, ast.Dict):
            self.node(depth, "Dict", [], at)
            self.field(d, "keys")
            for k in e.keys:
                if k is None:
                    self.line(d + 1, "-")
                else:
                    self.expr(k, d + 1)
            self.exprs(d, "values", e.values)
        elif isinstance(e, ast.Set):
            self.node(depth, "Set", [], at)
            self.exprs(d, "elts", e.elts)
        elif isinstance(e, ast.ListComp):
            self.node(depth, "ListComp", [], at)
            self.child(d, "elt", e.elt)
            self.comprehensions(e.generators, d)
        elif isinstance(e, ast.SetComp):
            self.node(depth, "SetComp", [], at)
            self.child(d, "elt", e.elt)
            self.comprehensions(e.generators, d)
        elif isinstance(e, ast.DictComp):
            self.node(depth, "DictComp", [], at)
            self.child(d, "key", e.key)
            self.child(d, "value", e.value)
            self.comprehensions(e.generators, d)
        elif isinstance(e, ast.GeneratorExp):
            self.node(depth, "GeneratorExp", [], at)
            self.child(d, "elt", e.elt)
            self.comprehensions(e.generators, d)
        elif isinstance(e, ast.Await):
            self.node(depth, "Await", [], at)
            self.child(d, "value", e.value)
        elif isinstance(e, ast.Yield):
            self.node(depth, "Yield", [], at)
            self.opt_child(d, "value", e.value)
        elif isinstance(e, ast.YieldFrom):
            self.node(depth, "YieldFrom", [], at)
            self.child(d, "value", e.value)
        elif isinstance(e, ast.Compare):
            ops = "[" + " ".join(op_name(o) for o in e.ops) + "]"
            self.node(depth, "Compare", [f"ops={ops}"], at)
            self.child(d, "left", e.left)
            self.exprs(d, "comparators", e.comparators)
        elif isinstance(e, ast.Call):
            self.node(depth, "Call", [], at)
            self.child(d, "func", e.func)
            self.exprs(d, "args", e.args)
            self.field(d, "keywords")
            for k in e.keywords:
                self.keyword(k, d + 1)
        elif isinstance(e, ast.JoinedStr):
            self.node(depth, "JoinedStr", [f"raw={self.segment(e)!r}"], at)
        elif isinstance(e, ast.Constant):
            self.node(depth, "Constant", [f"value={self.literal(e.value)}"], at)
        elif isinstance(e, ast.Attribute):
            self.node(depth, "Attribute",
                      [f"attr={e.attr}", f"ctx={op_name(e.ctx)}"], at)
            self.child(d, "value", e.value)
        elif isinstance(e, ast.Subscript):
            self.node(depth, "Subscript", [f"ctx={op_name(e.ctx)}"], at)
            self.child(d, "value", e.value)
            self.child(d, "slice", e.slice)
        elif isinstance(e, ast.Starred):
            self.node(depth, "Starred", [f"ctx={op_name(e.ctx)}"], at)
            self.child(d, "value", e.value)
        elif isinstance(e, ast.Name):
            self.node(depth, "Name", [f"id={e.id}", f"ctx={op_name(e.ctx)}"], at)
        elif isinstance(e, ast.List):
            self.node(depth, "List", [f"ctx={op_name(e.ctx)}"], at)
            self.exprs(d, "elts", e.elts)
        elif isinstance(e, ast.Tuple):
            self.node(depth, "Tuple", [f"ctx={op_name(e.ctx)}"], at)
            self.exprs(d, "elts", e.elts)
        elif isinstance(e, ast.Slice):
            self.node(depth, "Slice", [], at)
            self.opt_child(d, "lower", e.lower)
            self.opt_child(d, "upper", e.upper)
            self.opt_child(d, "step", e.step)
        else:
            raise AssertionError(f"unhandled expression {type(e).__name__}")

    def segment(self, node: ast.AST) -> str:
        return ast.get_source_segment(self.source, node) or ""

    # -- helper nodes ------------------------------------------------------

    def comprehensions(self, gens: list[ast.comprehension], depth: int) -> None:
        self.field(depth, "generators")
        for g in gens:
            self.line(depth + 1, f"comprehension is_async={bool(g.is_async)}")
            self.child(depth + 2, "target", g.target)
            self.child(depth + 2, "iter", g.iter)
            self.exprs(depth + 2, "ifs", g.ifs)

    def arguments(self, a: ast.arguments, depth: int) -> None:
        self.line(depth, "arguments")
        d = depth + 1
        self.field(d, "posonlyargs")
        for x in a.posonlyargs:
            self.arg(x, d + 1)
        self.field(d, "args")
        for x in a.args:
            self.arg(x, d + 1)
        if a.vararg is None:
            self.field(d, "vararg", absent=True)
        else:
            self.field(d, "vararg")
            self.arg(a.vararg, d + 1)
        self.field(d, "kwonlyargs")
        for x in a.kwonlyargs:
            self.arg(x, d + 1)
        self.field(d, "kw_defaults")
        for x in a.kw_defaults:
            if x is None:
                self.line(d + 1, "-")
            else:
                self.expr(x, d + 1)
        if a.kwarg is None:
            self.field(d, "kwarg", absent=True)
        else:
            self.field(d, "kwarg")
            self.arg(a.kwarg, d + 1)
        self.exprs(d, "defaults", a.defaults)

    def arg(self, a: ast.arg, depth: int) -> None:
        self.node(depth, "arg", [f"arg={a.arg}"], self.at(a))
        self.opt_child(depth + 1, "annotation", a.annotation)

    def keyword(self, k: ast.keyword, depth: int) -> None:
        self.node(depth, "keyword", [f"arg={self.opt_id(k.arg)}"], self.at(k))
        self.child(depth + 1, "value", k.value)

    def alias(self, a: ast.alias, depth: int) -> None:
        self.node(depth, "alias",
                  [f"name={a.name}", f"asname={self.opt_id(a.asname)}"], self.at(a))

    def with_item(self, w: ast.withitem, depth: int) -> None:
        self.line(depth, "withitem")
        self.child(depth + 1, "context_expr", w.context_expr)
        self.opt_child(depth + 1, "optional_vars", w.optional_vars)

    def handler(self, h: ast.ExceptHandler, depth: int) -> None:
        self.node(depth, "ExceptHandler", [f"name={self.opt_id(h.name)}"], self.at(h))
        self.opt_child(depth + 1, "type", h.type)
        self.stmts(depth + 1, "body", h.body)

    def match_case(self, c: ast.match_case, depth: int) -> None:
        self.line(depth, "match_case")
        d = depth + 1
        self.field(d, "pattern")
        self.pattern(c.pattern, d + 1)
        self.opt_child(d, "guard", c.guard)
        self.stmts(d, "body", c.body)

    # -- patterns ----------------------------------------------------------

    def patterns(self, depth: int, name: str, ps: list[ast.pattern]) -> None:
        self.field(depth, name)
        for p in ps:
            self.pattern(p, depth + 1)

    def seq_kind(self, p: ast.MatchSequence) -> str:
        """Which bracket the sequence was written with.

        `ast` forgets. The source segment is the only record: `[` means a list
        pattern, and anything else -- `(`, or nothing at all for a bare
        `case a, b:` -- means a tuple. This is what `syntax.py` does.
        """
        seg = ast.get_source_segment(self.source, p) or ""
        return "List" if seg.lstrip().startswith("[") else "Tuple"

    def pattern(self, p: ast.pattern, depth: int) -> None:
        d = depth + 1
        at = self.at(p)
        if isinstance(p, ast.MatchValue):
            self.node(depth, "MatchValue", [], at)
            self.child(d, "value", p.value)
        elif isinstance(p, ast.MatchSingleton):
            self.node(depth, "MatchSingleton", [f"value={self.literal(p.value)}"], at)
        elif isinstance(p, ast.MatchSequence):
            self.node(depth, "MatchSequence", [f"kind={self.seq_kind(p)}"], at)
            self.patterns(d, "patterns", p.patterns)
        elif isinstance(p, ast.MatchMapping):
            self.node(depth, "MatchMapping", [f"rest={self.opt_id(p.rest)}"], at)
            self.exprs(d, "keys", p.keys)
            self.patterns(d, "patterns", p.patterns)
        elif isinstance(p, ast.MatchClass):
            self.node(depth, "MatchClass",
                      [f"kwd_attrs={self.id_list(p.kwd_attrs)}"], at)
            self.child(d, "cls", p.cls)
            self.patterns(d, "patterns", p.patterns)
            self.patterns(d, "kwd_patterns", p.kwd_patterns)
        elif isinstance(p, ast.MatchStar):
            self.node(depth, "MatchStar", [f"name={self.opt_id(p.name)}"], at)
        elif isinstance(p, ast.MatchAs):
            self.node(depth, "MatchAs", [f"name={self.opt_id(p.name)}"], at)
            if p.pattern is None:
                self.field(d, "pattern", absent=True)
            else:
                self.field(d, "pattern")
                self.pattern(p.pattern, d + 1)
        elif isinstance(p, ast.MatchOr):
            self.node(depth, "MatchOr", [], at)
            self.patterns(d, "patterns", p.patterns)
        else:
            raise AssertionError(f"unhandled pattern {type(p).__name__}")


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    pos = "--pos" in sys.argv
    path = args[0]
    with open(path, "rb") as f:
        source = f.read().decode("utf-8-sig")
    # Universal newlines, as `Source::new` does.
    source = source.replace("\r\n", "\n").replace("\r", "\n")
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as e:
        print(f"!error {e.msg}")
        return
    w = Walk(source, pos)
    w.source = source
    w.out.append("Module")
    w.stmts(1, "body", tree.body)
    print("\n".join(w.out))


if __name__ == "__main__":
    main()
