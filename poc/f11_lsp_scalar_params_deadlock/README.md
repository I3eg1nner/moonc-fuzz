# F11: `moon-lsp` never answers a request whose `params` is a JSON scalar

Pinned: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, `moon-lsp` from the
same toolchain. Host: Linux x86_64.

This is a language-server failure at the JSON-RPC decode layer. If a request
carries `params` as a **JSON scalar** (`null`, a number, a string, or a
boolean), the server raises an uncaught `Jsonrpc` exception out of its stdio
read loop, sends no response, stays alive at ~0% CPU, and stops reading later
requests. Composite params (`{}`, `[]`) and an absent `params` member are
handled correctly — including a proper `-32602` / `-32601` error response.

It is the same escape path as [F12](../f12_lsp_frame_wedge/): an exception
raised while converting a frame escapes `Lsp__Io.Make.read`. F11 and F12 are
therefore reported as **one defect with two entry points** (field-level
conversion here, whole-packet conversion in F12), not as two independent root
causes. What differs is only where the decoder rejects the input.

It is **not** specific to `shutdown` or to any one method: the same request with
`"params": {}` answers immediately while `"params": null` hangs.

## Reproduce

```
cd poc/f11_lsp_scalar_params_deadlock
python3 replay.py hang_null.json 3        # HUNG, cpu 0.0%, alive=True
python3 replay.py ok_object.json 3        # OK: -32602 (params are required)
python3 replay.py ok_omitted.json 3       # OK: -32602
```

`replay.py` starts `~/.moon/bin/moon-lsp --stdio`, sends `initialize`,
`initialized`, then the request from the JSON file, waits for the matching id,
samples `/proc/<pid>/stat` for CPU, and kills the server afterwards.

## Observed matrix

All of these are single requests to the pinned server on a fresh process. The
`hover` rows use `textDocument/hover` with no prior `didOpen`, so a **composite**
`params` is expected to fail validation — the point is that it *answers*.

| payload file | method | `params` | observed |
|---|---|---|---|
| `hang_null.json` | `textDocument/hover` | `null` | **no response**, alive, 0% CPU |
| `hang_number.json` | `textDocument/hover` | `0` | **no response**, alive, 0% CPU |
| `hang_string.json` | `textDocument/hover` | `"x"` | **no response**, alive, 0% CPU |
| `hang_bool.json` | `textDocument/hover` | `true` | **no response**, alive, 0% CPU |
| `ok_object.json` | `textDocument/hover` | `{}` | `-32602` "the following record elements were undefined: position textDocument" |
| `ok_array.json` | `textDocument/hover` | `[]` | `-32602` "list instead of atom for record expected" |
| `ok_omitted.json` | `textDocument/hover` | omitted | `-32602` "params are required" |
| `shutdown_null.json` | `shutdown` | `null` | **no response**, alive, 0% CPU |
| `shutdown_object.json` | `shutdown` | `{}` | `{"result": null}` |
| `unknown_null.json` | `no/such-method` | `null` | **no response**, alive, 0% CPU |
| `unknown_object.json` | `no/such-method` | `{}` | `-32601` "Unknown method" |

The unknown-method row is the sharpest control: with composite params the
dispatcher correctly produces `-32601`, so nothing about the method or the
handler is at issue — only the shape of `params`.

Every `HANG` row was reproduced 3/3 with a fresh server process. The 3 s wall
time is the probe's own wait; a separate manual run waited 15 s with no
response, the process still alive, and a `/proc` CPU delta of one tick over that
window.

## Queue blocking

After a hung request, a later valid request also receives no response. Sending
`shutdown` with `params: null` and then `moonbit-lsp/format-nth` with a
well-formed payload (which answers in under 10 ms on a clean server) produced
two consecutive timeouts. So this is not "one request is ignored": the request
loop stops making progress.

## Why it is a defect

JSON-RPC 2.0 requires a response to every request: either a result or an error
object, and it restricts `params` to an object or an array. The server already
returns `-32602` for unparseable/absent params and `-32601` for an unknown
method, so the correct behaviour for a scalar `params` is one of those — not
silence.

The LSP specification defines `shutdown` with **no** params (not
`"params": null`), so a scalar `params` is a client error rather than something
the spec blesses. It is nonetheless a realistic one: Emacs 29's built-in Eglot
calls `jsonrpc-request` with a nil params value, which its JSON-RPC layer
encodes as JSON `null`. A server that stops serving after one such request is
therefore unreachable for that client.

## What the server reports

`moon-lsp` prints its own uncaught-exception block for this trigger, capturing
the escape path:

```
| Internal error: Uncaught exception.
| Jsonrpc: json conversion failed: invalid structured value
| Raised at Jsonrpc__Import.Json.error in file "ocaml-lsp/jsonrpc/src/import.ml", line 22, characters 23-50
| Called from Jsonrpc__Import.Option.map in file "ocaml-lsp/jsonrpc/src/import.ml", line 7, characters 21-26
| Called from Jsonrpc.Packet.t_of_fields in file "ocaml-lsp/jsonrpc/src/jsonrpc.ml", line 264, characters 22-78
| Called from Lsp__Io.Make.read in file "ocaml-lsp/lsp/src/io.ml", line 103, characters 25-58
| Called from Fiber__Scheduler.exec in file "fiber/src/scheduler.ml", line 73, characters 8-11
```

An earlier revision of this PoC called F11 a "silent" deadlock and used that to
distinguish it from F12. That was wrong: the F11 replay script discarded stderr.
F11 and F12 share the escape path and differ only in which conversion raises.

## Byte-level transcript

`transcript_null.txt` records every byte written and read, with timestamps:
after `initialize` succeeds (1344 bytes returned), the scalar-`params` request
and a following complete `shutdown` both elicit **0 bytes** with
`status=open`, while the process stays alive; stderr carries
`invalid structured value`.

## Scope

- Confirmed: request-level failure for `params` ∈ {`null`, number, string,
  boolean}; composite and omitted `params` are fine.
- Confirmed after a real `didOpen` of a valid file and a successful `hover`:
  the scalar-`params` request still gets no response.
- Observation window: responses are absent and later request bytes stay unread
  for at least 15 s. This is not a proof of permanent failure, only of no
  recovery within the observed window.
- Not tested here: notifications with scalar `params` (no response is expected,
  so a hang is not observable the same way), batch requests, and whether the
  same deadlock exists in the Wasm build of the language server.
- Not claimed: root cause. The reproducible shape and the queue blocking are
  established; the internal reason is not.
- Distinct from [F10](../f10_lsp_format_nth_hang/): F10 spins at 100% CPU inside
  the formatter for one valid input and returns as soon as a trailing newline is
  added, with no exception on stderr. F11 is 0% CPU, method-independent, and
  triggered by the JSON type of `params`.
- Same layer as [F12](../f12_lsp_frame_wedge/): both raise out of
  `Lsp__Io.Make.read`. F11 fails in `Jsonrpc.Packet.t_of_fields` while
  converting `params`; F12 fails in `Jsonrpc.Packet.t_of_yojson` (top-level not
  an object) or in `Lsp__Io.Make.read_header` (BOM).

## Upstream

No matching upstream report was found. Searching the 500 most recent issues of
`moonbitlang/moonbit-docs` for `shutdown`, `params: null`, `scalar params`,
`deadlock` and `never responds` returned no issue describing this shape; the
only open LSP hang is
[#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372), which is F10.
This PoC therefore does not claim an upstream root cause, and it has not been
filed upstream.
