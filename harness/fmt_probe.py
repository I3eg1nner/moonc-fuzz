#!/usr/bin/env python3
"""Printer/round-trip probe over one program per language construct.

For each .mbt in --dir (must syncheck):
  fmt -> out; require fmt rc=0, output re-parses, fmt is idempotent, and no
  structural delimiter is removed.  Scan formatted code for characters that
  the lexer rejects (~ U+007E) outside strings/comments, and for keyword loss
  (async/defer/impl/trait/derive/...), which indicate the printer dropped or
  rewrote a construct.

Usage:
  python3 harness/fmt_probe.py run --dir out/fmt_probe --out out/fmt_probe.jsonl
  python3 harness/fmt_probe.py report
"""
from __future__ import annotations
import argparse, json, os, re, sys
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
sys.path.insert(0,HERE); import syntax_boundary as sb

MOONC=os.path.expanduser("~/.moon/bin/moonc"); FMT=os.path.expanduser("~/.moon/bin/moonfmt")
TMP=os.path.join(ROOT,"out","fmt_probe_tmp")
KW=["async","await","defer","impl","trait","derive","suberror","raise","try","catch","is","guard","mut","priv","pub","test","bench"]
STR=re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*')

def code_only(s):
    return "\n".join(STR.sub("",l) for l in s.splitlines())

def counts(s):
    return {ch:s.count(ch) for ch in "()[]{}"}

def run(d, out):
    os.makedirs(TMP,exist_ok=True)
    o,e=os.path.join(TMP,"o"),os.path.join(TMP,"e")
    rows=[]
    for f in sorted(os.listdir(d)):
        if not f.endswith(".mbt"): continue
        src=open(os.path.join(d,f)).read()
        p=os.path.join(TMP,"c.mbt"); open(p,"w").write(src)
        r1=sb.run_measured([FMT,"c.mbt","-o","f1.mbt"],TMP,30,o,e)
        rec={"file":f,"fmt_rc":r1["rc"],"bytes":len(src)}
        if r1["rc"]==0 and os.path.exists(os.path.join(TMP,"f1.mbt")):
            s1=open(os.path.join(TMP,"f1.mbt")).read()
            r2=sb.run_measured([FMT,"f1.mbt","-o","f2.mbt"],TMP,30,o,e)
            rec["idempotent"]= r2["rc"]==0 and open(os.path.join(TMP,"f2.mbt"),"rb").read()==open(os.path.join(TMP,"f1.mbt"),"rb").read()
            rc=sb.run_measured([MOONC,"syncheck","f1.mbt"],TMP,20,o,e)
            st,sig=sb.classify(rc); rec["reparse"]=st; rec["sig"]=sig
            rec["tilde"]= ("~+" in code_only(s1)) or ("~-" in code_only(s1))
            rec["delims_removed"]={k:v for k,v in ((k,counts(src)[k]-counts(s1)[k]) for k in "()[]") if v>0}
            rec["kw_lost"]=[k for k in KW if k!="try" and src.count(k)>0 and s1.count(k)==0]
            rec["out_bytes"]=len(s1)
            if st!="ok_quiet" and st!="ok":
                rec["out"]=s1[:800]
        rows.append(rec)
    with open(out,"w") as fh:
        for r in rows: fh.write(json.dumps(r)+"\n")
    bad=[r for r in rows if r.get("reparse") not in ("ok","ok_quiet") or r.get("tilde") or r.get("kw_lost") or r.get("delims_removed") or r.get("fmt_rc")!=0]
    print("files",len(rows),"flagged",len(bad))
    for r in bad:
        print(" ",r["file"],"fmt",r.get("fmt_rc"),"reparse",r.get("reparse"),"tilde",r.get("tilde"),
              "kw_lost",r.get("kw_lost"),"delims",r.get("delims_removed"),"|",r.get("sig","")[:90])
    return 0

def report():
    p=os.path.join(ROOT,"out","fmt_probe.jsonl")
    rows=[json.loads(l) for l in open(p)]
    print("files",len(rows))
    print("fmt_fail",sum(1 for r in rows if r["fmt_rc"]!=0))
    print("reparse_fail",sum(1 for r in rows if r.get("reparse") not in ("ok","ok_quiet")))
    print("not_idempotent",sum(1 for r in rows if not r.get("idempotent")))
    print("tilde",sum(1 for r in rows if r.get("tilde")))
    print("kw_lost",sum(1 for r in rows if r.get("kw_lost")))
    print("delims_removed",sum(1 for r in rows if r.get("delims_removed")))
    return 0

if __name__=="__main__":
    ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest="cmd",required=True)
    r=sub.add_parser("run"); r.add_argument("--dir",default=os.path.join(ROOT,"out","fmt_probe")); r.add_argument("--out",default=os.path.join(ROOT,"out","fmt_probe.jsonl"))
    sub.add_parser("report"); a=ap.parse_args()
    sys.exit(run(a.dir,a.out) if a.cmd=="run" else report())
