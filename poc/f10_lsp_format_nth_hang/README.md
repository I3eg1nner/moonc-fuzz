# F10: `moon-lsp` `format-nth` hangs at 100% CPU when the last block has no trailing newline

Pinned: `moon 0.1.20261104`, `moonc v0.10.20+65efd5b93`, `moon-lsp` from the
same toolchain. Host: Linux x86_64.

This defect is **not a compiler ICE**. It is a language-server hang: one JSON-RPC
request never returns, the process spins at 100% CPU, and every later request
queues behind it. The CLI formatter (`moon fmt`) formats the same file
correctly, so the defect is specific to the LSP's single-block formatter.

## Reproduce

```
cd poc/f10_lsp_format_nth_hang
python3 replay.py hang.json     # prints: HUNG (no response in 10s)
python3 replay.py ok.json       # prints: OK: {"newText": ...}
```

`replay.py` starts `~/.moon/bin/moon-lsp --stdio`, sends `initialize`, then one
`moonbit-lsp/format-nth` request, and waits 10 s for the matching response id.
It kills the server afterwards either way.

## Trigger

The request body is the whole trigger; no project or open document is needed:

```json
{"content": "fn f() -> Unit {\n  ()\n}", "n": 0, "isMarkdown": false}
```

Adding the trailing newline makes the same request return immediately:

```json
{"content": "fn f() -> Unit {\n  ()\n}\n", "n": 0, "isMarkdown": false}
```

Observed on the pinned toolchain, 3 runs each, fresh process per run:

| Request | Result | Wall time | Server CPU |
|---|---|---|---|
| `hang.json` (no trailing newline) | no response, killed after the 10 s wait | 10.01 s, 10.01 s, 10.01 s | 100% in all three |
| `ok.json` (trailing newline) | formatted block returned | < 0.01 s | 0% |

Both `initialize` handshakes succeeded, so the hang is in request handling, not
in startup. The 100% CPU reading is a point sample from `ps -o %cpu` taken while
the request was outstanding.

This is a hang, not a slow path: the server never answers, and because the
handler is single-threaded every later request is blocked behind it. In VS Code
this is reachable through the "Update test" code lens, which sends
`format-nth` for the edited test block; if that test is the last block and the
file has no final newline, the server stops responding.

## Why it is a defect

A formatter request for a 17-byte, syntactically valid block should return a
formatted block or an error. Spinning forever while holding the request queue is
neither. The input is ordinary valid MoonBit and does not require any malformed
syntax to trigger it.

## Scope

- Confirmed: `format-nth` on the **last** top-level block without a final
  newline. Upstream reports that formatting an earlier block (`n` smaller than
  the last index) works, and that the block contents do not matter.
- Not tested here: other LSP methods, non-final blocks, `isMarkdown: true`,
  CRLF content, empty content, out-of-range `n`. Those are exactly the variants
  a protocol-level probe should cover next; this PoC only pins the one shape.
- Not claimed: root cause. Upstream's stack sample points at `skip_until` /
  `peek_inner` looping without an end-of-input check, but that is their
  inference, not something this repository verified.

## Upstream

Matches open upstream report
[#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372)
(`moon-lsp hangs at 100% CPU in format-nth when the last top-level block has no
trailing newline`), filed 2026-11-15. Reproduced here on the repository's pinned
Linux toolchain; not claimed as a new upstream root cause.
