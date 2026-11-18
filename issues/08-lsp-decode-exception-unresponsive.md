---
title: "moon-lsp: an input-decode exception escapes the stdio read loop and leaves a live but unresponsive session"
labels: [bug, lsp]
state: draft
toolchain: moon 0.1.20261104, moonc v0.10.20+65efd5b93
moon_lsp_sha256: 5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d
upstream_duplicate_check: 2026-11-18
---

# `moon-lsp`: an input-decode exception escapes the stdio read loop and leaves a live but unresponsive session

Two request shapes make `moon-lsp` stop serving. In both cases the server stays
alive at ~0% CPU, keeps stdout open, sends no response, and **never reads later
requests** — their bytes stay unread in the stdin pipe. The server prints an
uncaught-exception block to stderr naming the same escape path in both cases.

They are reported together because the mechanism is the same (an exception
raised while decoding an input frame escapes `Lsp__Io.Make.read`); only the
raise site differs.

| trigger | stderr |
|---|---|
| request whose `params` is a JSON scalar | `Jsonrpc: json conversion failed: invalid structured value`, raised in `Jsonrpc.Packet.t_of_fields` |
| frame whose top-level JSON value is not an object (e.g. `[1,2]`) | `Jsonrpc: json conversion failed: invalid packet`, raised in `Jsonrpc.Packet.t_of_yojson` |

A third, related shape fails one layer earlier, in header parsing: a UTF-8 BOM
before `Content-Length` raises `Error: content length absent` in
`Lsp__Io.Make.read_header`, with the same outcome.

## Reproduction

`moon-lsp --stdio`, send `initialize` (id 1), then `initialized`, then the
trigger, then a **complete, well-formed** request (id 3). The id-3 request is
never answered.

### Trigger A — scalar `params`

```json
{"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": null}
```

`params` may be `null`, a number, a string, or a boolean; all behave the same.
`{}`, `[]`, and an omitted `params` all get a normal response (`-32602`).

### Trigger B — non-object top-level body

```
Content-Length: 5\r\n\r\n[1,2]
```

`[1,2]` is valid JSON. `Content-Length` matches the body exactly.

### Trigger C — BOM before the header

```
\xef\xbb\xbfContent-Length: 63\r\n\r\n{"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}
```

## Observed

Fresh process per run; published toolchain and binary:

| trigger | response to trigger | response to later complete request | process | CPU | stdout |
|---|---|---|---|---|---|
| A `params: null` | none | **none** | alive | ~0% | open, not EOF |
| B `[1,2]` | none | **none** | alive | ~0% | open, not EOF |
| C BOM | none | **none** | alive | ~0% | open, not EOF |
| control: `params: {}` | `-32602` | answered | alive | — | — |
| control: valid object `params` | `hover` result | answered | alive | — | — |
| control: `params` omitted | `-32602 params are required` | answered | alive | — | — |
| control: unknown method, `{}` | `-32601` | answered | alive | — | — |

Measurement details (15 s observation, independent driver, no id-based
filtering of the raw stream):

- process state `S`, CPU delta 1 tick over 15 s;
- non-blocking `read` on stdout returns `EAGAIN`, not `b""` — the pipe is open;
- **314 bytes unread in the stdin pipe**, exactly the two complete health
  requests sent after the trigger; in the control run the backlog is 0.

So this is not "slow", not "waiting for more bytes", and not EOF: the read loop
is gone while the process lives on.

## stderr (verbatim, trigger B)

```
/-----------------------------------------------------------------------
| Internal error: Uncaught exception.
| Jsonrpc: json conversion failed: invalid packet
| Raised at Jsonrpc__Import.Json.error in file "ocaml-lsp/jsonrpc/src/import.ml", line 22, characters 23-50
| Called from Jsonrpc.Packet.t_of_yojson in file "ocaml-lsp/jsonrpc/src/jsonrpc.ml", line 291, characters 15-47
| Called from Lsp__Io.Make.read in file "ocaml-lsp/lsp/src/io.ml", line 103, characters 25-58
| Called from Fiber__Scheduler.exec in file "fiber/src/scheduler.ml", line 73, characters 8-11
```

and for trigger A:

```
| Jsonrpc: json conversion failed: invalid structured value
| Raised at Jsonrpc__Import.Json.error in file "ocaml-lsp/jsonrpc/src/import.ml", line 22, characters 23-50
| Called from Jsonrpc__Import.Option.map in file "ocaml-lsp/jsonrpc/src/import.ml", line 7, characters 21-26
| Called from Jsonrpc.Packet.t_of_fields in file "ocaml-lsp/jsonrpc/src/jsonrpc.ml", line 264, characters 22-78
| Called from Lsp__Io.Make.read in file "ocaml-lsp/lsp/src/io.ml", line 103, characters 25-58
```

The escaping frames are `Lsp__Io.Make.read` (A, B) and
`Lsp__Io.Make.read_header` (C). We do not know the exact upstream commit of the
bundled ocaml-lsp, so we do not claim which side should catch it.

## Why this is a bug worth fixing

A client error in one request should produce an error response and leave the
session usable. JSON-RPC 2.0 requires a response to every request and restricts
`params` to an object or array, so the expected handling for trigger A is
`-32600` or `-32602`; for trigger B, `-32600 Invalid Request` (a batch-aware
implementation might report two `-32600` errors instead of one). For trigger C
the transport is damaged, so closing the connection is a defensible choice — but
the current behaviour is to neither answer nor close, leaving the process alive
and the client blocked.

Practical impact: a single request can disable every editor feature for the rest
of the session. Trigger A is reachable from real clients — Emacs 29's Eglot
sends `"params": null` for `shutdown` because its JSON-RPC layer encodes nil as
null.

## What we did not establish

- Root cause: we have the escaping exception's own backtrace, not a fix.
- Permanence: observed for 15 s with unread bytes in the pipe; we did not prove
  it can never recover.
- Method independence: `hover` was measured with all four scalar types,
  `shutdown` with `null`, and an unknown method with `null`. A shared decoder
  stack suggests but does not prove that every method is affected.
- Whether the same failure exists in the Wasm build of the language server.

## Related

- [ocaml-lsp#1330](https://github.com/ocaml/ocaml-lsp/issues/1330) reports that
  string `params` reaches an uncaught exception in the shared `jsonrpc`
  library; the fix suggested there is to restrict `Structured` to objects and
  arrays. That is the same raising site as trigger A, but it does not cover the
  product-level behaviour we report here (live process, open stdout, unread
  input, no response, later requests lost).
- [moonbit-docs#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372)
  is a different `moon-lsp` defect: `format-nth` spins at 100% CPU on a valid
  input and prints nothing to stderr. It is not this report.

## Local evidence

- `poc/f11_lsp_scalar_params_deadlock/` — trigger A, 3/3, byte-level transcript
- `poc/f12_lsp_frame_wedge/` — triggers B and C, 3/3, byte-level transcripts
- `findings/codex_lsp_review.md` — independent re-verification
