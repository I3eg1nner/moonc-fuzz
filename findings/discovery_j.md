# Discovery J：签名分桶与 400 包放大

Date: 2026-11-23. Pin 不变。commit 不 push。

## J1 签名桶

归一化规则：去掉函数号/偏移/类型编号，只保留 `opcode|expected<-found|ref/stack`。

| signature | artifacts | packages |
|---|---:|---|
| `local.set\|ref<-ref\|identity` | 5 | 415（1）, `Arcelyth/aitne`（4） |
| `fallthru\|stack2\|extern-wasm-body` | 2 | `mizchi/zlib/component`（2） |

- 415 internal_test：`local.set expected ref, found local.get ref`
- aitne route/anys：`local.set expected ref, found call/struct.get ref`
→ 两者同归一化桶，确认同根因族。
- zlib 的 `mem_store32` extern body 声明 Unit 却 `(result i32)`，仓内自己写的
  WAT 不合法；最小 repro js 也 rc255，**不是可加载差分，不是 candidate**。

## J2 语料与扫描

- registry：386 个 module@version；直接 add 尝试 250，之前一轮 fetched 109，
  其余失败/超时如实计数；
- 扫描 400 个 `.mooncakes` module 目录：

```json
{"modules":400,"attempted":400,
 "buildable_both":281,
 "wasm_only":3,"js_only":3,
 "different_codes":7,
 "invalid_artifact":3,
 "test_attempted":200,
 "test_compile_fail":4,
 "differential":1}
```

- invalid artifacts：aitne 4 个同 identity 桶；zlib/component 2 个 fallthru 桶；
- wasm-only：`bobzhang/ajson` 4021、`KKKIIO/moondark` 4021、`moonbit-community/js-ffi` 4156；
- js-only：`gaato/mttp`、`mizchi/svg/component`、`mizchi/zlib/component`；
- test differential=1；test compile fail 包：`Arcelyth/aitne`、`jaredzhou/libs`、
  `jaredzhou/pony`（含嵌套）；test 名未稳定提取（缺口）。

## J3 结论

- 没有出现不属于 415/aitne identity 桶的**新根因 candidate**；
  zlib fallthru 桶是用户 extern WAT 自身不合法，js 也不通过，排除；
- 静默非法产物密度约 **3/281**（invalid artifact 包/ buildable），
  其中 aitne 与 415 同根因族，不是新发现；
- test differential 仅 1 条，包名/测试名记录不完整，不能升级为 candidate；
- 下一轮：若要继续该面，应做类型导向生成/运行时输出差分；继续加包收益低。
