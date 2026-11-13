#!/usr/bin/env python3
"""重放 moon 的真实命令（`moon <cmd> --dry-run -v` 的输出）并测覆盖。

为什么：手拼 `-i` 永远拼不对——别名是每个消费者自己在 moon.pkg 里声明的，
子包要写 `encoding/utf8`，trait 还要按全路径可见，白盒测试要 `-whitebox-test`。
`moon --dry-run -v` 给的是官方驱动算出来的 299 条命令，包含依赖闭包和白盒包。

用法：
  moon check --target wasm-gc --dry-run -v > /tmp/cmds.log
  python3 replay.py /tmp/cmds.log --cwd /tmp/corecopy --out out/cov_replay_check.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import tempfile
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import symbolize  # noqa: E402

MOONC = os.path.expanduser("~/.moon/bin/moonc")
AFL_QEMU = "/tmp/AFLplusplus/afl-qemu-trace"
PC_RE = re.compile(rb"\[[0-9a-f]+/([0-9a-f]+)/")
CFG = {}


def w_init(cwd):
    CFG["wd"] = tempfile.mkdtemp(prefix="rep_", dir="/tmp")
    CFG["sym"] = symbolize.SymTab()
    CFG["cwd"] = cwd


def one(arg):
    i, argv = arg
    wd = CFG["wd"]
    home = os.path.expanduser("~/.moon")
    argv = [a.replace("$MOON_HOME", home) for a in argv]
    argv = [os.path.expandvars(a) for a in argv]
    out_mi = os.path.join(wd, f"o{i}.mi")
    if "-o" in argv:
        orig = argv[argv.index("-o") + 1]
        out_mi = os.path.join(wd, f"o{i}" + (os.path.splitext(orig)[1] or ".out"))
        argv[argv.index("-o") + 1] = out_mi
    log = os.path.join(wd, f"e{i}.log")
    rc, err, timed_out, capped = None, "", False, False
    CAP = 128 * 1024 * 1024
    try:
        p = subprocess.Popen([AFL_QEMU, "-d", "exec", "-D", log, "--"] + argv,
                             cwd=CFG["cwd"], stdout=subprocess.DEVNULL,
                             stderr=subprocess.PIPE)
        t0 = time.time()
        while p.poll() is None:
            time.sleep(0.1)
            try:
                if os.path.getsize(log) > CAP:
                    p.kill(); capped = True; break
            except OSError:
                pass
            if time.time() - t0 > 180:
                p.kill(); timed_out = True; break
        rc = p.wait()
        err = (p.stderr.read()[:300].decode("utf-8", "replace") if p.stderr else "")
    except OSError as e:
        err = str(e)
    funcs, ntb = set(), 0
    sym = CFG["sym"]
    try:
        with open(log, "rb") as f:
            for line in f:
                if capped and f.tell() > CAP:
                    break
                m = PC_RE.search(line)
                if not m:
                    continue
                ntb += 1
                fn = sym.func_of(int(m.group(1), 16))
                if fn:
                    funcs.add(fn)
    except FileNotFoundError:
        pass
    finally:
        try:
            os.unlink(log)
        except OSError:
            pass
        try:
            os.unlink(out_mi)
        except OSError:
            pass
    pkg = ""
    if "-pkg" in argv:
        pkg = argv[argv.index("-pkg") + 1]
    return {"i": i, "pkg": pkg, "funcs": sorted(funcs), "tb": ntb,
            "rc": rc, "timed_out": timed_out, "capped": capped, "stderr": err,
            "whitebox": "-whitebox-test" in argv, "cmd": " ".join(argv[:6])}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--cwd", default=".")
    ap.add_argument("--workers", type=int, default=32)
    ap.add_argument("--out")
    ap.add_argument("--keep", action="store_true", help="保留输出 .mi（依赖后续命令时用）")
    a = ap.parse_args()
    cmds = []
    for line in open(a.log, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if not line.startswith("moonc "):
            continue
        argv = shlex.split(line)
        argv[0] = MOONC
        cmds.append(argv)
    print(f"[replay] {len(cmds)} commands from {a.log}", flush=True)
    with Pool(a.workers, initializer=w_init, initargs=(os.path.abspath(a.cwd),)) as p:
        res = p.map(one, list(enumerate(cmds)), chunksize=1)
    union = set()
    for r in res:
        union |= set(r["funcs"])
    moonc = {f for f in union if f.startswith("camlMoonc")}
    wb = [r for r in res if r["whitebox"]]
    wb_union = set().union(*[set(r["funcs"]) for r in wb]) if wb else set()
    out = dict(tool="replay-moon-dryrun", log=a.log, n=len(cmds),
               funcs=sorted(union), func_count=len(union),
               moonc_count=len(moonc),
               whitebox_cmds=len(wb),
               whitebox_funcs=len({f for f in wb_union if f.startswith("camlMoonc")}),
               tb_total=sum(r["tb"] for r in res),
               rc0=sum(1 for r in res if r["rc"] == 0),
               failed=sum(1 for r in res if r["rc"] not in (0, None)),
               timed_out=sum(1 for r in res if r["timed_out"]),
               capped=sum(1 for r in res if r.get("capped")),
               per_cmd=[{k: r[k] for k in ("pkg", "tb", "whitebox", "rc")} for r in res])
    if a.out:
        json.dump(out, open(a.out, "w"))
    print(f"[replay] union funcs={len(union)} Moonc={len(moonc)} "
          f"whitebox_cmds={len(wb)} whitebox_Moonc={out['whitebox_funcs']} "
          f"TB={out['tb_total']}")


if __name__ == "__main__":
    main()
