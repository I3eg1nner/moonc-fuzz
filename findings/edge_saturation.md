# Edge 轴为什么恒零：cap 饱和，而不是"baseline 覆盖了全部边"

Date: 2026-11-21. 依据：第三轮复核指出 9/9 的 `edge_saturated=true`、
`edge_keys=50000`；本文用带阶段计数的实验给出实测。工具链 pin 未改。

## 结论

`new_edges=0` 是 **`--edge-cap 50000` 在 baseline 阶段就被填满** 的结果。
baseline 的 16 条 trace（8 个 spread seed × T1/T2）联合覆盖了超过 5 万条
TB 边，universe 在约 24 秒时饱和并置 `edge_saturated=true`，此后所有候选边
被拒绝（`edge_refused` 计数），所以 `new_edges` 恒 0。

把 cap 提到 200000 后：

- baseline 到 **65,302** 条边仍未饱和；
- T1 候选 trace 继续新增 **13,255–14,775** 条边；
- T2 候选 trace 在这两轮里新增 **0** 条（T2 trace 数量少，不能据此断言
  T2 永不产生新边）。

## 方法

`cmd/fuzz` 新增按来源的边计数：`edge_new_baseline`、`edge_new_t1`、
`edge_new_t2`、`edge_new_t3`、`edge_at_settle`（U0 settle 时的 universe 大小）
与 `edge_refused`（饱和后被拒绝的 trace 数），并写进 `summary.json` 与每 2 秒
的 `stats.jsonl`。

每次运行 600 s、2 workers、`--trace-t1 20 --trace-t2 20`、`baseline-seeds 8`
（spread）、baseline 日志上限 256 MiB、trace 64 MiB。

## stage × arm 表

| run | edge cap | baseline | edge_at_settle | final edge_keys | saturated | new(baseline/T1/T2/T3) | refused |
|---|---:|---|---:|---:|---|---|---:|
| func50k | 50,000 | complete | 50,000 | 50,000 | **true** | 50,000 / 0 / 0 / 0 | 57 |
| func200k | 200,000 | complete | 65,302 | 78,557 | false | 65,302 / 13,255 / 0 / 0 | 0 |
| funcEdge200k | 200,000 | complete | 65,593 | 80,368 | false | 65,593 / 14,775 / 0 / 0 | 0 |
| deep200k（deep-p 30） | 200,000 | complete | 65,593 | 68,314 | false | 65,593 / 2,721 / 0 / 0 | 0 |

（`funcEdge200k` 第一次运行 baseline incomplete，作废；上表是重跑。）

`func50k` 的 `stats.jsonl` 显示第 12 个采样点（约 24 s）`edge_keys` 已达
50000 且 `edge_saturated=true`——早于 baseline 结束，也早于任何候选奖励。

## 这修正了什么

- 上一版 `findings/p1_feedback.md` 写"baseline 的边集合已覆盖 campaign 边
  universe，候选 trace 没有新增边"，这是**错误归因**：真正的因果是 cap 截断。
- 也因此 function vs func-edge 的 30 分钟 A/B **不能回答 edge 反馈问题**：
  两臂都在 baseline 后进入饱和，测到的是同一个 50000 上限。
- `edge_saturated` 是 sticky 的：一旦置 true，本次 campaign 再也不会把边
  新颖度计入奖励或 `new_edges`。这是有意的成本约束，但必须显式暴露
  （已进 summary/stats），不能把"不可测"报告成"0 新颖度"。

## 确定性正/负控（已补）

`edge axis: new keys counted until the cap, then explicitly degraded`
单测用 cap=4：基线 `{a,b}` 计 2；候选 `{b,c,d}` 计 2（新边 B 被计数）；
universe 到 4 条（未饱和）；下一条新边 `e` 返回 0 并置
`edge_saturated=true`——显式 degraded，不是静默 0。另有断言证明
`new_edges>0` 时父本能量确实增加（奖励路径可达，不是只计数）。

## 仍未做

- 稳定 feature 空间（带 binary/config 身份）与跨 epoch 的边状态恢复目前
  只存 50000 上限内的并集；
- 不在完成上述两项前再做 function vs edge 长跑。
