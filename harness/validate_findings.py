#!/usr/bin/env python3
"""Reproduce F1-F5 and P1 five times, with resource caps where needed.

Each finding gets a canonical command, five runs, and a compact table:
rc, wall time, peak RSS (child rusage), and the discriminating signature.
F3 is capped at 6 GiB / 15 s so a reproduction cannot take the host down;
P1 is measured at k=1024 and k=2048 with a plain-string control.

Usage: python3 harness/validate_findings.py --out out/validation.json
"""
from __future__ import annotations
import argparse, json, os, shutil, sys, statistics, tempfile
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
sys.path.insert(0,HERE); import syntax_boundary as sb
MOONC=os.path.expanduser("~/.moon/bin/moonc"); FMT=os.path.expanduser("~/.moon/bin/moonfmt")
MOON=os.path.expanduser("~/.moon/bin/moon")
POC=os.path.join(ROOT,"poc"); TMP=os.path.join(ROOT,"out","validation_tmp")

def run(argv, cwd, timeout=15, mem=6):
    os.makedirs(TMP,exist_ok=True)
    return sb.run_measured(argv,cwd,timeout,os.path.join(TMP,"o"),os.path.join(TMP,"e"),mem_gb=mem)

def clean_build(d):
    shutil.rmtree(os.path.join(d,"_build"),ignore_errors=True)

def main(out):
    rows=[]
    def add(name,cmd,kind,**kw):
        rs=[]
        for i in range(5):
            d=kw.get("cwd")
            if kw.get("clean"): clean_build(d)
            r=run(cmd,d,kw.get("timeout",15),kw.get("mem",6))
            st,sig=sb.classify(r)
            rs.append({"rc":r["rc"],"ms":r["ms"],"rss_kb":r["rss_kb"],"status":st,"sig":sig,
                       "stderr":r["stderr"][:200]})
        rows.append({"finding":name,"kind":kind,"runs":rs})
        print(f"{name:4} {kind:16} rcs={[x['rc'] for x in rs]} rss={[x['rss_kb'] for x in rs]}")

    d1=os.path.join(POC,"f1_moon_pkg_segv")
    add("F1",[MOONC,"syncheck","moon.pkg"],"SIGSEGV",cwd=d1)
    d2=os.path.join(POC,"f2_lex_escape_ice")
    add("F2",[MOON,"check"],"ICE",cwd=d2,clean=True)
    d3=os.path.join(POC,"f3_parser_oom")
    add("F3",[MOONC,"syncheck","cmd/main.mbt"],"OOM",cwd=d3,timeout=15,mem=6)
    d4=os.path.join(POC,"f4_invalid_utf8")
    add("F4",[MOONC,"syncheck","doc.mbt.md"],"ICE",cwd=d4)
    d5=os.path.join(POC,"f5_prefix_plus")
    add("F5-syn",[MOONC,"syncheck","u.mbt"],"parses",cwd=d5)
    add("F5-check",[MOONC,"check","-no-mi","-pkg","f5/p","-i",
                     os.path.expanduser("~/.moon/lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi"),
                     "u.mbt"],"rejects",cwd=d5)
    rs=[]
    for i in range(5):
        fr=run([FMT,"u.mbt","-o","u1.mbt"],d5,30)
        rr=run([MOONC,"syncheck","u1.mbt"],d5,30)
        st,sig=sb.classify(rr)
        rs.append({"rc":rr["rc"],"ms":rr["ms"],"rss_kb":rr["rss_kb"],"status":st,"sig":sig,
                   "stderr":rr["stderr"][:200],"fmt_rc":fr["rc"],
                   "fmt_has_tilde_plus":"~+" in ""})
        # record whether formatted output contains the internal token
        if os.path.exists(os.path.join(d5,"u1.mbt")):
            rs[-1]["fmt_has_tilde_plus"]="~+" in open(os.path.join(d5,"u1.mbt")).read()
    rows.append({"finding":"F5-fmt-reparse","kind":"unparseable","runs":rs})
    print("F5-fmt-reparse rcs=",[x["rc"] for x in rs],"tilde+",[x["fmt_has_tilde_plus"] for x in rs])
    # P1: interpolation vs plain string, k=1024/2048
    for k in (1024,2048):
        for fam,mk in (("interp",lambda k: '"%s"'%("".join("\\{%d}"%i for i in range(k)))),
                       ("plain",lambda k: '"%s"'%("a"*k))):
            d=os.path.join(TMP,f"p1_{fam}_{k}"); os.makedirs(d,exist_ok=True)
            open(os.path.join(d,"p.mbt"),"w").write("fn f() -> String { %s }\n"%mk(k))
            rs=[]
            for i in range(5):
                r=run([FMT,"p.mbt","-o","o.mbt"],d,60)
                rs.append({"ms":r["ms"],"rss_kb":r["rss_kb"],"rc":r["rc"]})
            rows.append({"finding":f"P1-{fam}-{k}","kind":"fmt_time","runs":rs})
            print(f"P1 {fam:6} k={k:<5} median={statistics.median(x['ms'] for x in rs):8.1f}ms rc={[x['rc'] for x in rs]}")
    json.dump(rows,open(out,"w"),indent=1); print("->",out)

if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("--out",default=os.path.join(ROOT,"out","validation.json")); a=ap.parse_args(); main(a.out)
