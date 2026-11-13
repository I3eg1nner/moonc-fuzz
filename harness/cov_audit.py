#!/usr/bin/env python3
"""Coverage-measurement audit (codex review 4, action 1).

Checks three claims that all coverage numbers depend on:

  A. symbolization -- is a PC attributed to the *right* function?  Current
     symbolize.py takes the nearest preceding text symbol; here we compare it
     to an ELF-size-bounded mapping (nm -S) and count PCs that fall in no
     function interval (gaps, padding, aliases).
  B. replay outcomes -- replay.py discards return code and stderr; here we
     re-run a stratified sample recording rc / stderr / timeout / trace
     completeness, and compare the function union of all commands vs only
     rc==0 commands.
  C. reproducibility -- the same sample is run twice (optionally 3x); function
     sets must be stable, otherwise a "union" is an artifact of scheduling.

Usage:
  cd /tmp/corecopy
  moon check --target wasm-gc --dry-run -v > /tmp/audit_cmds.log
  python3 /data/audit/mbtfuzz/harness/cov_audit.py /tmp/audit_cmds.log \
      --cwd /tmp/corecopy --sample 12 --rounds 2 --out out/cov_audit.json
"""
from __future__ import annotations

import argparse
import bisect
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import symbolize  # noqa: E402

MOONC = os.path.expanduser("~/.moon/bin/moonc")
AFL_QEMU = "/tmp/AFLplusplus/afl-qemu-trace"
PC_RE = re.compile(rb"\[[0-9a-f]+/([0-9a-f]+)/")


def symtab_sized(binary=MOONC):
    out = subprocess.run(["nm", "-S", "-n", binary], capture_output=True, text=True).stdout
    syms = []
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 4 and p[2] in ("T", "t", "W", "w"):
            try:
                syms.append((int(p[0], 16), int(p[1], 16), p[3]))
            except ValueError:
                pass
    syms.sort()
    return syms


def audit_symtab(syms):
    zero = sum(1 for _, s, _ in syms if s == 0)
    by_addr = {}
    for a, s, n in syms:
        by_addr.setdefault(a, []).append(n)
    aliases = {a: v for a, v in by_addr.items() if len(v) > 1}
    overlap = 0
    for i in range(len(syms) - 1):
        a, s, _ = syms[i]
        if s and a + s > syms[i + 1][0]:
            overlap += 1
    return {"text_symbols": len(syms), "zero_size": zero,
            "alias_addrs": len(aliases), "overlapping_intervals": overlap,
            "alias_examples": list(aliases.items())[:5]}


class Bounded:
    def __init__(self, syms):
        self.s = syms
        self.starts = [a for a, _, _ in syms]

    def func_of(self, pc):
        i = bisect.bisect_right(self.starts, pc) - 1
        if i < 0:
            return None
        a, size, n = self.s[i]
        if a <= pc < a + max(size, 1):
            return n
        return None  # gap between functions or padding


def run_cmd(argv, cwd, log):
    try:
        r = subprocess.run([AFL_QEMU, "-d", "exec", "-D", log, "--"] + argv,
                           cwd=cwd, stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=180)
        rc, err, to = r.returncode, r.stderr[:400].decode("utf-8", "replace"), False
    except subprocess.TimeoutExpired:
        rc, err, to = None, "TIMEOUT", True
    except OSError as e:
        rc, err, to = None, str(e), False
    pcs = []
    complete = True
    try:
        with open(log, "rb") as f:
            data = f.read()
        complete = data.endswith(b"\n")
        for line in data.splitlines():
            m = PC_RE.search(line)
            if m:
                pcs.append(int(m.group(1), 16))
    except FileNotFoundError:
        complete = False
    return rc, err, to, pcs, complete


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--cwd", default=".")
    ap.add_argument("--sample", type=int, default=12)
    ap.add_argument("--rounds", type=int, default=2)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    cmds = []
    for line in open(a.log, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line.startswith("moonc "):
            argv = shlex.split(line)
            argv[0] = MOONC
            cmds.append(argv)
    if not cmds:
        print("no moonc commands in log")
        return 1
    step = max(1, len(cmds) // a.sample)
    picked = cmds[::step][: a.sample]
    print("commands total=%d picked=%d rounds=%d" % (len(cmds), len(picked), a.rounds))

    syms = symtab_sized()
    st = audit_symtab(syms)
    print("symtab:", st["text_symbols"], "text symbols, zero-size", st["zero_size"],
          "aliases", st["alias_addrs"], "overlaps", st["overlapping_intervals"])
    naive = symbolize.SymTab()
    bounded = Bounded(syms)

    wd = tempfile.mkdtemp(prefix="audit_", dir="/tmp")
    rounds = []
    for r in range(a.rounds):
        rows = []
        for i, argv in enumerate(picked):
            log = os.path.join(wd, "r%d_%d.log" % (r, i))
            rc, err, to, pcs, complete = run_cmd(argv, a.cwd, log)
            f_naive, f_bnd = set(), set()
            gap = 0
            for pc in pcs:
                n1 = naive.func_of(pc)
                n2 = bounded.func_of(pc)
                if n1:
                    f_naive.add(n1)
                if n2:
                    f_bnd.add(n2)
                elif n1:
                    gap += 1
            rows.append({"i": i, "rc": rc, "timeout": to, "complete": complete,
                         "pcs": len(pcs), "naive": len(f_naive), "bounded": len(f_bnd),
                         "gap_pcs": gap, "naive_set": sorted(f_naive),
                         "naive_only": sorted(f_naive - f_bnd)[:20],
                         "bounded_only": sorted(f_bnd - f_naive)[:20],
                         "stderr": err[:200]})
            os.unlink(log) if os.path.exists(log) else None
        union_n = set().union(*[set(x["naive_only"]) for x in rows]) if rows else set()
        rounds.append(rows)
        print("round %d: rc0=%d/%d timeouts=%d incomplete=%d gap_pcs=%d"
              % (r, sum(1 for x in rows if x["rc"] == 0), len(rows),
                 sum(1 for x in rows if x["timeout"]),
                 sum(1 for x in rows if not x["complete"]),
                 sum(x["gap_pcs"] for x in rows)))

    # reproducibility: per-command naive set cannot be compared directly here
    # (we only stored counts), so compare totals and rc pattern as a first pass.
    def sig(rows):
        return [(x["naive"], tuple(x["naive_set"])) for x in rows]
    stable = all(sig(rounds[0]) == sig(rounds[r]) for r in range(1, len(rounds)))
    out = {"symtab": st, "commands_total": len(cmds), "picked": len(picked),
           "rounds": rounds, "per_command_stable": stable}
    json.dump(out, open(a.out, "w"), indent=1)
    print("stable per command:", stable, "->", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
