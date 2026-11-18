# F12: `moon-lsp` input loop wedges permanently on an unparsable frame

**Status:** confirmed 3/3 in fresh processes; *not root-caused*.
**Toolchain:** `moon 0.1.20261104 (940aa18 2026-11-04)`,
`moon-lsp` sha256 `5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d`.
**Surface:** `moon-lsp --stdio`, JSON-RPC 2.0 with `Content-Length` framing.

## Shape

After a successful `initialize`, a single frame that the server cannot decode
kills its request processing:

1. the trigger request is never answered (and, for the BOM/array triggers,
   never parsed into a JSON-RPC request at all);
2. a **later, complete, well-formed request (id 3) is also never answered**;
3. the process stays alive at **0% CPU** with stdout still open;
4. stderr gets an `Internal error: Uncaught exception.` block, e.g.
   `Yojson.Json_error(...)` for the BOM or
   `Jsonrpc: json conversion failed: invalid packet` for the array.

This is not a temporary stall while waiting for bytes: the declared body was
fully sent, and the follow-up frame is complete. The connection is unusable
until the client kills the server, but the server gives no EOF or error.

## Minimal triggers

| mode | bytes sent (after `initialize`/`initialized`) | request answered? |
|---|---|---|
| `bom` | `EF BB BF` + a valid `shutdown` frame (id 2) | no, and id 3 never |
| `array` | `Content-Length: 5\r\n\r\n[1,2]` | no, and id 3 never |
| `control` | a valid `shutdown` frame (id 2) | id 2 **and** id 3 |

`[1,2]` is valid JSON but not a JSON-RPC object; a conforming server should
answer `-32600 Invalid Request`. A UTF-8 BOM before the first header is a
common client encoding mistake. Neither should make the session unrecoverable.

The exact byte sequences are committed as `payloads/bom.bin`,
`payloads/array.bin` and `payloads/control.bin`.

## Reproduce

```sh
cd poc/f12_lsp_frame_wedge
python3 replay.py control   # CONTROL_OK, ids [2, 3]
python3 replay.py bom       # WEDGED, no ids, alive, stderr Internal error
python3 replay.py array     # WEDGED, no ids, alive, stderr Internal error
```

`replay.py` starts a fresh `moon-lsp --stdio`, sends `initialize` (id 1), sends
the trigger, then 50 ms later a complete `shutdown` (id 3), reads for 2 s, and
always SIGKILLs and reaps the server. It reads the raw pipe with `os.read()`,
not buffered `readline()`, so a second response cannot hide in a user-space
buffer. It exits 0 only when the mode behaves as documented.

## Evidence (3/3 each, fresh process)

See `evidence.txt`; summarized:

| mode | run 1 | run 2 | run 3 |
|---|---|---|---|
| control | CONTROL_OK, ids 2,3 | CONTROL_OK | CONTROL_OK |
| bom | WEDGED, 0% CPU | WEDGED | WEDGED |
| array | WEDGED, 0% CPU | WEDGED | WEDGED |

Every wedged run: `init_ok=true`, `alive=true`, `ids=[]`, `server_cpu_pct=0.0`,
`stderr="Internal error: Uncaught exception."`. The control run answers both
requests with `{"result": null}`, so the harness itself can observe responses
that arrive together.

## Relation to earlier work

`findings/lsp_probe.md` (main `f2a87ce`) already recorded that malformed JSON,
a bad `Content-Length`, a missing header and an undersized length produce
silence (HANG, 0% CPU) in a single request. F12 does not claim those payloads
as new. It adds:

- new transport triggers: UTF-8 BOM, valid JSON that is not an object
  (`array`, `number`, `string`, `null`), empty body, missing/typo'd
  `Content-Length`, and a stray blank line before the next header;
- the missing **permanence** proof: every trigger is followed by a complete
  request id 3, which is never processed (3/3);
- stderr evidence (`Internal error: Uncaught exception.`) distinguishing this
  from F11, which deadlocks silently on scalar `params` at 0% CPU.

F10 (`format-nth` spin at 100% CPU) and F11 (scalar `params` deadlock) are
unrelated and are excluded from this PoC.

## What the server itself reports

`moon-lsp` prints an uncaught-exception block to stderr, and the toolchain
ships that binary with OCaml symbols, so the escaping exception is identifiable
without debugging. Captured verbatim for the `array` trigger
(`Content-Length: 5\r\n\r\n[1,2]`):

```
/-----------------------------------------------------------------------
| Internal error: Uncaught exception.
| Jsonrpc: json conversion failed: invalid packet
| Raised at Jsonrpc__Import.Json.error in file "ocaml-lsp/jsonrpc/src/import.ml", line 22, characters 23-50
| Called from Jsonrpc.Packet.t_of_yojson in file "ocaml-lsp/jsonrpc/src/jsonrpc.ml", line 291, characters 15-47
| Called from Lsp__Io.Make.read in file "ocaml-lsp/lsp/src/io.ml", line 103, characters 25-58
| Called from Fiber__Scheduler.exec in file "fiber/src/scheduler.ml", line 73, characters 8-11
```

The frame that raises is `Lsp__Io.Make.read` — the stdio read loop — so the
exception unwinds out of request processing entirely. That matches the observed
behaviour: stdout stays **open but silent** (a non-blocking read returns no
bytes rather than EOF, verified separately), the process stays alive at ~0%
CPU, and later complete requests are never read.

The `bom` trigger raises the same class one layer earlier, in Yojson
(`Yojson.Json_error(...)`) instead of `Jsonrpc` conversion.

## Root cause

Not established by inspection of the binary, and this repository does not claim
one. What is established is the escaping exception's own backtrace (above),
which points at the read loop rather than at any request handler: decoding a
frame whose top-level JSON value is not an object raises, and nothing between
`Lsp__Io.Make.read` and the scheduler catches it. A defensive fix would be to
answer `-32700`/`-32600` and continue reading; the PoC does not verify that such
a fix exists or works.

## Limitations

- Curated triggers, not random fuzzing.
- 2 s wall-clock observation window; a response after 2 s would be missed.
- One toolchain and one `moon-lsp` binary.
- No packet capture of the server's stdout beyond Content-Length frames.
