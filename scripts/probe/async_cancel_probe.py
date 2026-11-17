#!/usr/bin/env python3
"""Serial probe of moonbit core/async cancellation, timeout and combinator state machines."""
import json, os, re, shutil, subprocess, sys, time

ROOT = "/tmp/ac_probe/matrix"
OUT = "/tmp/ac_probe/results.jsonl"
MOON = "moon"
STAGES = ["check", "build", "test-build", "test"]

W = '#warnings("-fragile_catch_all")\n'

CASES = []
def add(cid, family, src, aio=False, targets=("native", "js", "wasm"), note=""):
    CASES.append(dict(id=cid, family=family, src=src, aio=aio, targets=list(targets), note=note))

# ---------------- Family 1: with_timeout bodies ----------------
add("tw_01_immediate", "F1_with_timeout", '''
async test "tw immediate" {
  let x = @async.with_timeout(500, () => 7)
  assert_eq(x, 7)
}
''')
add("tw_02_pause_once", "F1_with_timeout", '''
async test "tw pause once" {
  let x = @async.with_timeout(500, () => {
    @async.pause()
    8
  })
  assert_eq(x, 8)
}
''')
add("tw_03_pause_loop", "F1_with_timeout", '''
async test "tw pause loop" {
  let x = @async.with_timeout(500, () => {
    let mut i = 0
    while i < 3 {
      @async.pause()
      i = i + 1
    }
    i
  })
  assert_eq(x, 3)
}
''')
add("tw_04_sleep_short", "F1_with_timeout", '''
async test "tw sleep short" {
  let x = @async.with_timeout(500, () => {
    @async.sleep(20)
    9
  })
  assert_eq(x, 9)
}
''')
add("tw_05_throw_before", "F1_with_timeout", W + '''
async test "tw throw before timeout" {
  let caught = try {
    let _ = @async.with_timeout(500, () => { raise Failure::Failure("boom") })
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("tw_06_throw_after_pause", "F1_with_timeout", W + '''
async test "tw throw after pause" {
  let caught = try {
    let _ = @async.with_timeout(500, () => {
      @async.pause()
      raise Failure::Failure("boom")
    })
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("tw_07_expire_sleep", "F1_with_timeout", W + '''
async test "tw expire" {
  let caught = try {
    let _ = @async.with_timeout(50, () => { @async.sleep(500); 1 })
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("tw_08_expire_loop", "F1_with_timeout", W + '''
async test "tw expire in pause loop" {
  let caught = try {
    let _ = @async.with_timeout(50, () => {
      let mut i = 0
      while i < 100 {
        @async.pause()
        @async.sleep(5)
        i = i + 1
      }
      i
    })
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("tw_09_defer_on_timeout", "F1_with_timeout", '''
async test "tw defer runs on timeout" {
  let log = []
  let r : Int? = @async.with_timeout_opt(50, () => {
    defer log.push("defer")
    @async.sleep(500)
    1
  })
  assert_true(r is None)
  assert_eq(log, ["defer"])
}
''')
add("tw_10_custom_error", "F1_with_timeout", W + '''
async test "tw custom error" {
  let caught = try {
    let _ = @async.with_timeout(50, () => { @async.sleep(500); 1 }, error=Failure::Failure("custom"))
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("tw_11_raise_q_inside", "F1_with_timeout", '''
pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}

async test "tw around raise? callback" {
  let r : Int? = @async.with_timeout(500, () => pick(x => if x == 1 { Some(x) } else { None }))
  assert_eq(r, Some(1))
}
''', aio=True, note="F8 shape as control (known signature expected)")
add("tw_12_raise_q_bare", "F1_with_timeout", '''
pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}

async test "bare raise? callback" {
  let r : Int? = pick(x => if x == 1 { Some(x) } else { None })
  assert_eq(r, Some(1))
}
''', aio=True, note="F8 minimal control (known signature expected)")

# ---------------- Family 2: with_timeout_opt ----------------
add("to_01_immediate_some", "F2_with_timeout_opt", '''
async test "opt immediate" {
  let r : Int? = @async.with_timeout_opt(500, () => 7)
  assert_eq(r, Some(7))
}
''')
add("to_02_pause_some", "F2_with_timeout_opt", '''
async test "opt pause" {
  let r : Int? = @async.with_timeout_opt(500, () => { @async.pause(); 7 })
  assert_eq(r, Some(7))
}
''')
add("to_03_expire_none", "F2_with_timeout_opt", '''
async test "opt expire" {
  let r : Int? = @async.with_timeout_opt(50, () => { @async.sleep(500); 7 })
  assert_true(r is None)
}
''')
add("to_04_loop_none", "F2_with_timeout_opt", '''
async test "opt loop expire" {
  let r : Int? = @async.with_timeout_opt(50, () => {
    let mut i = 0
    while i < 50 {
      @async.pause()
      @async.sleep(5)
      i = i + 1
    }
    i
  })
  assert_true(r is None)
}
''')
add("to_05_throw", "F2_with_timeout_opt", W + '''
async test "opt body raises" {
  let caught = try {
    let _ = @async.with_timeout_opt(500, () => { @async.pause(); raise Failure::Failure("x") })
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("to_06_protected_cleanup", "F2_with_timeout_opt", '''
async test "opt protected cleanup returns Some" {
  let r : Int? = @async.with_timeout_opt(50, () => {
    @async.protect_from_cancel(() => { @async.sleep(200); 1 })
  })
  assert_eq(r, Some(1))
}
''')
add("to_07_nested_inner", "F2_with_timeout_opt", '''
async test "opt nested inner timeout" {
  let r : Int?? = @async.with_timeout_opt(500, () => @async.with_timeout_opt(50, () => { @async.sleep(500); 1 }))
  assert_true(r is Some(None))
}
''')

# ---------------- Family 3: all / any ----------------
add("al_01_single", "F3_all_any", '''
async test "all single" {
  let xs = @async.all([() => 1])
  assert_eq(xs[0], 1)
}
''')
add("al_02_two_mixed", "F3_all_any", '''
async test "all two mixed" {
  let xs = @async.all([() => 1, () => { @async.pause(); 2 }])
  assert_eq(xs, [1, 2])
}
''')
add("al_03_five_mixed", "F3_all_any", '''
async test "all five mixed" {
  let xs = @async.all([
    () => 1,
    () => { @async.pause(); 2 },
    () => 3,
    () => { @async.sleep(10); 4 },
    () => { @async.pause(); @async.pause(); 5 },
  ])
  assert_eq(xs, [1, 2, 3, 4, 5])
}
''')
add("al_04_five_pause", "F3_all_any", '''
async test "all five pause" {
  let xs = @async.all([
    () => { @async.pause(); 1 },
    () => { @async.pause(); 2 },
    () => { @async.pause(); 3 },
    () => { @async.pause(); 4 },
    () => { @async.pause(); 5 },
  ])
  assert_eq(xs, [1, 2, 3, 4, 5])
}
''')
add("al_05_raise", "F3_all_any", W + '''
async test "all one raises" {
  let caught = try {
    let _ = @async.all([
      () => { @async.sleep(10); 1 },
      () => { @async.pause(); raise Failure::Failure("x") },
    ])
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("al_06_cancel_sibling", "F3_all_any", W + '''
async test "all cancels sibling on failure" {
  let log = []
  let caught = try {
    let _ = @async.all([
      () => { @async.sleep(50); raise Failure::Failure("x") },
      () => {
        match @async.handle_cancellation(() => @async.sleep(1000)) {
          None => log.push("cancelled")
          Some(_) => log.push("done")
        }
        2
      },
    ])
    false
  } catch {
    _ => true
  }
  assert_true(caught)
  assert_eq(log, ["cancelled"])
}
''')
add("an_01_single", "F3_all_any", '''
async test "any single" {
  let x = @async.any([() => 4])
  assert_eq(x, 4)
}
''')
add("an_02_two_mixed", "F3_all_any", '''
async test "any two mixed" {
  let x = @async.any([() => 1, () => { @async.pause(); 2 }])
  assert_true(x == 1 || x == 2)
}
''')
add("an_03_five_mixed", "F3_all_any", '''
async test "any five mixed" {
  let x = @async.any([
    () => { @async.pause(); 1 },
    () => 2,
    () => { @async.sleep(10); 3 },
    () => { @async.pause(); 4 },
    () => { @async.sleep(20); 5 },
  ])
  assert_true(x >= 1 && x <= 5)
}
''')
add("an_04_fail_default", "F3_all_any", W + '''
async test "any failure default" {
  let caught = try {
    let _ = @async.any([() => { @async.pause(); raise Failure::Failure("x") }, () => { @async.sleep(500); 2 }])
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("an_05_allow_failure", "F3_all_any", '''
async test "any allow failure" {
  let x = @async.any([
    () => { @async.pause(); raise Failure::Failure("x") },
    () => { @async.pause(); 5 },
  ], allow_failure=true)
  assert_eq(x, 5)
}
''')

# ---------------- Family 4: cancellation ----------------
add("cx_01_cancel_during_sleep", "F4_cancel", W + '''
async test "cancel during sleep" {
  @async.with_task_group(root => {
    let t = root.spawn(() => { @async.sleep(1000); 1 })
    @async.sleep(50)
    t.cancel()
    let cancelled = try {
      let _ = t.wait()
      false
    } catch {
      _ => true
    }
    assert_true(cancelled)
  })
}
''')
add("cx_02_cancel_handle", "F4_cancel", '''
async test "cancel with handle_cancellation" {
  let log = []
  @async.with_task_group(root => {
    let t = root.spawn(() => {
      match @async.handle_cancellation(() => @async.sleep(1000)) {
        None => log.push("cancelled")
        Some(_) => log.push("done")
      }
      0
    })
    @async.sleep(50)
    t.cancel()
    let _ = t.wait()
  })
  assert_eq(log, ["cancelled"])
}
''')
add("cx_03_cancel_before_yield", "F4_cancel", W + '''
async test "cancel before first suspend" {
  @async.with_task_group(root => {
    let t = root.spawn(() => { @async.pause(); 1 })
    t.cancel()
    let cancelled = try {
      let _ = t.wait()
      false
    } catch {
      _ => true
    }
    assert_true(cancelled)
  })
}
''')
add("cx_04_cancel_after_done", "F4_cancel", '''
async test "cancel after completion" {
  @async.with_task_group(root => {
    let t = root.spawn(() => 1)
    assert_eq(t.wait(), 1)
    t.cancel()
    assert_eq(t.try_wait(), Some(1))
  })
}
''')
add("cx_05_cancel_twice", "F4_cancel", W + '''
async test "cancel twice" {
  @async.with_task_group(root => {
    let t = root.spawn(() => { @async.sleep(1000); 1 })
    @async.sleep(20)
    t.cancel()
    t.cancel()
    let cancelled = try {
      let _ = t.wait()
      false
    } catch {
      _ => true
    }
    assert_true(cancelled)
  })
}
''')
add("cx_06_group_error_cancels", "F4_cancel", W + '''
async test "child error cancels sibling" {
  let log = []
  let caught = try {
    @async.with_task_group(root => {
      root.spawn_bg(() => { @async.sleep(50); raise Failure::Failure("x") })
      root.spawn_bg(() => {
        match @async.handle_cancellation(() => @async.sleep(1000)) {
          None => log.push("cancelled")
          Some(_) => log.push("done")
        }
      })
    })
    false
  } catch {
    _ => true
  }
  assert_true(caught)
  assert_eq(log, ["cancelled"])
}
''')
add("cx_07_timeout_protect", "F4_cancel", '''
async test "timeout vs protect_from_cancel" {
  let log = []
  let caught = try {
    let _ = @async.with_timeout(50, () => {
      @async.protect_from_cancel(() => { @async.sleep(200); log.push("protected") })
      @async.sleep(500)
    })
    false
  } catch {
    _ => true
  }
  assert_true(caught)
  assert_eq(log, ["protected"])
}
''')
add("cx_08_cancel_suspended_all", "F4_cancel", '''
async test "with_timeout cancels all" {
  let log = []
  let r : Array[Int]? = @async.with_timeout_opt(50, () => {
    @async.all([
      () => { match @async.handle_cancellation(() => @async.sleep(1000)) { None => log.push("a"); Some(_) => () }; 1 },
      () => { match @async.handle_cancellation(() => @async.sleep(1000)) { None => log.push("b"); Some(_) => () }; 2 },
    ])
  })
  assert_true(r is None)
  assert_eq(log, ["a", "b"])
}
''')
add("cx_09_cancel_nested_group", "F4_cancel", '''
async test "nested group cancel" {
  let log = []
  @async.with_task_group(root => {
    let t = root.spawn(() => {
      @async.with_task_group(inner => {
        inner.spawn_bg(() => {
          match @async.handle_cancellation(() => @async.sleep(1000)) {
            None => log.push("inner-cancelled")
            Some(_) => log.push("inner-done")
          }
        })
        @async.sleep(1000)
      })
    })
    @async.sleep(50)
    t.cancel()
    let _ = try { t.wait() } catch { _ => () }
  })
  assert_eq(log, ["inner-cancelled"])
}
''')

# ---------------- Family 5: nested combinations ----------------
add("nx_01_tw_all", "F5_nested", '''
async test "timeout around all" {
  let xs = @async.with_timeout(500, () => @async.all([() => 1, () => { @async.pause(); 2 }]))
  assert_eq(xs, [1, 2])
}
''')
add("nx_02_all_tw", "F5_nested", '''
async test "all of timeouts" {
  let xs = @async.all([
    () => @async.with_timeout(500, () => 1),
    () => @async.with_timeout(500, () => { @async.pause(); 2 }),
  ])
  assert_eq(xs, [1, 2])
}
''')
add("nx_03_any_raises", "F5_nested", '''
async test "any with raising branch" {
  let x = @async.any([
    () => { @async.pause(); raise Failure::Failure("x") },
    () => { @async.pause(); 5 },
  ], allow_failure=true)
  assert_eq(x, 5)
}
''')
add("nx_04_tw_any", "F5_nested", '''
async test "timeout around any" {
  let x = @async.with_timeout(500, () => @async.any([() => 1, () => { @async.pause(); 2 }]))
  assert_true(x == 1 || x == 2)
}
''')
add("nx_05_any_tw", "F5_nested", '''
async test "any of timeouts" {
  let x = @async.any([
    () => @async.with_timeout(500, () => 1),
    () => @async.with_timeout(500, () => { @async.pause(); 2 }),
  ])
  assert_true(x == 1 || x == 2)
}
''')
add("nx_06_outer_shorter", "F5_nested", W + '''
async test "outer timeout shorter" {
  let caught = try {
    let _ = @async.with_timeout(50, () => @async.with_timeout(500, () => { @async.sleep(500); 1 }))
    false
  } catch {
    _ => true
  }
  assert_true(caught)
}
''')
add("nx_07_inner_shorter", "F5_nested", '''
async test "inner timeout shorter" {
  let r : Int?? = @async.with_timeout_opt(500, () => {
    let inner : Int? = @async.with_timeout_opt(50, () => { @async.sleep(500); 1 })
    inner
  })
  assert_true(r is Some(None))
}
''')
add("nx_08_all_in_any", "F5_nested", '''
async test "all inside any" {
  let x = @async.any([
    () => @async.all([() => 1, () => { @async.pause(); 2 }])[0],
    () => { @async.pause(); 9 },
  ])
  assert_true(x == 1 || x == 9)
}
''')

# ---------------- Family 6: controls ----------------
add("ct_01_bare_pause_loop", "F6_control", '''
async test "control bare pause loop" {
  let mut i = 0
  while i < 3 { @async.pause(); i = i + 1 }
  assert_eq(i, 3)
}
''')
add("ct_02_bare_all", "F6_control", '''
async test "control bare all" {
  let xs = @async.all([() => 1, () => 2, () => 3])
  assert_eq(xs, [1, 2, 3])
}
''')
add("ct_03_bare_any", "F6_control", '''
async test "control bare any" {
  let x = @async.any([() => 1, () => 2])
  assert_true(x == 1 || x == 2)
}
''')
add("ct_04_bare_task_cancel", "F6_control", W + '''
async test "control bare task cancel" {
  @async.with_task_group(root => {
    let t = root.spawn(() => { @async.sleep(500); 1 })
    @async.sleep(20)
    t.cancel()
    let cancelled = try { let _ = t.wait(); false } catch { _ => true }
    assert_true(cancelled)
  })
}
''')
add("ct_05_sync", "F6_control", '''
test "control synchronous" {
  let xs = [1, 2, 3].map(x => x + 1)
  assert_eq(xs, [2, 3, 4])
}
''')
add("ct_07_bare_wait", "F6_control", '''
async test "control task wait without cancel" {
  @async.with_task_group(root => {
    let t = root.spawn(() => { @async.sleep(20); 3 })
    assert_eq(t.wait(), 3)
  })
}
''')
add("ct_08_bare_sleep", "F6_control", '''
async test "control bare sleep" {
  @async.sleep(20)
  assert_eq(1, 1)
}
''')
add("ct_06_sync_throw", "F6_control", W + '''
test "control synchronous throw" {
  let caught = try { raise Failure::Failure("x"); false } catch { _ => true }
  assert_true(caught)
}
''')


def norm(text, rc=None):
    t = text
    m = re.search(r'File "moonc\.ml", line (\d+)', t)
    if m:
        return "moonc.ml:%s assertion" % m.group(1)
    if "lower_array_make" in t:
        return "lower_array_make (F7)"
    if "finish_stub_wrapper_shell" in t:
        return "finish_stub_wrapper_shell (F9)"
    m = re.search(r'Machine_error\(kind=([^;]+);\s*who=([^;]+);\s*message=([^)]*)\)', t)
    if m:
        return "Machine_error(kind=%s; who=%s; message=%s)" % (
            m.group(1).strip(), m.group(2).strip(), m.group(3).strip()[:120])
    if "Segmentation fault" in t:
        return "SIGSEGV"
    if "Aborted" in t or "core dumped" in t:
        return "SIGABRT"
    m = re.search(r'Error: \[(\d+)\]', t)
    if m:
        return "diag:[%s]" % m.group(1)
    m = re.search(r'error: \[(\d+)\]', t)
    if m:
        return "diag:[%s]" % m.group(1)
    m = re.search(r'Error: ([^\n]+)', t)
    if m:
        line = m.group(1).strip()
        line = re.sub(r'/tmp/ac_probe/matrix/[^/ ]+', '<case>', line)
        return "Error: " + line[:160]
    if "the compiler has encountered an unexpected situation" in t:
        return "ICE banner (unparsed)"
    m = re.search(r'failed: ([^\n]+)', t)
    if m:
        return "test-fail: " + re.sub(r'0x[0-9a-f]+', '0x?', m.group(1))[:160]
    if rc == 0:
        return "ok"
    return "rc-fail (no Error line)"


def is_crash(text):
    return bool(
        re.search(r'File "moonc\.ml"', text)
        or "Machine_error" in text
        or "lower_array_make" in text
        or "finish_stub_wrapper_shell" in text
        or "the compiler has encountered an unexpected situation" in text
        or "Segmentation fault" in text
        or "Aborted (core dumped)" in text
        or "Fatal error: exception" in text
        or "Stack overflow" in text
    )


def run(cid, family, src, aio, targets, note):
    d = os.path.join(ROOT, cid)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    dep = 'import {\n  "moonbitlang/async@0.22.9",\n}\n' if aio else ""
    open(os.path.join(d, "moon.mod"), "w").write(
        'name = "probe/%s"\nversion = "0.0.1"\n%s' % (cid, dep))
    pkg = 'import {\n  "moonbitlang/core/async" @async,\n'
    if aio:
        pkg += '  "moonbitlang/async" @aio,\n'
    pkg += '}\noptions("allow-experimental-packages": true)\n'
    if aio:
        pkg += 'supported_targets = "js+native+wasm"\n'
    open(os.path.join(d, "moon.pkg"), "w").write(pkg)
    open(os.path.join(d, "case.mbt"), "w").write(src)

    rec = dict(id=cid, family=family, note=note, targets={}, source=src)
    crashed = False
    for target in targets:
        trec = {}
        for stage in STAGES:
            if stage == "check":
                cmd = [MOON, "check", "--target", target, "-j", "1"]
            elif stage == "build":
                cmd = [MOON, "build", "--target", target, "-j", "1"]
            elif stage == "test-build":
                cmd = [MOON, "test", "--target", target, "-j", "1", "--build-only"]
            else:
                cmd = [MOON, "test", "--target", target, "-j", "1"]
            t0 = time.time()
            try:
                p = subprocess.run(cmd, cwd=d, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, timeout=60, text=True,
                                   errors="replace")
                out, rc, timed = p.stdout, p.returncode, False
            except subprocess.TimeoutExpired as e:
                out, rc, timed = (e.output or "") + "\n[TIMEOUT 60s]", 124, True
            dt = round(time.time() - t0, 2)
            trec[stage] = dict(rc=rc, sig=norm(out, rc), crash=is_crash(out),
                               out=out[-4000:], secs=dt, timeout=timed)
            if rc != 0:
                break
        rec["targets"][target] = trec
        # native-first: only proceed to js/wasm if native fully passed
        if target == "native" and (not trec or any(s["rc"] != 0 for s in trec.values())):
            break
        if "native" not in rec["targets"] or len(rec["targets"]["native"]) != len(STAGES) \
           or any(s["rc"] != 0 for s in rec["targets"]["native"].values()):
            break
    with open(OUT, "a") as f:
        f.write(json.dumps(rec) + "\n")
    st = rec["targets"].get("native", {})
    first = next((k for k in STAGES if k in st and st[k]["rc"] != 0), "PASS")
    desc = st.get(first, {}).get("sig", "all-pass") if first != "PASS" else "PASS"
    print("%-28s %-20s native=%-10s %s" % (cid, family, first, desc), flush=True)
    return rec


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    if not only:
        shutil.rmtree(ROOT, ignore_errors=True)
        os.makedirs(ROOT)
        if os.path.exists(OUT):
            os.remove(OUT)
    for c in CASES:
        if only and only not in c["id"]:
            continue
        run(c["id"], c["family"], c["src"], c["aio"], c["targets"], c["note"])


if __name__ == "__main__":
    main()
