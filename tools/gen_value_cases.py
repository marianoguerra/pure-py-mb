#!/usr/bin/env python3
"""Generate `value/arith_table_test.mbt` from CPython.

Every operator over literals, with the answer CPython gives: its `repr`, or
the name of the exception it raises. A row PurePy leaves UNDEFINED is marked
by hand -- CPython has an answer for all of them, and the point of the row is
that this implementation does not.

The undefined rows are the reason the table is written rather than derived:
`True == 1` and `1 == "a"` are True and False in Python and have no rule in
PurePy, and a table generated purely from CPython would assert the wrong
thing.

Regenerate with `just tables`; the diff is the review artifact.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "lib" / "value" / "arith_table_test.mbt"

# `nan` and `inf` are not literals and PurePy has no `float()`, so a case that
# wants one builds it the way a PurePy program has to: out of an overflow.
NAN = "(1e308 * 10.0 - 1e308 * 10.0)"
INF = "(1e308 * 10.0)"

# Expressions over literals only: no names, no calls.
CASES = [
    # integer arithmetic, including the floor rules
    "1 + 2", "1 - 2", "3 * 4", "-7 // 2", "7 // 2", "7 // -2", "-7 // -2",
    "-7 % 2", "7 % 2", "7 % -2", "-7 % -2", "0 % 3", "2 ** 10", "2 ** 100",
    "2 ** 0", "0 ** 0", "7 / 2", "4 / 2", "-7 / 2", "1 + -2", "- -3",
    "2 ** -1", "10 ** -2", "1000000000000000000000 + 1",
    "1 / 0", "1 // 0", "1 % 0", "0 ** -1",
    # float arithmetic
    "1.0 + 2.0", "1.5 * 2.0", "7.0 / 2.0", "-7.5 // 2.0", "7.5 // 2.0",
    "-7.5 % 2.0", "7.5 % -2.0", "1.0 / 0.0", "1.0 // 0.0", "1.0 % 0.0",
    "2.0 ** 0.5", "0.1 + 0.2", "1e308 * 10.0", "-1e308 * 10.0",
    # a zero remainder takes the sign of the divisor, like every other
    "1.5 % -0.5", "4.0 % -2.0", "-1.5 % 0.5", "2.0 % -1.0", "-4.0 % 2.0",
    # every ordering against a nan is False; `==` and `!=` have their own rule
    f"{NAN} < 1.0", f"{NAN} <= 1.0", f"{NAN} > 1.0", f"{NAN} >= 1.0",
    f"1.0 < {NAN}", f"{NAN} < {NAN}", f"{NAN} >= {NAN}",
    f"{NAN} == {NAN}", f"{NAN} != {NAN}", f"{NAN} == 1.0",
    f"{INF} > 1e308", f"-{INF} < 0.0",
    "2.5 ** 2.0", "1.0 - 1.0", "-0.0 + 0.0",
    # mixed
    "1 + 2.0", "2.0 * 3", "7 / 2.0", "1 == 1.0", "1 < 1.5", "2 > 1.5",
    "1.5 <= 2", "1 >= 1.0", "3 // 2.0", "3 % 2.0",
    # unary
    "-1", "+1", "-1.5", "+1.5", "not True", "not False",
    # strings
    '"a" < "b"', '"b" < "a"', '"" < "a"', '"abc" == "abc"', '"a" != "b"',
    '"bc" in "abcd"', '"x" in "abcd"', '"x" not in "abcd"',
    # containers
    "[1, 2] == [1, 2]", "[1, 2] == [1, 3]", "[1, 2] < [1, 3]",
    "[1] < [1, 2]", "(1,) < (1, 2)", "(1, 2) == (1, 2)",
    "[1, 2, 3][0]", "[1, 2, 3][-1]", "[1, 2, 3][2]", "(10, 20)[1]",
    '"xyz"[0]', '"xyz"[-1]', '"héllo"[1]',
    '{"a": 1}["a"]', '{"a": 1, "b": 2} == {"b": 2, "a": 1}',
    '{"a": 1} == {"a": 2}', '{"a": 1} == {"b": 1}',
    '"a" in {"a": 1}', '"b" in {"a": 1}',
    "1 in [1, 2]", "3 in [1, 2]", "1 in (1, 2)",
    "[1, 2, 3][3]", "[1, 2, 3][-4]", "[][0]", '{"a": 1}["b"]',
    # equality with None
    "None == None", "None == 1", "1 == None", "None != None",
    # nested repr
    '[1, "a", (2, 3), {"k": 1.5}, None, True]', "('x',)", "()", "[]", "{}",
    '{"k": [1, (2,)]}',
    "True == True", "True != False", "True == True",
    # sequence concatenation and repetition: `+` and `*` are not arithmetic
    # over a str, a list or a tuple, so the arithmetic table's TypeError
    # sentence does not reach them
    '"a" + "b"', '"" + "a"', '"a" * 2', '2 * "a"', '"a" * 0', '"a" * -1',
    "[1] + [2]", "[] + [1]", "[1] * 2", "2 * [1]", "[1] * 0", "[1] * -1",
    "(1,) + (2,)", "() + (1,)", "(1,) * 2", "2 * (1,)", "(1,) * 0",
    '["a"] + [1]', '"" * 3', "[] * 3",
    # the mismatches and the non-sequence operators keep Python's TypeError
    '1 + "a"', '"a" + 1', "[1] + (2,)", "(1,) + [2]", '"a" + [1]',
    "1.5 + 'a'", "None + None", '"a" - "b"', "[1] - [2]", "1 + [2]",
    '{"a": 1} + {"b": 2}', '"a" * "b"', "[1] * [2]", '"a" * 1.5',
]

# What PurePy leaves undefined, and why. Each is something CPython answers.
UNDEFINED = {
    "True == 1": "bool against int",
    "1 == True": "bool against int",
    "True < 2": "bool is not a number",
    "True + 1": "bool is not a number",
    "True * 2": "bool is not a number",
    "-True": "bool is not a number",
    "+False": "bool is not a number",
    '"a" * True': "bool is not a count",
    "1 % False": "bool is not a number",
    "not 1": "truthiness",
    "not None": "truthiness",
    '1 == "a"': "unrelated kinds",
    '"a" == 1': "unrelated kinds",
    '[1, "a"] == [1, 3]': "eq reaches an undefined pair",
    "[1] == (1,)": "a list against a tuple",
    "1 < 'a'": "unrelated kinds",
    '{1: 2}': "a dict key that is not a string",
    "1 in 2": "membership in a number",
    '[1] < (1,)': "a list against a tuple",
    # `%` on a string is Python's printf formatting, which PurePy does not
    # model. Undefined, not TypeError: Python has an answer, it is just not
    # one this subset gives.
    '"%d" % 3': "string formatting",
    '"a-%s" % "b"': "string formatting",
    '"a" % []': "string formatting",
}


# What PurePy ABORTS with TypeError although Python has a value for it.
#
# Empty, and meant to stay that way. A termination kind is named after the
# exception the same program raises under Python, so a row here would be this
# implementation claiming an exception Python does not raise. The rows that
# used to live here -- string concatenation, list repetition, `%` on a string,
# a bool in arithmetic -- are now either answered or undefined.
TYPE_ERROR: dict[str, str] = {}


def answer(expr: str) -> str:
    try:
        v = eval(expr)  # noqa: S307 - literal expressions from the list above
    except ZeroDivisionError:
        return "!ZeroDivisionError"
    except IndexError:
        return "!IndexError"
    except KeyError:
        return "!KeyError"
    except TypeError:
        return "!TypeError"
    except Exception as e:  # noqa: BLE001
        return f"!{type(e).__name__}"
    return repr(v)


def mbt_string(s: str) -> str:
    out = ['"']
    for c in s:
        if c == '"':
            out.append('\\"')
        elif c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        else:
            out.append(c)
    out.append('"')
    return "".join(out)


def main() -> None:
    rows = []
    for expr in CASES:
        rows.append(f"  ({mbt_string(expr)}, {mbt_string(answer(expr))}),")
    type_errors = []
    for expr, why in sorted(TYPE_ERROR.items()):
        type_errors.append(
            f"  // {why}; CPython says {answer(expr)}\n"
            f"  {mbt_string(expr)},"
        )
    undefined = []
    for expr, why in sorted(UNDEFINED.items()):
        # The comment records what CPython says, so a reader can see what is
        # being given up.
        undefined.append(
            f"  // {why}; CPython says {answer(expr)}\n"
            f"  {mbt_string(expr)},"
        )

    OUT.write_text(f'''// Generated by tools/gen_value_cases.py from CPython. DO NOT EDIT.
//
// Every operator over literals, with CPython's answer: its `repr`, or
// `!Name` for the exception it raises. The second table is the rows PurePy
// leaves UNDEFINED -- CPython answers all of them, which is exactly why they
// cannot be generated.

///|
let arith_cases : Array[(String, String)] = [
{chr(10).join(rows)}
]

///|
let undefined_cases : Array[String] = [
{chr(10).join(undefined)}
]

///|
let type_error_cases : Array[String] = [
{chr(10).join(type_errors)}
]

///|
test "every operator over literals answers as CPython answers" {{
  for case in arith_cases {{
    let (expr, want) = case
    assert_eq(evaluate(expr), want, msg=expr)
  }}
}}

///|
test "the operations PurePy leaves undefined" {{
  for expr in undefined_cases {{
    assert_eq(evaluate(expr), "!stuck", msg=expr)
  }}
}}

///|
test "the operations PurePy aborts where Python has an answer" {{
  for expr in type_error_cases {{
    assert_eq(evaluate(expr), "!TypeError", msg=expr)
  }}
}}
''')
    print(f"wrote {OUT.relative_to(ROOT)} ({len(rows)} rows, "
          f"{len(undefined)} undefined, {len(type_errors)} type errors)")


if __name__ == "__main__":
    main()
