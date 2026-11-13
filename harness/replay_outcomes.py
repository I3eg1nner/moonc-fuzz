#!/usr/bin/env python3
"""Record return code / stderr / duration for replayed moonc commands.

replay.py discards outcomes; this quantifies how many commands in a dry-run
log actually succeed, separately from coverage (failed commands contribute
fewer functions, so a union built over them is conservative, not inflated).

Usage:
  python3 harness/replay_outcomes.py /tmp/audit_cmds.log --cwd /tmp/corecopy \
      --out out/check_outcomes.json
"""
from __future__ import annotations
import argparse, json, os, shlex, subprocess, sys, time
from multiprocessing import Pool

MOONC = os.path.expanduser("~/.moon/bin/moonc")
CFG = {}

def w_init(cwd):
    CFG["cwd"] = cwd

def one(arg):
    i, argv = arg
    t0 = time.time()
    try:
        r = subprocess.run(argv, cwd=CFG["cwd"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=300)
        rc, err = r.returncode, r.stderr[:300].decode("utf-8", "replace")
        to = False
    except subprocess.TimeoutExpired:
        rc, err, to = None, "TIMEOUT", True
    except OSError as e:
        rc, err, to = None, str(e), False
    codes = sorted({p for p in ("E3001","E3002","E3003","E3004","E4037","E4032","E4080") if p in err})
    return {"i": i, "rc": rc, "timeout": to, "sec": round(time.time()-t0, 2),
            "err": err, "codes": codes, "pkg": (argv[argv.index("-pkg")+1] if "-pkg" in argv else "")}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log"); ap.add_argument("--cwd", default=".")
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    cmds = []
    for line in open(a.log, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line.startswith("moonc "):
            argv = shlex.split(line); argv[0] = MOONC; cmds.append(argv)
    with Pool(a.workers, initializer=w_init, initargs=(os.path.abspath(a.cwd),)) as p:
        res = p.map(one, list(enumerate(cmds)), chunksize=1)
    ok = [r for r in res if r["rc"] == 0]
    fail = [r for r in res if r["rc"] not in (0, None)]
    to = [r for r in res if r["timeout"]]
    print("commands=%d rc0=%d fail=%d timeout=%d" % (len(res), len(ok), len(fail), len(to)))
    from collections import Counter
    print("rc:", dict(Counter(r["rc"] for r in res)))
    print("fail examples:")
    for r in fail[:8]:
        print("  rc=%s pkg=%s %s" % (r["rc"], r["pkg"], r["err"].splitlines()[0][:120] if r["err"] else ""))
    json.dump({"n": len(res), "rc0": len(ok), "fail": len(fail), "timeout": len(to),
               "rows": res}, open(a.out, "w"), indent=1)
    print("->", a.out)

if __name__ == "__main__":
    main()
