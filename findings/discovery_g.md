# Discovery G：真实第三方语料与变异 pilot

Date: 2026-11-23. Pin 不变。网络：mooncakes registry 可达。

## G1 语料

在 `/tmp/gcorpus/scratch` 用 `moon search` 按主题搜并 `moon add`；不 vendor 包，仓库只留清单。

`findings/corpus_registry.txt`：**29 个 module@version**（含传递依赖）。
直接 add 9 个主题包；`tonyfettes/encoding@0.3.9` 因 `moon.mod.json`
不再支持而**未 fetched**，如实计入失败。

## G2 第三方扫描

`.mooncakes` 下 31 个 `moon.mod` 目录（含 nested）：

```json
{"modules":31,"attempted":31,
 "buildable_both":21,
 "wasm_only":0,"js_only":0,
 "different_codes":0,"invalid_artifact":0,
 "test_attempted":19,"test_compile_fail":0,
 "differential":0}
```

- 21/31 wasm+js 都 buildable；
- 10 个不可 build，未计入 yield；
- 0 wasm-only / js-only / differential / invalid artifact；
- test 19 个包，compile fail 0。
- 未出现 415/1051。

## G3 第三方变异

每个 module 取首个 `.mbt`，6 类结构化替换，官方 cap **300 mutant**：

```json
{"mutants":300,"build_ok":210,
 "wasm_only":0,"js_only":0,
 "both_fail":90,"different_codes":0,"diff":[]}
```

差分密度 **0/300**。90 个 both-fail 为类型/语法错误，不是差分。

探索性超跑（超 300 的额外样本，不计入正式 300）出现过 1 条
`moonstl/site/bridge` 的 wasm-only `Error [4032]`；未最小化、未按判据核对，
不列为候选。

## G4 结论

第一次真实第三方语料实验：N=31（清单 29 + nested），buildable 21，
官方 300 mutant 差分 **0**。这次 0 是真实第三方代码上的 0，不是模板上的 0。
瓶颈是第三方 buildable 率/差异密度；无候选，不凑 415/1051。
