#!/usr/bin/env python3
"""差分 oracle 的回归用例（codex review 指出的吞值问题）。"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import difftpl as D

CASES = [
    (b"9007199254740992", b"9007199254740993", False),
    (b"A", b"a", False),
    (b"1", b"1.0", True),
    (b"-0", b"0", True),
    (b"NaN", b"nan", True),
    (b"1e3", b"1000", True),
    (b"-0.0", b"0", True),
    (b"1.5", b"1.50", True),
    (b"[1,2]", b"[1, 2]", False),      # 空格差异是真实输出差异，不归一
]

def main():
    bad = 0
    for a, b, want in CASES:
        got = D.normalize(a) == D.normalize(b)
        if got != want:
            bad += 1
            print(f"FAIL {a!r} vs {b!r}: got {got}, want {want}")
    print(f"{len(CASES)-bad}/{len(CASES)} passed")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
