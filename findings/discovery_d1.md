# Discovery D1：INVALID_WASM oracle

- pkg lane：`rc!=0 && stderr 含 CompileError && WebAssembly.Module`
  → `kind=INVALID_WASM`，走 `save_pkg_witness` + triage。
- 415 真实 campaign：witness kind=INVALID_WASM，triage confirmed 3/3（已知 issue，只作正控）。
- 语法/类型错误包（compile_error 无 WebAssembly.Module）不生成 INVALID_WASM。
- 干净包不生成 INVALID_WASM。
- sem3 的 compile_error 仍保持旧 inconclusive，未改；D1 只接 pkg lane。

```json
{"ok":1,"positive_kind":"INVALID_WASM","positive_status":"confirmed",
 "syntax_invalid_witness":0,"clean_invalid_witness":0}
```
