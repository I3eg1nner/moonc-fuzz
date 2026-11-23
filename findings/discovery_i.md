# Discovery I：aitne 定案与口径修正

## I1 aitne

- clean rebuild：wasm-gc rc0，js rc0；`route.wasm` 413285 bytes，magic 正确
  `00 61 73 6d 01 00 00 00`，是真实产物；
- `new WebAssembly.Module` 失败：
  `local.set[0] expected type (ref 284), found call of type (ref 431)`；
- 同轮 `counter.wasm` 同 validator **valid**，排除 validator 特性假阳性；
- js 产物可执行 rc0；moon 最小 repro 14 行，wasm-gc/js build 均 rc0，
  wasm 产物 3/3 invalid；
- 判定：CONFIRMED invalid module；但构造是 `%identity` 类型擦除 + `Ref[T]`，
  与 415 同根因类，**不列新候选**。见 `candidate_aitne.md`（标题明确“不列新候选”）。

## I2 修正口径

- 失败首错改为“第一行含 Error 的行”；
- test differential 记录包名；修正后 150 包：

```json
{"modules":150,"buildable_both":111,
 "wasm_only":1,"js_only":0,
 "different_codes":1,
 "invalid_artifact":1,
 "test_attempted":61,
 "test_compile_fail":1,
 "differential":1,
 "differential_pkgs":[{"pkg":".mooncakes/Arcelyth/aitne","test":"build/load"}]}
```

旧 H 计数 `103/2/1/3/1` 已修正为 `111/1/0/1/1`；旧首行 `Using cached`
是测量错误。

## I3 下一步

- aitne 同 415 根因，不扩语料找同类；下一步换 oracle 面（运行时输出差分/
  类型导向生成），或先对 `ajson` 的 `4021` 做依赖/版本归因。
- 本轮不 push。
