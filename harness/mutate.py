"""Structure-aware mutators for MoonBit source.

针对闭源编译器的黑盒 fuzz：不做完整语法解析，只用括号/引号配平 + token 词表
做"近语法"变异，让大部分输入能穿过 lexer/parser 进入 typer / codegen。
"""
from __future__ import annotations

import random
import re

KEYWORDS = """
fn let mut match if else while for in return break continue raise try catch
async await struct enum trait impl type alias pub priv const test bench
derive dyn is as with where using guard loop do yield throw macro extern
import typealias traitalias super self true false not
""".split()

BUILTIN_TYPES = """
Int Int64 UInt UInt64 Double Float String Char Bool Unit Byte Bytes
Array ArrayView FixedArray Option Result
""".split()

OPERATORS = """
+ - * / % == != < > <= >= && || ! & | ^ << >> =
+= -= *= /= %= &= |= ^= <<= >>=
.. ... => -> :: .
""".split()

ATTRS = """
#[inline]
#[inline(always)]
#[inline(never)]
#[deprecated("x")]
#[test]
#[bench]
#[derive(Show)]
#[derive(Eq)]
#[derive(Compare)]
#[derive(Hash)]
#[derive(Default)]
#[derive(Arbitrary)]
#[coverage(never)]
#[js_only]
""".strip().splitlines()

LITERALS = [
    "0", "-1", "1", "2147483647", "-2147483648", "9223372036854775807",
    "-9223372036854775808", "18446744073709551615", "0x7fffffff", "0xffffffffffffffff",
    "1.0", "-0.0", "1e308", "1e-308", "0x1p-1074", "nan", "infinity",
    '""', '"\\u{0}"', '"\\u{10FFFF}"', '"\\u{110000}"', '"\\x00"', "'a'", "'\\u{0}'",
    "'\\u{10FFFF}'", "'\\u{110000}'", "b\"\\xff\"", "b'\\xff'",
    "true", "false", "()", "[]", "{}",
]

UNICODE_SEEDS = [
    "\u200b", "\ufeff", "\u0301", "\U0001f600", "\u202e", "\u0085",
    "\u00e9", "\u4e2d", "\ud7ff", "\ue000",
]

TOKEN_RE = re.compile(
    r'(?P<str>"(?:\\.|[^"\\])*")'
    r'|(?P<chr>\'(?:\\.|[^\'\\])*\')'
    r'|(?P<id>[A-Za-z_][A-Za-z0-9_]*)'
    r'|(?P<num>0[xX][0-9a-fA-F_]+|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][-+]?[0-9]+)?)'
    r'|(?P<op>[+\-*/%=<>&|^!~?:.@#,;()\[\]{}]+)'
)


def _boundaries(src: str):
    """返回 (start,end) 配平的括号区间，用于块级操作。"""
    stack, out = [], []
    pairs = {")": "(", "]": "[", "}": "{"}
    in_str = in_chr = False
    esc = False
    i = 0
    while i < len(src):
        c = src[i]
        if in_str or in_chr:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif (in_str and c == '"') or (in_chr and c == "'"):
                in_str = in_chr = False
        else:
            if c == '"':
                in_str = True
            elif c == "'":
                in_chr = True
            elif c in "([{":
                stack.append(i)
            elif c in ")]}":
                if stack and src[stack[-1]] == pairs[c]:
                    s = stack.pop()
                    out.append((s, i))
        i += 1
    return out


def _tokens(src: str):
    return [(m.lastgroup, m.group(0), m.start(), m.end()) for m in TOKEN_RE.finditer(src)]


def _fresh(rng, base="v"):
    return f"{base}{rng.randrange(10000)}"


def _dict_tokens():
    """AFL dictionary 格式的 token 表（harness/moonbit.dict），供注入用。"""
    import os
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "moonbit.dict")
    out = []
    try:
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if len(line) >= 2 and line[0] == '"' and line[-1] == '"':
                out.append(line[1:-1])
    except OSError:
        pass
    return out


DICT = []


def m_dict_token(src, rng):
    """用词典里的真 API 名/类型名替换一个标识符。

    实测：插入式（在随机边界插 token）会把 parse 成功率从 36% 压到 30%，
    替换式则保持 86%（400 次采样）。所以只做替换，不做插入。
    """
    global DICT
    if not DICT:
        DICT = _dict_tokens()
    toks = [t for t in _tokens(src) if t[0] == "id"]
    if not toks:
        return src
    kind, val, s, e = rng.choice(toks)
    cands = [d for d in DICT
             if d != val and d not in KEYWORDS
             and len(d) < 24 and d.replace("_", "a").isalnum()]
    if not cands:
        return src
    return src[:s] + rng.choice(cands) + src[e:]


def m_replace_token(src, rng):
    toks = _tokens(src)
    if not toks:
        return src
    kind, val, s, e = rng.choice(toks)
    if kind == "id":
        pool = KEYWORDS + BUILTIN_TYPES + [t[1] for t in toks if t[0] == "id"] + [_fresh(rng)]
        rep = rng.choice(pool)
    elif kind == "num":
        rep = rng.choice(LITERALS)
    elif kind == "str":
        rep = rng.choice(['"a"', '""', '"\\u{10FFFF}"', '"%.100s"', '"$(1)"'])
    elif kind == "chr":
        rep = rng.choice(["'a'", "'\\u{0}'", "'\\n'"])
    else:
        rep = rng.choice(OPERATORS + ["(", ")", "{", "}", "[", "]", ",", ";"])
    return src[:s] + rep + src[e:]


def m_dup_block(src, rng):
    bs = _boundaries(src)
    if not bs:
        return src
    s, e = rng.choice(bs)
    if e - s > 4000:
        return src
    return src[:e + 1] + "\n" + src[s:e + 1] + src[e + 1:]


def m_del_block(src, rng):
    bs = [b for b in _boundaries(src) if b[1] - b[0] < 2000]
    if not bs:
        return src
    s, e = rng.choice(bs)
    return src[:s] + src[e + 1:]


def m_wrap(src, rng):
    bs = [b for b in _boundaries(src) if 0 < b[1] - b[0] < 1000]
    if not bs:
        return src
    s, e = rng.choice(bs)
    frag = src[s:e + 1]
    wrappers = [
        ("if true { ", " }"),
        ("if false { ", " } else { %s }" % frag),
        ("match () { () => ", " }"),
        ("{ ", " }"),
        ("try { ", " } catch { _ => () }"),
        ("loop { break ", " }"),
    ]
    a, b = rng.choice(wrappers)
    return src[:s] + a + frag + b + src[e + 1:]


def m_insert_stmt(src, rng):
    stmts = [
        "let x = 1", "let x = 1 + 2", "let x : Int = 0", "let mut y = 0\ny = y + 1",
        "for i in 0..10 { () }", "while false { () }", "if true { () }",
        "match 1 { 1 => () _ => () }", "let f = fn() { () }", "f()",
        "raise Failure(\"x\")", "let (a, b) = (1, 2)", "return",
        "loop { break }", "let s = \"a\\u{1F600}b\"", "let a : Array[Int] = []",
        "#[inline]\nfn g() -> Int { 0 }",
    ]
    lines = src.splitlines(keepends=True)
    if not lines:
        return src
    i = rng.randrange(len(lines))
    ind = re.match(r"\s*", lines[i]).group(0)
    return "".join(lines[:i + 1]) + ind + rng.choice(stmts) + "\n" + "".join(lines[i + 1:])


def m_splice_fn(src, rng, pool):
    cand = [p for p in pool if p is not src and len(p) < 4000]
    if not cand:
        return src
    other = rng.choice(cand)
    fns = re.findall(r"(?ms)^(?:#\[[^\n]*\]\n)?(?:pub )?fn .*?^\}", other)
    if not fns:
        return src
    return src + "\n\n" + rng.choice(fns) + "\n"


def m_literal_edges(src, rng):
    nums = [m for m in re.finditer(r"(?<![\w.])\d{1,18}(?![\w.])", src)]
    if not nums:
        return src
    m = rng.choice(nums)
    return src[:m.start()] + rng.choice(LITERALS) + src[m.end():]


def m_rename_ident(src, rng):
    toks = _tokens(src)
    ids = [t[1] for t in toks if t[0] == "id" and t[1] not in KEYWORDS]
    if not ids:
        return src
    old = rng.choice(ids)
    new = _fresh(rng, old[:2] or "r")
    return re.sub(rf"\b{re.escape(old)}\b", new, src)


def m_inject_attr(src, rng):
    lines = src.splitlines(keepends=True)
    idx = [i for i, l in enumerate(lines) if re.match(r"\s*(pub )?(fn|struct|enum|trait|impl|type|let)\b", l)]
    if not idx:
        return src
    i = rng.choice(idx)
    ind = re.match(r"\s*", lines[i]).group(0)
    return "".join(lines[:i]) + ind + rng.choice(ATTRS) + "\n" + "".join(lines[i:])


def m_unicode(src, rng):
    pos = rng.randrange(len(src) + 1)
    ch = rng.choice(UNICODE_SEEDS)
    return src[:pos] + ch + src[pos:]


def m_truncate(src, rng):
    if len(src) < 4:
        return src
    cut = rng.randrange(1, len(src))
    return src[:cut]


def m_delim(src, rng):
    idx = [i for i, c in enumerate(src) if c in "()[]{}"]
    if not idx:
        return src
    i = rng.choice(idx)
    return src[:i] + src[i + 1:]


def m_bitflip(src, rng):
    b = bytearray(src.encode("utf-8", "surrogatepass"))
    if not b:
        return src
    for _ in range(rng.randint(1, 4)):
        i = rng.randrange(len(b))
        b[i] = rng.randrange(256)
    return b.decode("utf-8", "surrogateescape")


def m_generic(src, rng):
    m = re.search(r"\bfn\s+([A-Za-z_]\w*)\s*\(", src)
    if not m:
        return src
    return src[:m.end() - 1] + "[T] (x : T) -> T" + src[m.end() - 1:].replace("(", " (", 1)[0:]


def m_async(src, rng):
    return src + "\n\nasync fn __af() -> Unit { () }\nfn __bf() -> Unit raise Failure { () }\n"


def m_comment_cut(src, rng):
    return src + "\n/*" + "x" * rng.randrange(1, 200)


def m_body(src, rng):
    """只改函数体内部：保持顶层声明结构，提升"能过 parser 并进到 typer"的比例。"""
    bs = [b for b in _boundaries(src) if 20 < b[1] - b[0] < 6000]
    if not bs:
        return src
    s, e = rng.choice(bs)
    inner = src[s + 1:e]
    for _ in range(rng.randint(1, 3)):
        fn = rng.choice([m_replace_token, m_insert_stmt, m_literal_edges,
                         m_wrap, m_dup_block, m_rename_ident, m_dict_token])
        try:
            inner = fn(inner, rng)
        except Exception:
            pass
    return src[:s + 1] + inner + src[e:]


OPS = [
    (m_replace_token, 30), (m_dict_token, 8), (m_insert_stmt, 14), (m_dup_block, 8), (m_wrap, 8),
    (m_delim, 8), (m_truncate, 6), (m_bitflip, 5), (m_literal_edges, 5),
    (m_unicode, 5), (m_rename_ident, 4), (m_inject_attr, 4), (m_del_block, 3),
    (m_splice_fn, 3), (m_generic, 2), (m_async, 1), (m_comment_cut, 1),
]


def mutate(src: str, rng: random.Random, pool, body_only: bool = False) -> str:
    n = 1 if rng.random() < 0.55 else rng.randint(2, 5)
    for _ in range(n):
        if body_only and rng.random() < 0.85:
            fn = m_body
        else:
            fn = rng.choices(OPS, weights=[w for _, w in OPS])[0][0]
        try:
            if fn is m_splice_fn:
                src = fn(src, rng, pool)
            else:
                src = fn(src, rng)
        except Exception:
            pass
        if len(src) > 20000:
            src = src[:20000]
    return src
