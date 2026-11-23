# Discovery L：合法语义生成与运行时差分

Date: 2026-11-23. Pin 不变。commit 不 push。

## L1 生成器

`scripts/gen_semantic.sh`：12 族，固定确定性断言：

int add/div/mod/shift/bit/mul、string、array、Ref、match、closure、loop；
`%identity` 单独族，仅 50/600 = 8.3%。

```json
{"generated":600,
 "identity_samples":50,
 "build_valid":550,
 "valid_legal":550,
 "invalid_artifact":50,
 "discordant":50}
```

- legal 550/550 build_valid，**valid_rate=100%**（整体 550/600=91.7%）；
- invalid artifact 50，全部 identity 族，单列，不当主指标；
- 无普通编译失败。

## L2 运行时差分

同一程序 `moon test --target js` / wasm-gc，按 test 结果和 `Total tests` 对比：

- discordant=50，全部 identity 族（wasm invalid vs js assertion fail）；
- **legal 550 个 discordant=0**；
- 没有一边通过/一边失败的合法程序；
- 浮点格式化/迭代顺序/随机/时间/地址类输出在生成器里未使用。

## L3 候选

- 合法语义面 0 discordant；
- identity 50 是已知 415/aitne 桶，不是新候选；
- 无最小 repro（没有新候选）；
- 与 curated 去重不适用。

## L4 结论

- 合法程序 valid_rate 100%，legal discordant 0；
- 说明这些语义族在 pin 上 js/wasm-gc 结果一致；
- identity 族仍只复读已知根因；
- 下一步：扩大语义族（运行时输出/类型导向生成），或停这条线；不能把 identity
  50/600 当发现。
