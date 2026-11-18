# LSP transport framing and the remaining advertised methods

Toolchain: `moon 0.1.20261104 (940aa18 2026-11-04)`,
`moonc v0.10.20+65efd5b93 (2026-11-05)`, `moon-lsp` from the same install
(sha256 `5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d`).
Host: single Linux x86_64 machine. Baseline: main `f2a87ce` (63-case probe,
257 tests). Probe: `moonbit/cmd/lspfuzz`, library `moonbit/lsp`.

This sweep extends the existing probe driver rather than adding a second one.
`moonbit/lsp/framing.mbt` gained `frame_with_header`, `frame_declared`,
`split_at` and `scan_stream`; `moonbit/lsp/json.mbt` now extracts the JSON-RPC
error code; `cmd/lspfuzz` gained `--family framing|methods|all` and ordered
byte-step cases. The lsp package went from 20 to 29 pure tests, all passing.

## Oracle and classification

Every case gets a fresh `moon-lsp --stdio`, a bounded wait, and a SIGKILL +
`wait` reap. `OK`/`ERROR_RESPONSE` mean a matching-id response arrived.
`HANG` = no response past the timeout and the process is alive; `CRASH` = the
process exited. Both are repeated in three fresh processes and only 3/3 is
reported as `HANG`/`CRASH` (otherwise `FLAKY_*`).

Two additional outcomes are needed for this sweep:

- `DESYNC`: a complete frame was followed by bytes that cannot start a valid
  frame, or a malformed frame poisoned the input loop so a **later complete
  request** was never processed. The server stays alive at 0% CPU. Repeated
  3/3 like a hang, because it is the same kind of terminal silence.
- `STALL`: the server is alive and silent while a frame is legitimately
  incomplete (declared `Content-Length` exceeds the bytes sent). This is
  labelled `known=expected_wait` and **excluded** from defect counts.

`UNSUPPORTED` is recorded for a method the `initialize` result does not
advertise and that answers `-32601`/`-32603` ("Request not supported yet!").
A single well-formed request followed by no answer is still `HANG`, not
`DESYNC`; `DESYNC` requires the follow-up-request evidence.

## Method verification

`initialize` advertised exactly: `callHierarchyProvider`,
`codeActionProvider`, `codeLensProvider`, `completionProvider`,
`definitionProvider`, `documentFormattingProvider`, `documentSymbolProvider`,
`foldingRangeProvider`, `hoverProvider`, `inlayHintProvider`,
`referencesProvider`, `renameProvider` (with `prepareProvider`),
`semanticTokensProvider` (full, no delta), `signatureHelpProvider`,
`textDocumentSync: 2`, `workspaceSymbolProvider`.

Probed advertised names: `textDocument/definition`, `textDocument/references`,
`textDocument/rename`, `textDocument/prepareRename`,
`textDocument/codeAction`, `textDocument/codeLens`,
`textDocument/inlayHint`, `textDocument/foldingRange`,
`textDocument/semanticTokens/full`, `textDocument/signatureHelp`,
`workspace/symbol`, `callHierarchy/incomingCalls`,
`callHierarchy/outgoingCalls`. `textDocument/documentHighlight` and
`completionItem/resolve` are **not** advertised; both still route and answer
`-32603 Request not supported yet!`, recorded as `UNSUPPORTED`.

## Exact counts

Command (serial, one server at a time):

```
cd moonbit
moon run --target native cmd/lspfuzz -- \
  --out /tmp/lsp_frame_run --timeout-ms 700 --family all
```

136 cases in 71 s wall clock; 0 survivors afterwards.

| family | cases | OK | ERROR_RESPONSE | HANG | DESYNC | STALL | INCOMPLETE | UNSUPPORTED | CRASH | INIT_HANG |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| format-nth | 32 | 22 | 2 | 8 | . | . | . | . | . | . |
| documents | 19 | 18 | 1 | . | . | . | . | . | . | . |
| lifecycle | 12 | 4 | 1 | 6 | . | . | 1 | . | . | . |
| framing | 32 | . | 16 | . | 14 | 2 | . | . | . | . |
| methods | 41 | 26 | 13 | . | . | . | . | 2 | . | . |
| **total** | **136** | **70** | **33** | **14** | **14** | **2** | **1** | **2** | . | . |

New-family subtotals: **framing 32**, **methods 41**. The other 63 cases are
the unchanged main-matrix regression and reproduce the same outcomes as
`findings/lsp_probe.md` (including F10 and F11), so the driver changes did not
disturb the earlier evidence.

## Family A: framing and transport (32 cases)

| case | method label | outcome | known | repeats | elapsed | CPU |
|---|---|---|---|---:|---:|---:|
| `fr-larger-expect-wait` | content-length-too-large-alone | STALL | expected_wait | 1/1 | 701 ms | 0% |
| `fr-larger-then-valid` | content-length-too-large+next | DESYNC | known_prior_silence | 3/3 | 701 ms | 0% |
| `fr-larger-far-then-valid` | content-length-way-too-large+next | STALL | expected_wait | 1/1 | 701 ms | 0% |
| `fr-short-then-valid` | content-length-too-small+next | DESYNC | known_prior_silence | 3/3 | 701 ms | 0% |
| `fr-missing-length-then-valid` | header-without-content-length+next | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-wrong-header-name-then-valid` | content-lenght-typo+next | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-extra-content-type` | extra-content-type | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-extra-unknown-header` | extra-unknown-header | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-lowercase-header` | lowercase-content-length | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-space-before-colon-then-valid` | space-before-colon+next | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-extra-space-value` | space-after-colon | ERROR_RESPONSE | - | 1/1 | 1 ms | 0% |
| `fr-trailing-crlf-between` | blank-line-between-frames | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-header-split` | header-split-across-writes | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-body-split` | body-split-across-writes | ERROR_RESPONSE | - | 1/1 | 1 ms | 0% |
| `fr-bytewise-split` | frame-in-nine-byte-writes | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-bom-then-valid` | utf8-bom+next | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-lf-only-header` | lf-only-terminator | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-top-array-then-valid` | top-level-array+next | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-top-number-then-valid` | top-level-number+next | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-top-string-then-valid` | top-level-string+next | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-top-null-then-valid` | top-level-null+next | DESYNC | new_trigger | 3/3 | 701 ms | 0% |
| `fr-empty-body-then-valid` | content-length-zero+next | DESYNC | new_trigger | 3/3 | 700 ms | 0% |
| `fr-pipeline-two-valid` | two-valid-requests-one-write | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-pipeline-valid-then-bad` | valid-then-malformed-one-write | ERROR_RESPONSE | - | 1/1 | 1 ms | 0% |
| `fr-duplicate-id` | duplicate-id-two-responses | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-large-1mb` | 1mb-params | ERROR_RESPONSE | - | 1/1 | 7 ms | 0% |
| `fr-large-8mb` | 8mb-params | ERROR_RESPONSE | - | 1/1 | 41 ms | 121% |
| `fr-shutdown-then-request` | shutdown-then-frame | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-request-then-shutdown` | request-then-shutdown-one-write | ERROR_RESPONSE | - | 1/1 | 0 ms | 0% |
| `fr-bad-json-then-valid` | malformed-json+next | DESYNC | known_prior_silence | 3/3 | 701 ms | 0% |
| `fr-no-header-then-valid` | headerless-json+next | DESYNC | known_prior_silence | 3/3 | 701 ms | 0% |
| `fr-bad-length-then-valid` | content-length-xyz+next | DESYNC | known_prior_silence | 3/3 | 701 ms | 0% |

`ERROR_RESPONSE` here usually means `-32601 Unknown method` for the probe
method, i.e. the request was processed normally; for the method matrix it is
the expected `-32602` empty-params answer.

### EXPECTED_WAIT exclusions

Two cases are excluded as `known=expected_wait`:

- `fr-larger-expect-wait`: `Content-Length` declared 200 bytes too large and
  nothing else sent. The server waits for the rest of the body; that is
  exactly what the framing says to do. No defect.
- `fr-larger-far-then-valid`: declared 400 bytes too large, a complete request
  is appended but the declared body is still not complete. The server cannot
  know where the next frame starts, so waiting is legitimate. No defect.

When the declared length is only slightly too large (`fr-larger-then-valid`,
+20), the follow-up frame completes the declared body with header bytes; the
body is then invalid JSON and the input loop wedges (DESYNC). That is not an
expected wait: the declared body was fully delivered and the next frame was
complete.

### Recovery and grouping of DESYNC cases

All 14 `DESYNC` rows are 3/3, elapsed 700-701 ms, CPU 0%. They split into:

- **9 new trigger shapes** (`known=new_trigger`): BOM before the first header;
  top-level array/number/string/`null`; `Content-Length: 0` empty body;
  a header block without `Content-Length`; a typo'd header name; and a stray
  blank line between frames.
- **5 previously silent triggers** (`known=known_prior_silence`): oversized
  length, undersized length, malformed JSON, headerless JSON and
  `Content-Length: xyz`. The single-request silence of these was already in
  `findings/lsp_probe.md`; what is new here is that the server stays alive and
  never processes a subsequent complete request, i.e. the session is
  permanently dead rather than one request being unanswered.

`fr-space-before-colon-then-valid` is **not** a desync: the server tolerates
the space before the colon and answers both id 2 and id 3. Extra
`Content-Type`, an unknown extra header, lowercase `content-length`, extra
space after the colon, LF-only terminators, header/body split writes and
nine-byte writes all answer normally. 1 MB and 8 MB single requests answer at
0% CPU. Two requests in one write both answer; duplicate ids get two
responses; a request after a clean `shutdown` answers.

## Family B: advertised methods (41 cases)

Each advertised method was probed three ways, always in a fresh process:

1. `params: {}` with no document;
2. plausible method-specific params after a real `didOpen` of a small valid
   program (the control);
3. plausible params for a file that exists on disk but was never opened.

Every method answered; none hung or crashed. `{}` is uniformly rejected with
`-32602` (the generated params type fails to convert), which is a normal error
response, not silence. The controls all returned a real result (definition,
references, rename edits, code lenses, semantic tokens, etc.). Requests for a
never-opened document also answered, generally `null`/`[]` rather than an
error.

| method | empty `{}` | control (`didOpen` + plausible) | never opened |
|---|---|---|---|
| `textDocument/codeAction` | ERROR_RESPONSE | OK | OK |
| `textDocument/codeLens` | ERROR_RESPONSE | OK | OK |
| `completionItem/resolve` (not advertised) | UNSUPPORTED | - | - |
| `textDocument/definition` | ERROR_RESPONSE | OK | OK |
| `textDocument/documentHighlight` (not advertised) | UNSUPPORTED | - | - |
| `textDocument/foldingRange` | ERROR_RESPONSE | OK | OK |
| `callHierarchy/incomingCalls` | ERROR_RESPONSE | OK | OK |
| `textDocument/inlayHint` | ERROR_RESPONSE | OK | OK |
| `callHierarchy/outgoingCalls` | ERROR_RESPONSE | OK | OK |
| `textDocument/prepareRename` | ERROR_RESPONSE | OK | OK |
| `textDocument/references` | ERROR_RESPONSE | OK | OK |
| `textDocument/rename` | ERROR_RESPONSE | OK | OK |
| `textDocument/semanticTokens/full` | ERROR_RESPONSE | OK | OK |
| `textDocument/signatureHelp` | ERROR_RESPONSE | OK | OK |
| `workspace/symbol` | ERROR_RESPONSE | OK | OK |

The two unadvertised names were checked rather than assumed. Both are routed
but unsupported (`-32603 Request not supported yet!`); they are
`UNSUPPORTED`, not new errors.

**No new method-level hang or crash was found.** The residual risk is that
this matrix uses one small document and one position per method; it is a
reachability check, not a fuzzer.

## New finding: F12 (permanent framing wedge)

Confirmed 3/3 with fresh processes and a no-fail control; see
`poc/f12_lsp_frame_wedge/` and its `evidence.txt`.

A single unparsable frame permanently wedges the stdio input loop: the
trigger request is not answered, a later **complete** request id 3 is also
never answered, the process stays alive at 0% CPU with stdout open, and
stderr contains `Internal error: Uncaught exception.`
(`Yojson.Json_error` for the BOM, `Jsonrpc: json conversion failed: invalid
packet` for `[1,2]`). The control (a valid frame, then the same id-3 request)
answers both ids, so the harness can observe responses that arrive together.

Minimal new triggers (bytes committed in the PoC):

- `EF BB BF` before an otherwise valid `Content-Length` header;
- `Content-Length: 5\r\n\r\n[1,2]` - valid JSON, not a JSON-RPC object.

The underlying "bad input produces no response" was already seen for
malformed JSON. F12's claim is narrower and stronger: the failure is
permanent and session-fatal, and it is reachable through new transport/encoding
shapes that a real client can emit. It is **not** F10 (no 100% CPU spin) and
**not** F11 (no scalar `params`). It is not root-caused; the stderr block is
consistent with an uncaught decoder exception escaping the read loop, but the
PoC makes no source-level claim.

## Validation

- `moon test --target native`: **266/266** (257 baseline + 9 new framing /
  error-code tests; the lsp package itself is 29/29).
- `moon check`: 0 warnings; `moon fmt`, `moon fmt --check` clean.
- Probe run above: 136 cases, the counts in the table, no `CRASH`,
  `INIT_HANG` or `FLAKY_*`.
- `pgrep -x moon-lsp` printed nothing after the run and after the F12
  evidence run; every server is killed and reaped by the driver.

Raw rows: `findings/lsp_framing_results.jsonl`; aggregate:
`findings/lsp_framing_summary.json`.

## Limitations

- Curated cases, not random or coverage-guided fuzzing; absence of a shape is
  not evidence of absence.
- Wall-clock timeouts (700 ms probe, 2 s PoC) can miss a slower answer.
- One toolchain, one host, one `moon-lsp` binary; behaviour may differ across
  versions.
- The method set was verified only against this binary's `initialize` result;
  methods absent here (e.g. `textDocument/documentHighlight`,
  `completionItem/resolve`) were not probed beyond their `-32603` verdict.
- One small source document and one position per method in family B.
- The framing library's strict parser recognises CRLF only, while the server
  also accepts LF-only headers; this mismatch is documented in a unit test
  and is a limitation of the pure framer, not of the server.
- No coverage of mid-UTF-8 byte splits (the split helper is character-based).
- The probe does not capture server stderr; the internal-exception evidence
  comes from the F12 replay script, which does.
