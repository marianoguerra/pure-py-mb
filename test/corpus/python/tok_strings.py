# Prefixes in every case and combination, both quotes, triples, escapes, raw
# strings whose backslash still defers the quote, and implicit concatenation.
a = "double"
b = 'single'
c = """triple
double"""
d = '''triple
single'''
e = r"raw\n"
f = R"RAW\""
g = b"bytes"
h = B'bytes'
i = rb"rawbytes\x00"
j = bR"rawbytes"
k = Br'rawbytes'
m = u"unicode"
n = U'unicode'
o = "escapes: \n \t \\ \' \" \a \b \f \v \0 \101 \x41 é \N{BULLET}"
p = "implicit" "concatenation" 'of' """three kinds"""
q = "quote ' inside"
r = 'quote " inside'
s = ""
t = ''
u = """"""
v = "line one \
line two"
