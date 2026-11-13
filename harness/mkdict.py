#!/usr/bin/env python3
"""从 core 的 .mbti 抽 token 词典，给 AFL 用（E 层，成本≈0）。

只抽词法层面的东西：关键字、标识符、运算符。目的是让 token 级变异的
命中率上升，不是文法生成器。
"""
import os
import re
import sys
from collections import Counter

CORE = os.path.expanduser("~/.moon/lib/core")
ID = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
OPS = ["->", "=>", "|>", "<=", ">=", "==", "!=", "&&", "||", "..", "::", "#|",
       "@", "~", "^", "%", "+", "-", "*", "/", "=", "<", ">", "|", "&", "!", "?",
       "(", ")", "[", "]", "{", "}", ",", ":", ";"]

KEYWORDS = """fn let mut const type struct enum trait impl pub priv static
match if else while for in return break continue true false raise try catch
async await extern import test with derive guard as is not init main
sub error panic abort defer loop""".split()


def main():
    freq = Counter()
    for dp, _, fs in os.walk(CORE):
        for f in fs:
            if not f.endswith(".mbti"):
                continue
            try:
                txt = open(os.path.join(dp, f), encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            for m in ID.findall(txt):
                freq[m] += 1
    # 只保留出现 >=2 次的标识符，避免仓库里一次性的怪名字把词典撑爆
    idents = [w for w, c in freq.items() if c >= 2 and len(w) > 1]
    idents.sort(key=lambda w: (-freq[w], w))
    toks = list(dict.fromkeys(KEYWORDS + OPS + idents[:3000]))
    out = sys.argv[1] if len(sys.argv) > 1 else "harness/moonbit.dict"
    with open(out, "w") as f:
        for t in toks:
            esc = t.replace("\\", "\\\\").replace('"', '\\"')
            f.write(f'"{esc}"\n')
    print(f"{out}: {len(toks)} tokens ({len(idents)} idents, "
          f"{len(KEYWORDS)} kw, {len(OPS)} ops)")


if __name__ == "__main__":
    main()
