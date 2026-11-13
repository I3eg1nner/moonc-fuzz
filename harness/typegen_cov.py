#!/usr/bin/env python3
"""类型导向语料的覆盖增量：对每个项目重放 moon 的真实命令。

用法：python3 typegen_cov.py /tmp/tg240 --limit 40 --out out/typegen_cov.json
"""
import glob, json, os, re, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import symbolize

MOON = os.path.expanduser("~/.moon/bin/moon")
MOONC = os.path.expanduser("~/.moon/bin/moonc")
QEMU = "/tmp/AFLplusplus/afl-qemu-trace"
PC = re.compile(rb"\[[0-9a-f]+/([0-9a-f]+)/")

def cmds_for(proj):
    """先拿 dry-run 的命令（此时还没 build），再真跑一次生成依赖。"""
    r = subprocess.run([MOON, "check", "--target", "wasm-gc", "--dry-run", "-v"],
                       cwd=proj, capture_output=True, timeout=120)
    out = (r.stdout + r.stderr).decode("utf-8", "replace")
    cmds = []
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("moonc "):
            argv = [a.replace("'", "").replace("$MOON_HOME", os.path.expanduser("~/.moon"))
                    for a in line.split()]
            argv[0] = MOONC
            cmds.append(argv)
    try:
        subprocess.run([MOON, "check", "--target", "wasm-gc"], cwd=proj,
                       capture_output=True, timeout=120)
    except Exception:
        pass
    return cmds

def run_cmds(proj, cmds, sym):
    funcs = set()
    for argv in cmds:
        wd = tempfile.mkdtemp(dir="/tmp")
        o = argv.index("-o") if "-o" in argv else -1
        if o >= 0:
            argv = list(argv)
            argv[o + 1] = os.path.join(wd, "o" + os.path.splitext(argv[o + 1])[1])
        log = os.path.join(wd, "e.log")
        try:
            with open(log, "wb") as lf:
                subprocess.run([QEMU, "-d", "exec", "-D", log, "--"] + argv,
                               cwd=proj, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=120)
        except Exception:
            pass
        try:
            for line in open(log, "rb"):
                m = PC.search(line)
                if m:
                    fn = sym.func_of(int(m.group(1), 16))
                    if fn:
                        funcs.add(fn)
        except FileNotFoundError:
            pass
    return {f for f in funcs if f.startswith("camlMoonc")}

def main():
    d = sys.argv[1]
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else 40
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else "out/typegen_cov.json"
    sym = symbolize.SymTab()
    projs = sorted(glob.glob(os.path.join(d, "p*")))[:limit]
    union, per = set(), []
    for p in projs:
        try:
            fs = run_cmds(p, cmds_for(p), sym)
        except Exception as e:
            fs = set()
        union |= fs
        per.append(len(fs))
    json.dump({"n": len(projs), "funcs": sorted(union), "moonc": len(union),
               "per_project": per}, open(out, "w"))
    print(f"[tgcov] projects={len(projs)} union Moonc={len(union)} "
          f"mean/proj={sum(per)/max(len(per),1):.0f}")

if __name__ == "__main__":
    main()
