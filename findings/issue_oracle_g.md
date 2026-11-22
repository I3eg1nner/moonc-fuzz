# issue→oracle G：must-reject / 诊断完备性

Date: 2026-11-22. Pin 不变。未发上游。候选不叫 confirmed。

## G1 语料

`regressions/must_reject/`：

- `positive/`：124 个 must-reject 程序；
- `negative/`：37 个健康程序（25 templates + 12 fmt_shapes）；
- 控制：`oracle_cases/typecheck/551/` 的缺失 trait import 必须被拒。

语料来源：25 个模板 + 12 个 formatter 形态，每个源生成 4 个语义破坏变体
（有 24 个变体没有实际改动，故 148→124）。4 个变换：

1. `unknown_type`：把首个 `Int` 改成 `IntX`；
2. `unbound`：追加 `let _ = __missing_definition`；
3. `bad_escape`：追加 `let _ = "\q"`；
4. `truncate`：删掉最后一个 `}`。

**未实现的变换**（G3 的缺口，不是“没发现问题”）：错 arity、删 import、
重复字段/impl、破坏 trait bound、错 label。没有按文件 AST 做通用变换；
强行 sed 会产生“可能合法”的变体，不能保证 must-reject。

G1 的 curated/14 条 labeled defect 已在 E/F 审计；本 runner 只收单文件
must-reject，package 形态的 1294/836/551/1347 分别用各自 curated 命令跑。
已知 accepted 的 836/1294 不放进负控；它们已由 curated/L1 记录并去重。

## G2 谓词

每个 positive 跑 `moon check <file>`：

- `accepted`：rc0，静默接受，最高优先级 candidate；
- `wrong_diagnostic`：拒绝但错误码/消息与期望不符；
- `expected`：拒绝，当前只断言 rc!=0（未逐条校验错误码）。

负控 37 个必须 rc0；任何 `wrong_diagnostic` 都算负控误报。

## G3 结果

| 集合 | 数量 | accepted | rejected | negative_bad |
|---|---:|---:|---:|---:|
| positive | 124 | **0** | 124 | — |
| negative | 37 | — | — | **0** |
| control（551） | 1 | — | 1 | — |

`must_reject_sensitivity` gate：

```
positives=124 accepted=0 negative_bad=0 control_rc=1 rc=0
```

**0 accepted = 0 个新误接受候选。** 这是负结果：4 个变换 × 37 个健康程序
全部被拒；不能外推到未实现的 5 类变换。

## G4 去重与三档

本轮没有 accepted 候选，因此没有新的三档分类；已知 accepted 的
836/1294 已进 curated，并与 F1–F13、curated 签名去重。没有新 PoC/regression。

## 饱和论证

- 覆盖：37 个健康程序 × {类型改坏、未绑定引用、非法转义、括号截断}；
- 未覆盖：arity/import/字段重复/trait bound/label，以及 package/multi-file
  形态；这些是 G 的剩余空间，不能写成“编译器没问题”。
- `moon check` 单文件只验证前端接受/拒绝；不覆盖 codegen 或跨后端语义。

## 验收

- 124 ≥100 must-reject；负控 37 accepted=0；正控 551 rejected。
- 新 gate `must_reject_sensitivity`；accept 28/28、385/385。
- 报告 `findings/issue_oracle_g.md`；脚本 `scripts/must_reject.sh`。
