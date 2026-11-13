"""把 moonc 里的 PC 映射回函数名（闭源二进制，靠 nm 符号表）。

moonc 是 non-PIE（ELF type EXEC），所以符号地址就是运行时地址；
但 qemu-user 的 trace 里 PC 可能带 0x4000_0000_0000 的 guest base，
这里两种形态都处理。
"""
from __future__ import annotations

import bisect
import os
import subprocess

MOONC = os.path.expanduser("~/.moon/bin/moonc")
GUEST_BASE = 0x4000_0000_0000


class SymTab:
    def __init__(self, binary=MOONC):
        out = subprocess.run(["nm", "-n", binary], capture_output=True, text=True).stdout
        syms = []
        for line in out.splitlines():
            p = line.split()
            if len(p) == 3 and p[1] in ("T", "t", "W", "w"):
                try:
                    syms.append((int(p[0], 16), p[2]))
                except ValueError:
                    pass
        syms.sort()
        self.syms = syms
        self.addrs = [a for a, _ in syms]
        self.text_lo = syms[0][0]
        self.text_hi = syms[-1][0]

    def to_addr(self, pc: int):
        """moonc 是 ET_EXEC（非 PIE），运行时地址 == 符号地址。

        注意：qemu-user 的 trace 里还存在 0x4000_0000_0000 以上的动态库/loader
        区间；如果机械地减去 GUEST_BASE，部分地址会"恰好"落进 moonc 的 .text
        并查到假符号（工程调研中实际踩到过）。因此这里只接受 moonc 自己的
        地址区间，其余一律视为外部代码。
        """
        if self.text_lo <= pc <= self.text_hi:
            return pc
        return None

    def func_of(self, pc: int):
        a = self.to_addr(pc)
        if a is None:
            return None
        i = bisect.bisect_right(self.addrs, a) - 1
        if i < 0:
            return None
        return self.syms[i][1]

    def func_range(self, name: str):
        for i, (a, n) in enumerate(self.syms):
            if n == name:
                end = self.syms[i + 1][0] if i + 1 < len(self.syms) else a + 0x1000
                return a, end
        return None


def short(name: str) -> str:
    """camlMoonc__Lex_literal__foo_123 -> Moonc.Lex_literal.foo"""
    if name.startswith("caml"):
        name = name[4:]
    if name.startswith("Moonc__"):
        name = name[len("Moonc__"):]
    if name.startswith("Stdlib__"):
        return "Stdlib." + name[len("Stdlib__"):]
    return name
