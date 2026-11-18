# `moon-lsp` stops reading requests after an input decoding exception

> **Filed:** <https://github.com/moonbitlang/moonbit-docs/issues/1376> (2026-11-18).
> The live text is the issue; this file keeps the review trail only.

`moonbitlang/moonbit-compiler` has issues disabled and there is no separate
language-server repository, so I am reporting this here (same path as #1328,
#1372). The behaviour is in `moon-lsp`, not in `moonc` or `core`.

## Summary

After a successful `initialize` / `initialized` exchange, four malformed inputs
leave `moon-lsp` alive but unresponsive over stdio: scalar `params`, a `[1,2]`
body, a `{,}` body, and a UTF-8 BOM before `Content-Length`. In each case the
process stayed alive with stdout open and no output, and two later complete
requests stayed unread in the stdin pipe for 15 s.

## Environment

`moon 0.1.20261104 (940aa18)`, `moonc v0.10.20+65efd5b93`, Linux x86_64.
`moon-lsp` sha256 `5b9f19e9…2f8801d`. The reproductions do not invoke `moonc`,
so this is not a compiler ICE.

## Reproduction

Start `moon-lsp --stdio`, handshake, send one trigger, then a complete request.

| trigger | bytes sent | stderr |
|---|---|---|
| A scalar `params` | `{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":null}` | `invalid structured value` (`Packet.t_of_fields`) |
| B non-object body | `Content-Length: 5\r\n\r\n[1,2]` | `invalid packet` (`Packet.t_of_yojson`) |
| C BOM before header | `\xef\xbb\xbf` + a valid `shutdown` frame | `content length absent` (`Io.Make.read_header`) |
| D invalid JSON body | `Content-Length: 3\r\n\r\n{,}` | `Yojson.Json_error` (lexer) |

```python
import json, os, select, subprocess, time
p = subprocess.Popen([os.path.expanduser("~/.moon/bin/moon-lsp"), "--stdio"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
def raw(b): p.stdin.write(b); p.stdin.flush()
def obj(o):
    b = json.dumps(o).encode(); raw(b"Content-Length: %d\r\n\r\n" % len(b) + b)
def drain(s):
    out, end = b"", time.time() + s
    while time.time() < end:
        if select.select([p.stdout], [], [], 0.05)[0]:
            c = os.read(p.stdout.fileno(), 65536)
            if not c: break
            out += c
    return out
try:
    obj({"jsonrpc":"2.0","id":1,"method":"initialize",
         "params":{"processId":None,"rootUri":None,"capabilities":{}}}); drain(3)
    obj({"jsonrpc":"2.0","method":"initialized","params":{}})
    raw(b"Content-Length: 5\r\n\r\n[1,2]")            # B; swap in A, C or D
    time.sleep(0.1)
    obj({"jsonrpc":"2.0","id":3,"method":"shutdown","params":{}})
    print(len(drain(2)), p.poll() is None)           # 0 True
finally:
    p.kill(); p.wait()
```

## Actual

All four triggers: no response to the trigger, none to the follow-up, process
alive, CPU ~0%, stdout open (`EAGAIN`, not EOF). `FIONREAD` on the pipe showed
**254 bytes** unread — exactly the two follow-up frames — versus 0 before the
trigger and 0 in a control session that answered them.

Controls all answer normally: `params: {}` and `params: []` → `-32602`,
`params` omitted → `-32602 params are required`, unknown method with `{}` →
`-32601`, well-formed `hover` params → `result: null`.

Full stderr for B:

```
| Internal error: Uncaught exception.
| Jsonrpc: json conversion failed: invalid packet
| Called from Jsonrpc.Packet.t_of_yojson in ocaml-lsp/jsonrpc/src/jsonrpc.ml, line 291
| Called from Lsp__Io.Make.read in ocaml-lsp/lsp/src/io.ml, line 103
```

The exceptions are raised at different call sites inside the bundled ocaml-lsp
(`Packet.t_of_fields`, `Packet.t_of_yojson`, the Yojson lexer,
`Io.Make.read_header`), and all four escape `Lsp__Io.Make.read`. So these are
grouped by symptom, not by an established common root cause. I do not know the
bundled dependency revision, so I do not claim which layer should catch it.

## Expected

A → `-32600`/`-32602`; B → `-32600` (batch-aware implementations may report two
errors); D → `-32700`; C → closing the connection is also reasonable. In every
case the session should recover or close, not stay alive with input unread.
JSON-RPC 2.0 requires a response to every request and restricts `params` to an
object or array.

## Additional

- Impact: later requests on the connection got no response during the
  observation window, so editor features using it may stop until restart.
- Trigger A is realistic: Emacs 29 Eglot sends `params: null` for `shutdown`
  ([call](https://github.com/emacs-mirror/emacs/blob/emacs-29/lisp/progmodes/eglot.el#L923),
  [encoding](https://github.com/emacs-mirror/emacs/blob/emacs-29/lisp/jsonrpc.el#L501)).
- #1372 is a different defect (100% CPU spin inside `format-nth`).
  [ocaml-lsp#1330](https://github.com/ocaml/ocaml-lsp/issues/1330) is a related
  precedent — string `params` caused a `missing field error` and the server
  died — but not the same raising site or failure mode.

## Not established

Root cause; recovery after the 15 s window; whether every method is affected
(`hover` was tested with all four scalar types, `shutdown` and an unknown method
with `null`); behaviour of the Wasm build.

<!--
Posting notes — do not paste this block.

- Repository: moonbitlang/moonbit-docs (moonbit-compiler has issues disabled;
  docs has only an ICE template, so it was opened as a blank issue).
- Title: as in the H1 above (65 characters).
- Labels bug / moonbit-lsp could NOT be applied: the label API returns
  403 'Must have admin rights to Repository' for outside reporters. #1372 is
  likewise unlabeled.
-->