---
repo: moonbitlang/moonbit-docs
template: blank issue (the only template is ICE; this is not an ICE)
title: "moon-lsp: exception while decoding an input JSON-RPC frame escapes Lsp__Io.Make.read, server stays alive at 0% CPU and stops reading requests"
labels: [bug, moonbit-lsp]
state: draft, not filed
toolchain: moon 0.1.20261104 (940aa18), moonc v0.10.20+65efd5b93, moonrun 0.1.20261104
host: Linux x86_64
moon_lsp_sha256: 5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d
upstream_duplicate_check: 2026-11-18, no matching report; #1372 is a different moon-lsp defect
---

> Channel notes (not part of the issue body): `moonbitlang/moonbit-compiler` has
> `has_issues=false`, and `moonbit-docs` has exactly one template (`ice.md`),
> so this goes in as a **blank issue**. The `moonbit-lsp` label exists and has
> been used for LSP reports (#1046). Precedent: #1372, #912, #1240. Do **not**
> add the `ICE` label.

# `moon-lsp`: exception while decoding an input JSON-RPC frame escapes `Lsp__Io.Make.read`, server stays alive at 0% CPU and stops reading requests

Four request shapes make `moon-lsp` stop serving. In both cases the server stays
alive at ~0% CPU, keeps stdout open, sends no response, and **never reads later
requests** — their bytes stay unread in the stdin pipe. The server prints an
uncaught-exception block to stderr naming the same escape path in both cases.

They are reported together because the mechanism is the same (an exception
raised while decoding an input frame escapes `Lsp__Io.Make.read`); only the
raise site differs. All four were reproduced 3/3 in fresh processes, and in
every case a complete, well-formed request sent afterwards was never read.

| trigger | stderr |
|---|---|
| request whose `params` is a JSON scalar | `Jsonrpc: json conversion failed: invalid structured value`, raised in `Jsonrpc.Packet.t_of_fields` |
| frame whose top-level JSON value is not an object (e.g. `[1,2]`) | `Jsonrpc: json conversion failed: invalid packet`, raised in `Jsonrpc.Packet.t_of_yojson` |
| frame whose body is not valid JSON at all (e.g. `{,}`) | `Yojson.Json_error(...)`, raised inside `Yojson.Safe.__ocaml_lex_read_json_rec` |

A third, related shape fails one layer earlier, in header parsing: a UTF-8 BOM
before `Content-Length` raises `Error: content length absent` in
`Lsp__Io.Make.read_header`, with the same outcome.

## Environment

```
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)
Feature flags enabled: rr_moon_mod, rr_moon_pkg
```

- Host: Linux x86_64.
- `moon-lsp` sha256: `5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d`
  (`~/.moon/bin/moon-lsp`, from the toolchain above).
- This is **not** an ICE and not a `moonc` crash: `moonc` is not involved in any
  of the three triggers.

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

### Trigger D — body that is not valid JSON

```
Content-Length: 3\r\n\r\n{,}
```

Any malformed JSON body behaves the same way; `{,}` is only the shortest one we
tried. This is the most obvious bad-input case and it is the one a client bug is
most likely to produce.

### Trigger C — BOM before the header

```
\xef\xbb\xbfContent-Length: 63\r\n\r\n{"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}
```

### Minimal replay script

```python
import json, os, select, subprocess, time

p = subprocess.Popen([os.path.expanduser("~/.moon/bin/moon-lsp"), "--stdio"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE)

def send_raw(b):
    """Send bytes exactly as given (used for the trigger frame)."""
    p.stdin.write(b)
    p.stdin.flush()

def send_obj(obj):
    """Frame a JSON value as one complete request."""
    b = json.dumps(obj).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b)
    p.stdin.flush()

def drain(seconds):
    out, end = b"", time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.05)
        if r:
            out += os.read(p.stdout.fileno(), 65536)
    return out

send_obj({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"processId": None, "rootUri": None, "capabilities": {}}})
drain(3)
send_obj({"jsonrpc": "2.0", "method": "initialized", "params": {}})

# trigger: pick ONE of the three
send_raw(b"Content-Length: 5\r\n\r\n[1,2]")      # B: non-object body
# send_obj({"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": None})  # A
# send_raw(b"\xef\xbb\xbf" + b"Content-Length: 63\r\n\r\n" + b'{"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}')  # C

time.sleep(0.1)
send_obj({"jsonrpc": "2.0", "id": 3, "method": "shutdown", "params": {}})  # healthy follow-up
print("stdout bytes:", len(drain(2)))     # 0
print("alive:", p.poll() is None)         # True
print("stderr:", p.stderr.read1(4096).decode("utf8", "replace")[:200])
p.kill()
```

Observed: `stdout bytes: 0`, `alive: True`, and stderr begins with
`| Internal error: Uncaught exception.`

## Observed

Fresh process per run; published toolchain and binary:

| trigger | response to trigger | response to later complete request | process | CPU | stdout |
|---|---|---|---|---|---|
| A `params: null` | none | **none** | alive | ~0% | open, not EOF |
| B `[1,2]` | none | **none** | alive | ~0% | open, not EOF |
| C BOM | none | **none** | alive | ~0% | open, not EOF |
| D body `{,}` | none | **none** | alive | ~0% | open, not EOF |
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
