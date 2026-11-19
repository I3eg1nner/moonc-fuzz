# LSP defect regression gate (`cmd/lspregress`)

Upstream: filed as [moonbit-docs#1376](https://github.com/moonbitlang/moonbit-docs/issues/1376)
(F11 and F12 are one report).

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
| `F11-hang` | `textDocument/hover` with `"params":null` (id 2), then a complete `moonbit-lsp/format-nth` with a trailing newline (id 3) 100 ms later | `HANG`: **both** requests unanswered, process alive | F11 |
| `F11-control` | same hover method with `"params":{}` | error response `-32602` | F11 |
| `F12-hang` | after `initialize`, `Content-Length: 5\r\n\r\n[1,2]`, then a complete `shutdown` id 3 | no id-3 response, process alive | F12 |
| `F12-control` | after `initialize`, two complete `format-nth` requests (ids 2 and 3) | both ids answered (result *or* error) | F12 |

Each case gets a fresh `moon-lsp --stdio`. The driver initializes (id 1),
sends `initialized`, sends the trigger, and reads complete frames for at most
`--timeout-ms` (default 2000). Only frames with **no `id` member at all** are
treated as notifications and ignored. Every other frame — including
`id: null`, `id: "2"` and malformed ids — is recorded as a response frame.
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

## False pass found and fixed (2026-11-18)

An external review found that the oracle could pass for the wrong reason. The
old `Hang` matcher only looked for a response whose `id` parsed as an integer.
`moonbit/lsp/json.mbt` parsed `id` with `parse_int_at`, so `id: null` and
`id: "2"` both became `None`, and `collect()` dropped any frame whose id was
not an integer. `evaluate(Hang, …)` then saw an empty id list and reported
`HANG` even though the server had answered.

This is not a theoretical shape. JSON-RPC requires an error response generated
for a request whose id could not be parsed to carry `"id": null` (for example
`-32600 Invalid Request`); string ids are legal too. A server that correctly
answers the malformed request was therefore scored as silent.

The reviewer demonstrated it with an in-memory fake server:

| server answer to the first request | old verdict |
|---|---|
| `{"id":2,"error":{...}}` | correctly failed the inverted case |
| `{"id":null,"error":{...}}` | **wrongly passed** (`HANG`) |
| `{"id":"2","error":{...}}` | **wrongly passed** (`HANG`) |

The fix makes detection independent of id type:

- `json.mbt` now exposes `IdKind` (`IdMissing`, `IdNull`, `IdInt`,
  `IdString`, `IdOther`) and `ResponseInfo::is_response()`, defined as
  “has an `id` member (any type) **and** a top-level `result` or `error`”.
  `id: null` with an error/result is a response, not a notification; only
  `IdMissing` is a notification.
- `lspregress` records every response frame in `Wire.response_frames`.
  **Any response frame disables `HANG`.** If it cannot be correlated to an
  expected integer id, the case fails with `RESPONSE_UNASSOCIATED` and the
  raw frame excerpt instead of `HANG`.
- `lspfuzz` applies the same rule: a timed-out wait that nevertheless saw a
  response frame is classified `DESYNC`, not `HANG`; the init stage no longer
  reports `INIT_HANG` when a non-matching response arrived.

`id: null` must count because it is precisely how a spec-conformant server
reports that it received a malformed request. Treating it as silence turns
"server correctly rejected the request" into "server is wedged", which is the
opposite of what the inverted oracle is meant to detect.

The reviewer's counterexample is now a pure unit test
(`hang matcher: unassociated response frames are never HANG`): a synthetic
`id: null` error and a synthetic `id: "2"` error both produce `ok:false` with
`RESPONSE_UNASSOCIATED`, so the old false pass fails the suite.

Two adjacent cases were tightened in the same change:

- `F11-hang` now sends a **second complete request** after the scalar-params
  hover. Both must stay unanswered. If the second one is answered, the case
  fails with `PARTIAL_RECOVERY` (queue recovery, not the documented
  session-level hang) rather than confirming F11.
- `F12-control` no longer sends two consecutive `shutdown`s. After a
  `shutdown`, the protocol says later requests should be rejected, so
  requiring a second `shutdown` to succeed could fail a conforming server.
  The control now sends two complete `format-nth` requests; “answered” means a
  response frame of either kind (result or error) arrived for both ids.

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
| `F10-hang`, `F12-hang` | `timeout_ms` + 20–120 ms (spawn, initialize, kill/reap) |
| `F11-hang` | `timeout_ms` + 120–220 ms (100 ms between the two requests, then spawn/initialize/kill/reap) |
| controls | 40–90 ms |
| whole gate, default 2000 ms | ≈ 6.4–6.8 s |

The three hang cases dominate by construction. Keep the case count at six and
the timeout at 1.5–2 s on a loaded host: a hang costs the full timeout, and
each case also pays one process spawn plus a `/bin/cat /proc/<pid>/stat`
liveness read. Never raise the timeout to make a hang "more certain"; 2 s is
already 10× the observed control latency.

## Current observed timings

Run on 2026-11-18 in the `agent/lsporacle` worktree (the oracle fix),
default 2000 ms:

```
{"case":"F10-hang","expected":"HANG","observed":"HANG","ok":true,"ms":2056}
{"case":"F10-control","expected":"RESPONSE(newText)","observed":"OK","ok":true,"ms":42}
{"case":"F11-hang","expected":"HANG","observed":"HANG","ok":true,"ms":2154}
{"case":"F11-control","expected":"ERROR(-32602)","observed":"ERROR -32602","ok":true,"ms":45}
{"case":"F12-hang","expected":"HANG","observed":"HANG","ok":true,"ms":2104}
{"case":"F12-control","expected":"IDS[2,3]","observed":"IDS [2,3]","ok":true,"ms":76}
{"ok":true,"passed":6,"failed":0}
```

Total of the six case times: 6.48 s; `pgrep -x moon-lsp` was empty afterwards.
The F11 follow-up `format-nth` is sent 100 ms after the scalar-params hover.
A healthy server answers that same request in ≈40–45 ms (see `F10-control` and
the two-request `F12-control`), so the 2154 ms F11 case is the full timeout
with both requests unanswered, not a slow answer. `moon test --target native`:
275/275 (the pre-existing 271 plus four new pure tests for id-type-independent
response detection, the verdict table and the F11 two-request logic).

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

## The other direction: corpus of healthy sessions

The gate above is a *reverse* oracle: it fails when a defect stops reproducing.
That catches regressions in the defect, not false alarms in the classifier. The
gap was named in `findings/methodology.md` §4: the stall oracles had no real
negatives.

`moonbit/cmd/lspneg` closes it from the other side. Each session spawns a fresh
`moon-lsp --stdio`, initializes, opens a real file on disk, then issues seven
benign requests:

| probe | expected healthy answer |
|---|---|
| `textDocument/hover` | a hover result (or `null` for an unknown symbol) |
| `textDocument/documentSymbol` | a symbol list |
| `textDocument/completion` | a completion list |
| `textDocument/formatting` | a text edit |
| `textDocument/diagnostic` | `-32603` (not supported, but answered) |
| unknown method | `-32601` |
| `textDocument/hover` with `{}` | `-32602` |

An answered request is one negative observation (`rc=0`, no timeout, one
frame). A request that is not answered produces a finding and counts as a false
alarm. The probe also sends the F11 trigger (`params: null`) once and fails the
run if that produces no finding - a zero from a blind detector is not evidence.

Measured 2026-11-19 on the pin: **20 sessions, 140/140 answered, 0 findings**
(`3/140 = 2.1%` at 95%). Gate `lsp_negative` runs three sessions (21
observations) on every `accept` invocation.

Limits, stated because they bound the claim: the sessions are serial and share
one binary, so 140 observations are not 140 independent servers; and a healthy
session never times out, so the hang oracles still receive no *timeout*
negatives. What this corpus rules out is the mundane false alarm - a healthy
request being reported as a stall, a missing frame or a crash.
