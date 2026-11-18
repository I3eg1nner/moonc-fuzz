# LSP defect regression gate (`cmd/lspregress`)

`moonbit/cmd/lspregress/` is the automated gate for the three documented
`moon-lsp` stdio defects F10, F11 and F12. It replaces "someone remembers to
run the PoC" with six black-box cases: one canonical trigger and one control
per defect. The gate is invoked by `cmd/accept` as the separately named
`lsp_regress_6` check.

Toolchain for the timings below:

- `moon 0.1.20261104 (940aa18 2026-11-04)`
- `moonc v0.10.20+65efd5b93 (2026-11-05)`
- `moon-lsp` sha256 `5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d`

## What the gate asserts

| case | trigger | expected | control for |
|---|---|---|---|
| `F10-hang` | `moonbit-lsp/format-nth` with `{"content":"fn f() -> Unit {\n  ()\n}","n":0,"isMarkdown":false}` | `HANG`: no response, process alive | F10 |
| `F10-control` | same content plus a trailing `\n` | response body contains `newText` | F10 |
| `F11-hang` | `textDocument/hover` with `"params":null` | `HANG`: no response, process alive | F11 |
| `F11-control` | same method with `"params":{}` | error response `-32602` | F11 |
| `F12-hang` | after `initialize`, `Content-Length: 5\r\n\r\n[1,2]`, then a complete `shutdown` id 3 | no id-3 response, process alive | F12 |
| `F12-control` | after `initialize`, `shutdown` id 2 then `shutdown` id 3 | both ids answered | F12 |

Each case gets a fresh `moon-lsp --stdio`. The driver initializes (id 1),
sends `initialized`, sends the trigger, and reads complete frames for at most
`--timeout-ms` (default 2000). Notifications without an `id` are ignored.
Every server is SIGKILLed and reaped before the next case starts, so at most
one `moon-lsp` exists at a time. A case that cannot initialize reports
`INIT_FAILED`, never `HANG`.

Output is the same JSONL contract as `cmd/regress`:

```json
{"case":"F10-hang","expected":"HANG","observed":"HANG","ok":true,"ms":2046,"message":""}
...
{"ok":true,"passed":6,"failed":0}
```

`message` is empty on success. On failure it is the loud explanation, e.g.
`F10-hang: expected HANG, observed OK — defect appears fixed; update
findings/lsp_probe.md and poc/`. Exit status is 0 only when all six cases
match, 1 on any mismatch, and 2 for bad usage or a missing `moon-lsp` binary.

## Inverted oracle: a fix upstream must FAIL this gate

These cases assert that a **defect exists**. `F10-hang`, `F11-hang` and
`F12-hang` pass when the server is silent and alive; they fail the moment the
server answers. That is intentional. If upstream fixes F10/F11/F12, the correct
response is:

1. the gate fails with `expected HANG, observed OK` (or
   `ERROR …`), and
2. the PoC and `findings/lsp_probe.md` are updated to say the defect is
   fixed, and
3. the case is reclassified as a control (see procedure below).

**Do not "fix" a failing inverted case by flipping `Hang` to a response
expectation without doing the documentation/PoC update.** The name `*-hang`
and the `kind: "defect"` field in `build_cases()` are the markers that this is
an inverted oracle; a silent flip turns a would-be fix detector into a
tautology. The unit test file keeps the semantics explicit with synthetic
wires: silence+alive passes, any response fails.

## Expected durations

| case class | expected wall time |
|---|---|
| `F10-hang`, `F11-hang`, `F12-hang` | `timeout_ms` + 20–120 ms (spawn, initialize, kill/reap) |
| controls | 40–90 ms |
| whole gate, default 2000 ms | ≈ 6.3–6.6 s |

The three hang cases dominate by construction. Keep the case count at six and
the timeout at 1.5–2 s on a loaded host: a hang costs the full timeout, and
each case also pays one process spawn plus a `/bin/cat /proc/<pid>/stat`
liveness read. Never raise the timeout to make a hang "more certain"; 2 s is
already 10× the observed control latency.

## Current observed timings

Run on 2026-11-18 in the `agent/lspregress` worktree, default 2000 ms:

```
{"case":"F10-hang","expected":"HANG","observed":"HANG","ok":true,"ms":2046}
{"case":"F10-control","expected":"RESPONSE(newText)","observed":"OK","ok":true,"ms":43}
{"case":"F11-hang","expected":"HANG","observed":"HANG","ok":true,"ms":2046}
{"case":"F11-control","expected":"ERROR(-32602)","observed":"ERROR -32602","ok":true,"ms":43}
{"case":"F12-hang","expected":"HANG","observed":"HANG","ok":true,"ms":2099}
{"case":"F12-control","expected":"IDS[2,3]","observed":"IDS [2,3]","ok":true,"ms":73}
{"ok":true,"passed":6,"failed":0}
```

Total wall time: 6.35 s (`time` on the built binary). `pgrep -x moon-lsp` was
empty afterwards. `moon test --target native`: 271/271 (the pre-existing 266
plus five new pure matcher/path tests).

The same run through `cmd/accept` reported
`{"check":"lsp_regress_6","ok":true,"detail":"rc=0 cases=6 rows=7 ms=6345"}`;
the whole accept run took 1 m 27 s. `--moon-lsp /no/such/moon-lsp` exits 2
with `moon-lsp not found: ...`, and `--only F11-control,F12-control` runs just
those two rows.

## Accept integration

`cmd/accept` builds `moonbit`, then runs
`_build/native/debug/build/cmd/lspregress/lspregress.exe` with a 60 s ceiling
and adds `lsp_regress_6`. The check requires:

- rc 0,
- exactly 7 stdout rows (6 case rows + summary),
- every row containing `"ok":true`,
- `moon-lsp` present at `$HOME/.moon/bin/moon-lsp`.

The accept detail is `rc=… cases=6 rows=… ms=…`, so the LSP portion of the
acceptance time is visible without re-running anything. If `moon-lsp` is
absent, the detail is exactly `moon-lsp not found` and the check is
`ok:false`; it is not skipped. `regressions_12` is untouched and still owns
the twelve compiler defect cases.

## Updating the gate when a defect is fixed

Follow this only after independently confirming the fix with the PoC and
`cmd/lspfuzz` (same toolchain hash, fresh processes, controls still pass).

1. Replay the PoC (`poc/f10_lsp_format_nth_hang/replay.py`, etc.) on the new
   toolchain. Record the new `moon-lsp` sha256 and the observed result.
2. Update `findings/lsp_probe.md` and the affected `poc/f1x_*/README.md`
   status from "confirmed" to "fixed in <version/hash>", keeping the original
   reproduction evidence and date.
3. In `moonbit/cmd/lspregress/main.mbt`:
   - change that case's `Expected` from `Hang` to the new contract (for a
     fixed F10, a `ResponseContains` with `newText`; for F11/F12, an
     `ErrorCode` or `AllAnswered` as appropriate),
   - change its `kind` from `"defect"` to `"control"`,
   - update the case name from `*-hang` to a name that no longer promises a
     hang (e.g. `F10-fixed`), and update `want` in `drive` if the case no
     longer needs a special follow-up frame.
4. Update the pure test table in `lspregress_wbtest.mbt` so the matcher still
   covers `Hang` failing on a response and the new expectation passing.
5. Update the case table, expected durations and observed timings in this
   file. Note in the commit message which defect was retired and the
   toolchain hash that fixed it.
6. Run `moon test --target native`, `moon check`, `moon fmt --check`, the gate,
   and `moon run cmd/accept -- <worktree>`. Confirm `lsp_regress_6` passes and
   `pgrep -x moon-lsp` is empty.

If a case fails for any other reason (control mismatch, `INIT_FAILED`,
`MISSING_ID`), do not reclassify it. That is either a gate bug or a new
server regression; investigate before touching the expectation.
