# LSP protocol probe: `moon-lsp` stdio surface (F10 neighbours)

Toolchain: `moon 0.1.20261104 (940aa18 2026-11-04)`,
`moonc v0.10.20+65efd5b93 (2026-11-05)`, `moon-lsp` from the same install.
Host: single Linux x86_64 machine. Probe: `moonbit/cmd/lspfuzz`, library
`moonbit/lsp`.

## Surface

`moon-lsp --stdio` speaks JSON-RPC 2.0 over stdin/stdout with
`Content-Length: N\r\n\r\n` framing. It is the code path VS Code and other
editors use, it is not exercised by the compiler fuzzers, and one unresponsive
request blocks every later request because the server handles them in order.
F10 (`poc/f10_lsp_format_nth_hang/`) showed that this surface can hang at 100%
CPU on a 17-byte `moonbit-lsp/format-nth` payload. The question here is whether
F10 has neighbours.

## Why a timeout oracle

The failure mode is silence, not an error code: the server keeps the process
alive and simply never answers. Exit status is therefore useless until the
client gives up. The probe treats a matching-id response within the timeout as
`OK`/`ERROR_RESPONSE`, a still-live process with no response as `HANG`, and an
exited process with no response as `CRASH` (recording the exit code/signal).
A candidate `HANG`/`CRASH` is re-run in **three fresh processes**; only 3/3 is
reported as `HANG`/`CRASH`, otherwise it is `FLAKY_HANG`/`FLAKY_CRASH`.
Every case gets a fresh server, because a hung request poisons the queue for
anything sent afterwards.

## Method verification

The request model was checked against the installed binary before use.
`initialize` advertises `hoverProvider`, `completionProvider`,
`documentFormattingProvider`, `documentSymbolProvider`,
`definitionProvider`, `referencesProvider`, `renameProvider`,
`codeActionProvider`, `codeLensProvider`, `callHierarchyProvider`,
`signatureHelpProvider`, `workspaceSymbolProvider`, `semanticTokensProvider`.
`textDocument/didOpen`, `initialized`, `shutdown` and `exit` are base-protocol
methods. `textDocument/diagnostic` is *not* advertised, but the binary routes
it and returns `-32603 Request not supported yet!`; it is kept as an
`ERROR_RESPONSE` case rather than as a supported method. No method name was
invented.

## Matrix and exact counts

Command:

```
cd moonbit
moon run --target native cmd/lspfuzz -- \
  --out /tmp/lsp_final2 --timeout-ms 800 --cases all
```

63 cases, each in a fresh `moon-lsp` process; 14 hangs were re-run 3x.

| family | cases | OK | ERROR_RESPONSE | HANG | INCOMPLETE |
|---|---:|---:|---:|---:|---:|
| format-nth | 32 | 22 | 2 | 8 | 0 |
| documents | 19 | 18 | 1 | 0 | 0 |
| lifecycle | 12 | 4 | 1 | 6 | 1 |
| **total** | **63** | **44** | **4** | **14** | **1** |

No `CRASH`, `INIT_HANG`, `FLAKY_HANG` or `FLAKY_CRASH` occurred. Every server
handshake succeeded (`initialize` returned in all 63 cases). Raw rows:
`findings/lsp_probe_results.jsonl`; aggregate: `findings/lsp_probe_summary.json`.

The format matrix covers: exact F10 payload and trailing-newline control;
empty, whitespace-only, separator-only, newline-only and CRLF-only content;
single/multiple blocks; `n` = 0, middle, last, too large, negative; no final
newline variants; trailing space; trailing `\r`; trailing comment; content
ending mid-token; `///|` doc block; `isMarkdown: true`; unicode/emoji; a very
long single line. The document matrix opens a temp project's `a.mbt` (with and
without final newline) then sends `textDocument/formatting`, `hover` at EOF,
`completion` at EOF, `documentSymbol` and `diagnostic`; it also sends requests
for a file that exists but was never opened, a non-existent file URI, and
positions past EOF. Lifecycle covers `shutdown` (params omitted, `{}`, `null`,
`0`), shutdown-then-hover, shutdown-then-exit, an unknown method, malformed
JSON, a bad Content-Length, a missing header, an undersized and an oversized
Content-Length.

## Hangs, with payloads and repeats

All rows below are 3/3 in fresh processes unless stated.

| case | method | hits | CPU | known | payload |
|---|---|---:|---:|---|---|
| fmt-f10-exact-no-final-newline | format-nth | 3/3 | 99% | **known_f10** | `{"content":"fn f() -> Unit {\n  ()\n}","n":0,"isMarkdown":false}` |
| fmt-multi-no-nl-n1-last | format-nth | 3/3 | 99% | F10-adjacent | two blocks, no final newline, `n=1` |
| fmt-triple-no-nl-n2-last | format-nth | 3/3 | 100% | F10-adjacent | three blocks, no final newline, `n=2` |
| fmt-trailing-space-no-nl | format-nth | 3/3 | 99% | F10-adjacent | single block + trailing space, `n=0` |
| fmt-crlf-no-final-newline | format-nth | 3/3 | 100% | F10-adjacent | CRLF body, no final newline, `n=0` |
| fmt-separator-doc-no-nl | format-nth | 3/3 | 99% | F10-adjacent | `///|` + single block, no final newline |
| fmt-unicode-emoji-no-nl | format-nth | 3/3 | 99% | F10-adjacent | emoji/unicode comment, no final newline |
| fmt-very-long-line | format-nth | 3/3 | 99% | F10-adjacent | one ~1.2 KB line, no final newline |
| life-shutdown-null | shutdown | 3/3 | 0% | **new (F11)** | `{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}` |
| life-shutdown-number | shutdown | 3/3 | 0% | **new (F11 shape)** | same with `"params":0` |
| frame-bad-json | malformed-json | 3/3 | 0% | protocol silence | `Content-Length: 9` + `{not json` |
| frame-bad-content-length | bad-content-length | 3/3 | 0% | protocol silence | `Content-Length: xyz\r\n\r\n{}` |
| frame-no-header | no-header | 3/3 | 0% | protocol silence | headerless JSON-RPC shutdown request |
| frame-length-too-small | content-length-small | 3/3 | 0% | protocol silence | declared 5, 55-byte JSON-RPC body |

Full payload strings are in `findings/lsp_probe_results.jsonl`; the very long
line case is `"fn f() -> Unit { let x = " + "1 + ".repeat(400) + "1 }"`.

### What is actually new

- **F11: `shutdown` with explicit `"params": null` never returns.** This is the
  one clean new finding. It is 3/3, the process stays alive at ~0% CPU (a
  deadlock, not a spin), a later `hover` is also unanswered, and the controls
  are unambiguous: omitting `params` returns `{"result": null}` immediately,
  `params: {}` and `params: []` also return immediately. Scalar `params: 0`
  deadlocks too.

  **Post-probe generalisation (project-manager verification, after the commit).**
  The trigger is not `shutdown` and not `null` specifically: it is *any scalar
  `params`*, on *any method*. Verified with the committed `replay.py`:

  | method | `null` | `0` | `"x"` | `true` | `{}` | `[]` | omitted |
  |---|---|---|---|---|---|---|---|
  | `textDocument/hover` | hang | hang | hang | hang | `-32602` | `-32602` | `-32602` |
  | `shutdown` | hang | — | — | — | `null` | — | — |
  | `no/such-method` | hang | — | — | — | `-32601` | — | — |

  Queued requests are also blocked: `shutdown` with `params: null` followed by a
  well-formed `format-nth` yields two consecutive timeouts, where the same
  `format-nth` answers in under 10 ms on a clean server. PoC renamed to
  `poc/f11_lsp_scalar_params_deadlock/`; `README.md` there carries the full
  matrix, the 3/3 repeats and the no-upstream-report note. Not root-caused.
- **Seven F10-adjacent format hangs.** Each hangs 3/3 at 99–100% CPU with the
  same trigger condition as F10: `format-nth` on the *last* top-level block
  when the content has no final newline. I am **not** claiming these as a new
  root cause; they are new *shapes* (multi-block, CRLF, emoji, long line,
  trailing space, `///|`) that all confirm the same upstream defect class.
  `n` pointing at a non-last block and the same content with a final newline
  are OK, and empty/whitespace/out-of-range/negative cases are OK or clean
  errors, which is the expected control behaviour.
- **Four protocol silences.** Intentionally malformed frames (bad JSON, bad
  `Content-Length`, no header, undersized `Content-Length`) get no response at
  all rather than a JSON-RPC parse error. They are 3/3 but are not CPU hangs;
  they are recorded as a framing/protocol-conformance gap and excluded from the
  "new hang" claim because the bytes never formed a valid JSON-RPC request.
  The oversized-`Content-Length` case is deliberately incomplete, so no
  response is expected and it is classified `INCOMPLETE`, not `HANG`.

## Limitations

- Single host and a single pinned toolchain; no cross-machine or cross-version
  claim.
- The matrix is curated, not random; it covers the shapes listed above but not
  every LSP method (e.g. `rename`, `references`, `codeAction`, `codeLens`,
  `inlayHint`, `semanticTokens` are advertised but not probed).
- Timeouts are wall-clock (800 ms for the full run; 5 s for the F11 replay).
  A response slower than the timeout would be misclassified; the 3/3 re-runs
  and the F10 control make that unlikely for the reported hangs.
- Method names and params were verified only against this binary; another
  `moon-lsp` build could add/remove methods.
- A hanging server masks later cases, so each case gets a fresh process; this
  costs startup time and means cases cannot share didOpen state.
- Server stderr is collected by the runner but not interpreted; no stderr
  signature is part of the oracle.
- `textDocument/diagnostic` is routed but unsupported (`-32603`); its
  `ERROR_RESPONSE` is not evidence that diagnostics work.

## Validation and process hygiene

```
moon test --target native     -> Total tests: 257, passed: 257, failed: 0
moon check --target native    -> 0 warnings, 0 errors
moon fmt && moon fmt --check  -> clean
```

63/63 probe cases produced rows; the exact F10 payload is `HANG` with
`known_f10` in `results.jsonl`; no crash occurred. After the run,
`pgrep -x moon-lsp` is empty and `pgrep -f '[m]oon-lsp'` is empty (the bracket
avoids matching the checking shell's own command line). Every case kills by pid
and reaps with `wait()`; the runner uses an external `/bin/kill -9` because
calling the async cancellation-handler value directly did not schedule the
kill.
