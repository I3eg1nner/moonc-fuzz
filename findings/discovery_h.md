# Discovery H：4032、放大语料、双 oracle

Date: 2026-11-23. Pin 不变。网络可用；未 push 前本地累积。

## H1 4032

`moonstl/site/bridge` 基线 wasm-gc/js 都 rc0。按 G3 的 `Int->Int64` 重新施加到
嵌套 `.mooncakes/moonbit-community/prettyprinter/combinator.mbt` 后，两边仍 rc0。
G3 没有记录被变异的具体文件，4032 很可能是变异命中嵌套依赖后的 collateral，
**不能复现，不列为 candidate**；与 415 非同根因结论不成立/不比较。

## H2 放大

- 30 个关键词 `moon search`；250 个 module 候选；
- 直接 `moon add` 前 151 个：**fetched=109、failed=41**；
- `.mooncakes` 内 232 个 module@version（含传递依赖）；
- 目标 120–200 个 module@version：registry 232 超过，direct fetched 109 略低；
- 未 fetched 不计 buildable。

## H3 双 oracle（150 modules）

```json
{"modules":150,"attempted":150,
 "buildable_both":103,
 "wasm_only":2,"js_only":1,
 "different_codes":3,
 "invalid_artifact":1,
 "test_attempted":71,"test_compile_fail":3,
 "differential":1}
```

- wasm-only：
  - `bobzhang/ajson`：`Error 4021 Value run_async_main not found ... core/async`
  - `KKKIIO/moondark`：首行是 `Using cached ...`，实际错误未提取
- js-only：`gaato/mttp`，首行 cached，实际错误未提取
- invalid artifact：`Arcelyth/aitne` 的 `_build/wasm-gc/.../examples/route/route.wasm`
  被 `WebAssembly.validate` 判 invalid；
- test differential=1，但 G2 summary 未记录包名（**缺口**）；
- 415/1051 未出现。

## H4 结论

- 真实第三方 150 个模块：103 buildable，compile wasm-only 2、js-only 1、
  invalid artifact 1、test differential 1；
- **没有按预注册判据最小化完成的 candidate**；有 3 条未最小化 lead
  (`ajson`、`aitne`、test differential 未命名)；
- 与 G 的 31 包 0/300 相比，放大后出现了差分信号，但不足以称候选；
- 决策数据：150 包 × 双 oracle 不是 0，但候选仍需最小化/根因；若下一轮
  200 包仍无合格 candidate，应换 oracle 面（运行时输出/类型导向生成），
  不再只加包。
