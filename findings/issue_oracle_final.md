# Issue corpus → oracle 收尾（I）

Date: 2026-11-22. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. 语料冻结；未发上游；未改 pin。

## 1. 基线与 I1 增量（两列分开，不混）

| 口径 | curated | reproduced | fixed | unclear | L1 | L2 |
|---|---:|---:|---:|---:|---:|---:|
| F 收尾时 | 33 | 12 | 13 | 2（旧口径；612 后归 needs_old_toolchain） | **12/12** | **5/12** |
| I1 新增后 | **38** | **15** | **15** | **4 unclear + 3 needs_old_toolchain(68/45/612) + 1 not_reproducible(875)** | **14/14**（light） | **5/15 = 33.3%** |

F 行三列合计 27/33，其余为 needs_old_toolchain/not_reproducible/待定，均以 `curated.json` 为准；612 不属于 unclear。

I1 的 4 条：

| issue | 结论 | 命令 / rc / 输出 | 资产 |
|---|---|---|---|
| 1051 | **fixed** | 2025 `type I Int` 不再解析；当前 `type I = Int` + extern js，`moon build --target js` rc0 | `oracle_cases/miscompile/1051/` |
| 440 | **fixed** | `moon check --target native` rc0，`Array::make(3, extern_ref)` 通过；link 仍需 C stub，不是编译器缺陷 | `oracle_cases/crash_ice/440/` |
| 415 | **reproduced** | `moon test --target wasm-gc` rc255；`WebAssembly.Module` `local.set` type mismatch | `oracle_cases/miscompile/415/` |
| 1339 | **unclear** | 缺 `moonbit-community/moonplot@38ed2c954` 仓库与 native link 环境；不猜 | `oracle_cases/crash_ice/1339/` |

415 的 L2：seedfuzz test 50 mutants，50 runs，0 同签名，原因 `no_predicate`
（invalid-module 错误不是 judge defect）。

## 2. H/I 覆盖表

| 门禁 | 断言 | 实测 |
|---|---|---|
| `must_reject_sensitivity` | transforms ≥12、positives ≥350 | **14 / 360**；accepted 0、wrong_diagnostic 0、neg 37/0 |
| `attribute_sensitivity` | families ≥8、cases ≥160 | **9 / 160**；expected 140、missing 20（全 836）、extra 0 |

- must-reject 14 类：arity(少)、arity2、arity3、import、pkg_import、pkg_private、
  dupfield、duptrait、traitbound、breaklabel、letassign、match、derive、visibility。
- attribute 9 族：unknown_plain、unknown_dotted、deprecated、two_unknown、
  skip_current、cfg、alias、double、nested。
- 负控：templates 25 + fmt_shapes 12，0 误报；正控 551 缺失 trait import 被拒。
- 20 个 missing 全部是 `unknown_dotted`，与已知 836 去重；不是新候选。

## 3. 候选与去重

- **F13** 仍是唯一新候选（formatter 嵌套一元负号，未 confirmed）；
- 836/1294/1347 是本次资产化的已知诊断/emit 缺陷；
- H/I 的 0 accepted、20 missing 均去重，**0 个新 crash/miscompile**；
- 与 F1–F13、curated 签名去重后无新增。

## 4. 召回

E1 两轮 100 条抽样：labeled 14/100，**pin-validated 8/100 = 8%**；
Wilson 95% CI **4.1%–15.0%**；推算 389 条漏 16–58 条；curated 召回
**30.8%–61.9%**（点估计 45.6%）。这是保守口径，未 pin 的 labeled 不算。

## 5. 残余风险（逐条）

- **旧语法**：68/45/612/1051 等 2023–2025 语法当前 parser 拒绝，需旧工具链；
- **缺最小 repro**：E2 36 条中 30 blocked、6 unclear；不能重建 ≠ 不是 bug；
- **缺依赖**：1175 需 Why3，1339 需 MoonPlot 仓库，moon#2527 需 QRFlux，
  async#732/#725 需并发/FS churn；
- **宿主限制**：1272/1338/1337 需 32-bit，1327/1072 需 LLVM bundle；
- **package/多文件**：H/I 的 package 形态只覆盖 import/visibility/blackbox，
  未覆盖全部 multi-file 语义；
- **attribute 邻域**：cfg/alias/nested 已有 160 例，但 attribute 组合空间远未穷尽；
- **召回区间宽**：18.7–61.9% 级别的剩余不确定性，不能靠“0 新缺陷”消掉。

## 6. 不声称

- 不声称编译器无缺陷；
- 不声称 561 条语料已穷尽或 38 curated 是完整缺陷集；
- 不把 `fixed` 写成 upstream fixed：1328/1326/1155 等仍 open，只有 **pin_expected**；
- 不声称 L1 100% 等于 L2 强；L2 5/15 且多条 no_predicate；
- 不把 H/I 的 20 missing 当新发现（已知 836）；
- 不声称 package/multi-file 或 32-bit/LLVM 已覆盖。

## 7. 验收

```
accept: checks=29 ok=true
moon_test: 386/386
issue_regress: normal 0 / tamper 1
must_reject: positives=360 transforms=14 accepted=0 wrong=0 neg_bad=0 control_rc=1
attribute: cases=160 families=9 expected=140 missing=20 extra=0
issuecheck: reproduced 14/14, fixed 14/14 (heavy 1366/1155 skipped)
```

## 8. 交付

- `findings/issue_oracle_final.md`（本文件）
- `issues/curated.json` 38 条、`issues/l2_results.json`
- `regressions/must_reject_v2/` 360、`regressions/attributes/` 160、
  `regressions/package_seeds/` 3
- `scripts/must_reject.sh`、`scripts/attribute_check.sh`、`cmd/accept`
- 新增资产：1051/440/415/1339、1347、1294/945/447/551/836


> 验收注：本文 F 收尾时 accept 为 35；后续 J1/J2/H/I 增至 35，见 `findings/handoff_final.md`。
