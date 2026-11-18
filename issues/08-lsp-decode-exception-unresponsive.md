# `moon-lsp` stops reading requests after an input decoding exception

> **Filed:** <https://github.com/moonbitlang/moonbit-docs/issues/1376> (2026-11-18).
> Draft kept here for the review trail; the live text is the issue.

`moonbitlang/moonbit-compiler` has issues disabled, and there is no separate
repository for the language server (`moonbitlang/moonbit-lsp` and the
`vscode` / `language-server` searches under that org return nothing), so I am
reporting this here. The behaviour is in `moon-lsp`, the language server shipped
with the toolchain — not in `moonc` and not in `core`'s library code. Same
reporting path as [#1328](https://github.com/moonbitlang/moonbit-docs/issues/1328)
and [#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372).

## Summary

After a successful `initialize` / `initialized` exchange, malformed input can
leave `moon-lsp` alive but unresponsive over stdio. I reproduced this with four
inputs: scalar `params`, a `[1,2]` body, a `{,}` body, and a UTF-8 BOM before
`Content-Length`. For each, the process stayed alive with stdout open and no
output, and two subsequent complete requests remained unread in the stdin pipe
during a 15-second observation.

The cases are grouped because they produce similar session failures after
input-parsing exceptions. The backtraces identify different decoding stages; a
common root cause has not been established.

## Environment

```
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)
Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

- Host: Linux x86_64.
- `moon-lsp` sha256: `5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d`
  (`~/.moon/bin/moon-lsp`, from the toolchain above).
- These minimal reproductions do not invoke an external `moonc`; this is
  language-server input handling, so it is not a compiler ICE.

## Reproduction

Start `moon-lsp --stdio`, complete the handshake, send one trigger, then a
**complete, well-formed** request. The follow-up request is not answered.

### Trigger A — scalar `params`

```json
{"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": null}
```

`params` may be `null`, a number, a string or a boolean. `{}`, `[]` and an
omitted `params` all get a normal response (`-32602`).

### Trigger B — non-object top-level body

```
Content-Length: 5\r\n\r\n[1,2]
```

`[1,2]` is valid JSON and the declared length matches the body exactly.

### Trigger C — UTF-8 BOM before the header

```
\xef\xbb\xbfContent-Length: 56\r\n\r\n{"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}
```

The body is a complete, valid `shutdown` request, so the BOM is the only
malformed part.

### Trigger D — body that is not valid JSON

```
Content-Length: 3\r\n\r\n{,}
```

The fully framed body `{,}` reproduced this failure. Other malformed JSON
bodies were not exhaustively tested.

### Minimal replay script

Pick one of the four trigger lines. Runs on the pinned toolchain as written.

```python
import json, os, select, subprocess, time

p = subprocess.Popen([os.path.expanduser("~/.moon/bin/moon-lsp"), "--stdio"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE)

def send_raw(b):
    """Send bytes exactly as given (for a complete trigger frame)."""
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
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk:
                break
            out += chunk
    return out

try:
    send_obj({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"processId": None, "rootUri": None, "capabilities": {}}})
    drain(3)
    send_obj({"jsonrpc": "2.0", "method": "initialized", "params": {}})

    send_raw(b"Content-Length: 5\r\n\r\n[1,2]")                        # B
    # send_obj({"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": None})   # A
    # body = b'{"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}'
    # send_raw(b"\xef\xbb\xbf" + b"Content-Length: %d\r\n\r\n" % len(body) + body)           # C
    # send_raw(b"Content-Length: 3\r\n\r\n{,}")                        # D

    time.sleep(0.1)
    send_obj({"jsonrpc": "2.0", "id": 3, "method": "shutdown", "params": {}})
    print("stdout bytes:", len(drain(2)))       # 0
    print("alive:", p.poll() is None)           # True
    r, _, _ = select.select([p.stderr], [], [], 1.0)
    print("stderr:", os.read(p.stderr.fileno(), 4096).decode("utf8", "replace")[:200] if r else "<none>")
finally:
    p.kill()
    p.wait()
```

Observed on the pinned toolchain:

```
stdout bytes: 0
alive: True
stderr: /-----------------------------------------------------------------------
| Internal error: Uncaught exception.
```

## Actual

| trigger | response to trigger | response to follow-up | process | CPU | stdout |
|---|---|---|---|---|---|
| A `params: null` | none | **none** | alive | ~0% | open, not EOF |
| B `[1,2]` | none | **none** | alive | ~0% | open, not EOF |
| C BOM | none | **none** | alive | ~0% | open, not EOF |
| D `{,}` | none | **none** | alive | ~0% | open, not EOF |
| control: `params: {}` | `-32602` | answered | alive | — | — |
| control: `params: []` | `-32602` | answered | alive | — | — |
| control: `params` omitted | `-32602 params are required` | answered | alive | — | — |
| control: unknown method, `{}` | `-32601` | answered | alive | — | — |
| control: well-formed `hover` params | `result: null` | answered | alive | — | — |

For each trigger, a separate 15-second test observed:

- process state `S`, CPU delta 1 tick over 15 s (0 for D);
- last non-blocking read on stdout returned `EAGAIN`, not `b""` — the pipe is
  open, so this is not EOF;
- **254 bytes** — exactly two later complete requests (an 85-byte `shutdown`
  and a 169-byte `moonbit-lsp/format-nth`) — were still unread in the stdin
  pipe. The backlog was 0 before the trigger; with the same two requests sent
  to a control session that answers them, the backlog was also 0. Backlog was
  measured with `FIONREAD` on the pipe (`fcntl.ioctl(fd, termios.FIONREAD, ...)`),
  not by counting what the client wrote.

The session made no observable input-processing progress during the observation
window. That is a bounded statement about 15 seconds, not a proof of permanent
failure. The exception backtrace and the unread follow-up bytes are consistent
with input processing having stopped.

## stderr

Trigger B:

```
/-----------------------------------------------------------------------
| Internal error: Uncaught exception.
| Jsonrpc: json conversion failed: invalid packet
| Raised at Jsonrpc__Import.Json.error in file "ocaml-lsp/jsonrpc/src/import.ml", line 22, characters 23-50
| Called from Jsonrpc.Packet.t_of_yojson in file "ocaml-lsp/jsonrpc/src/jsonrpc.ml", line 291, characters 15-47
| Called from Lsp__Io.Make.read in file "ocaml-lsp/lsp/src/io.ml", line 103, characters 25-58
| Called from Fiber__Scheduler.exec in file "fiber/src/scheduler.ml", line 73, characters 8-11
```

Trigger A:

```
| Jsonrpc: json conversion failed: invalid structured value
| Raised at Jsonrpc__Import.Json.error in file "ocaml-lsp/jsonrpc/src/import.ml", line 22, characters 23-50
| Called from Jsonrpc__Import.Option.map in file "ocaml-lsp/jsonrpc/src/import.ml", line 7, characters 21-26
| Called from Jsonrpc.Packet.t_of_fields in file "ocaml-lsp/jsonrpc/src/jsonrpc.ml", line 264, characters 22-78
| Called from Lsp__Io.Make.read in file "ocaml-lsp/lsp/src/io.ml", line 103, characters 25-58
```

Trigger D:

```
| Yojson.Json_error("Line 1, bytes 1-3:\nExpected string or identifier but found ',}'")
| Raised at Yojson.json_error in file "common.ml", line 5, characters 19-39
| Called from Yojson.Safe.__ocaml_lex_read_json_rec in file "lib/read.mll", line 234, characters 38-57
```

Trigger C:

```
| Error: content length absent
| Raised at Lsp_fiber__Fiber_io.Io.raise in file "ocaml-lsp/lsp-fiber/src/fiber_io.ml", line 12, characters 22-31
| Called from Lsp__Io.Make.read_header.(fun) in file "ocaml-lsp/lsp/src/io.ml", line 86, characters 15-55
```

The backtraces pass through bundled ocaml-lsp components: `Io.Make.read` for
A, B and D; `Io.Make.read_header` for C. The exception is raised at different
call sites (the `Raised at` line), and the bundled dependency revision is not
known to me, so I do not claim which layer should catch it.

## Expected

- A: return an appropriate request/parameter error (`-32600` or `-32602`);
- B: report an invalid request (`-32600`; a batch-aware implementation might
  report two `-32600` errors instead of one);
- D: return `-32700 Parse error`;
- C: the transport is damaged, so explicitly closing the connection is also
  reasonable.

In every case the session should either recover or be closed, rather than
staying alive with input unread. JSON-RPC 2.0 requires a response to every
request and restricts `params` to an object or array.

## Additional

Practical impact: subsequent requests on the affected stdio connection received
no responses during the observation window, so editor features using that
connection may stop working until the server is restarted.

A real-client example of trigger A's input shape: Emacs 29's Eglot calls
`jsonrpc-request` with a nil params value for `shutdown`, and its JSON-RPC layer
encodes nil as JSON `null`
([call](https://github.com/emacs-mirror/emacs/blob/emacs-29/lisp/progmodes/eglot.el#L923),
[encoding](https://github.com/emacs-mirror/emacs/blob/emacs-29/lisp/jsonrpc.el#L501)).
That demonstrates a real-client input shape; it does not establish how often the
failure occurs during normal editing.

Related reports:

- [#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372) is a
  different `moon-lsp` defect: `format-nth` spins at 100% CPU on a valid input.
  That happens inside the formatter; this report is about input decoding and
  shows ~0% CPU.
- [ocaml-lsp#1330](https://github.com/ocaml/ocaml-lsp/issues/1330) is a related
  historical report: string `params` to `ocamllsp/switchImplIntf` caused an
  uncaught `Jsonrpc: json conversion failed: missing field error` and the server
  died; its discussion recommends array params and clearer documentation. It
  does not establish the same raising site or the same failure mode as this
  report, where the process stays alive.

## What I did not establish

- Root cause. The escaping exception's own backtrace is quoted above; no fix is
  proposed.
- Permanence. Observed for 15 s with unread bytes in the pipe; recovery beyond
  that window was not tested.
- Method independence. `hover` was measured with all four scalar types,
  `shutdown` with `null`, and an unknown method with `null`; a shared decoder
  suggests but does not prove that every method is affected.
- Whether the Wasm build of the language server behaves the same way.

<!--
Posting notes — do not paste this block.

- Repository: moonbitlang/moonbit-docs (moonbit-compiler has issues disabled;
  docs has only an ICE template, so open a blank issue).
- Title: as in the H1 above (65 characters).
- Labels: bug, moonbit-lsp. Do not add ICE, and do not add PRIO:* labels.
- Inline the reproduction; #1372 also keeps its script in the body. Byte-level
  transcripts are available in the reporter's repository if asked for.
- Expected codes are per JSON-RPC 2.0: invalid JSON body -> -32700; invalid
  request shape -> -32600; invalid method params -> -32602.
-->
