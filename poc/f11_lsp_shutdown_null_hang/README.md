# F11: `moon-lsp` `shutdown` never responds when `params` is `null`

Pinned: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, `moon-lsp` from the
same toolchain. Host: Linux x86_64.

This is a language-server deadlock, distinct from F10. A `shutdown` request
carrying an explicit JSON `null` params value receives **no response**, the
server stays alive at ~0% CPU, and later requests queue behind it forever.
Sending the same request with `params` omitted, or with `{}` / `[]`, returns
`{"result": null}` immediately.

## Reproduce

```
cd poc/f11_lsp_shutdown_null_hang
python3 replay.py hang.json 5          # HUNG ..., server cpu 0.0%, alive=True
python3 replay.py ok_omitted.json 5    # OK: null
python3 replay.py ok_object.json 5     # OK: null
python3 replay.py hang_number.json 5   # HUNG: scalar params also deadlock
```

`replay.py` starts `~/.moon/bin/moon-lsp --stdio`, sends `initialize` and
`initialized`, then the request from the JSON file. It waits for the matching
id, samples `/proc/<pid>/stat` for CPU, and kills the server afterwards.

## Trigger

```json
{"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": null}
```

No project, file or `didOpen` is needed; `initialize` with `rootUri: null` is
enough. The same request with the `params` member omitted is the control.

Observed on the pinned toolchain, fresh process per run:

| Request | Result | Wall time | Server CPU |
|---|---|---|---|
| `hang.json` (`params: null`) | no response, killed after wait | 5.01 s, 5.01 s, 5.01 s | 0.0% in all three |
| `ok_omitted.json` (no `params`) | `{"result": null}` | < 0.01 s | 0% |
| `ok_object.json` (`params: {}`) | `{"result": null}` | < 0.01 s | 0% |
| `hang_number.json` (`params: 0`) | no response | 5.01 s | 0.0% |

A separate manual run waited 15 s for the `null` case: no response, process
alive, `/proc/<pid>/stat` utime+stime delta 1 tick over 15 s (~0% CPU), and a
`textDocument/hover` sent afterwards also received no response. The 3/3
automated run is the one committed here.

## Why it is a defect

`shutdown` is a zero-argument LSP request; clients commonly encode that as
`"params": null` (the shape shown in LSP protocol examples), and the server
accepts the omitted form and the empty-container forms. A compliant or even
merely robust server should answer `null` and then wait for `exit`. Instead the
request is never answered, the handler does not spin (unlike F10), and the
request queue is blocked. In an editor this means shutdown/restart can hang.

## Scope and relation to F10

- New shape: `shutdown` with `params: null` (also scalar `0`); not the
  `format-nth` recursion reported upstream as
  [#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372).
- Not root-caused. The probe only establishes the request shape and the
  reproducible outcome; it does not inspect `moon-lsp` internals.
- The probe's `life-shutdown-null` case reproduces this 3/3 with fresh
  processes. See `findings/lsp_probe.md` for the full matrix.
