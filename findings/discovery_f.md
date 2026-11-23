# Discovery F1–F4：分母、失败解释、变异 pilot

Date: 2026-11-23. Pin 不变。

## F1 语料拆分

| 来源 | N | buildable（wasm+js rc0） | 失败主因 |
|---|---:|---:|---|
| third-party：`~/.moon/lib` | 2 | 2 | 无 |
| third-party：`~/.mooncakes` | 0 | 0 | 目录不存在 |
| ours：`poc/`、`oracle_cases/`、`regressions/` | 92 | 19 | 3005/4037 等语料内错误 |
| 合计 | 94 | 21 | — |

**yield 只算 third-party**；ours 是 curated/回归资产，不能当分母。

## F2 3005/4037

原始 stderr：

```text
Error: [3005]
   ╭─[ .../pkg_private_01/pkga/a.mbt:1:1 ]
 1 │ priv fn hidden1() -> Int { 1 }
   ...
Error: failed when checking project

Error: [4037]
   ╭─[ .../pkg_import_01/pkgb/b.mbt:1:20 ]
 1 │ fn use1() -> Int { @pkga.hidden1() }
   ...
Error: failed when checking project
```

- 3005 = 跨包访问私有名字 → **语料内错误**；
- 4037 = 未导入包/未解析 `@pkg` → **语料内错误**，不是依赖解析；
- 69 wasm 失败分桶：3005=45、4037=15、4023=2、4156=2、无码=5；
- 因此“68 不可 build”是 ours 语料问题，不进 yield 分母。
- 唯一 wasm-only：1051（4156，known curated）；唯一 differential：415（known）。

## F3 500 mutant

`scripts/discovery_mutants.sh`，25 templates × 20 =500，结构化替换
（Int→Int64、0→1、1→2、true→false、Float→Double），每 mutant
wasm-gc + js build：

```json
{"mutants":500,"build_ok":470,"wasm_only":0,"js_only":0,
 "both_fail":30,"different_codes":0,"invalid_artifact":0,
 "diff":[]}
```

- 差分密度 **0/500**；
- 30 个两边都失败，均为类型/语法错误，不是差分；
- 无 invalid artifact；
- 未命中候选，不把 1051/415 算新发现。

## F4 结论

500 mutant 里差分密度 0。瓶颈是模板变异空间/third-party 语料密度，不是
“没有缺陷”。third-party 只有 2 个 buildable 包，本轮未对其做 25×2 变异；
这是 F3 的覆盖缺口。
