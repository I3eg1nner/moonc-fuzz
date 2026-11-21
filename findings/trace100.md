> **2026-11-21 更正：本文结论作废（测量假象）。**
> 当时 `coverage_adds`/`edges` 的平台来自 "worker 结束就关队列、只完成 ~57 条
> trace"；修完 drain 与 trace CPU 预算后，同样 50% 采样下完成 189–190 条，
> adds 2,851/2,985、edges 32.6k/31.8k。本文中所有基于 ~1,960（或更低平台）
> 的"无收益/天花板"判断均为测量假象，不得引用。

# Trace 100% 的 10 分钟对拍：平台没有抬升

Date: 2026-11-21. 工具链 pin 未改。

## 配置

与 edge30 相同（2 workers、cap 200k、baseline 8、父本 500），只把
`--trace-t1/--trace-t2` 从 20 提到 100。

| arm | it | adds | new_edges | trace_completed | failed | dropped | baseline | edge_status |
|---|---:|---:|---:|---:|---:|---:|---|---|
| function | 7,567 | 1,794 | 14,441 | 63 | 25 | 33 | complete | ok |
| func-edge | 7,797 | 1,790 | 13,344 | 49 | 33 | 30 | complete | ok |

对照（20% 采样、30 分钟，edge30 中位）：adds 1,960 / 1,964，edges
17,137 / 17,201，trace_completed 210–240。

## 判读

1. **提高采样率没有抬升平台**：adds 反而低约 8–9%（1,79x vs 1,96x），
   edges 也低。
2. 原因不是"trace 更多"，而是 **完成的 trace 更少**：100% 采样把队列/CPU
   打满，10 分钟只完成 63/49 条（20% 的 30 分钟有 210–240 条），
   failed+dropped 约 58–63。也就是说这次实验把"采样率"和"trace 吞吐"
   混在一起了，**不能**据此证明 1,960 是语言上限。
3. 能确定的是：**单纯把采样率拉到 100% 不是解法**；要抬平台必须先保证
   trace 能完成（更多 trace workers / 更大队列 / 更长日志预算），再比较。
4. 1960 是否等于"75% 可达函数的真实天花板"仍未判定；下一轮应在
   trace 完成率 ≥50% 且队列不丢的前提下重做，或改用 headroom 指标
   （见 `findings/feedback_design.md`）。

## 边界

- 单 seed、10 分钟；baseline 相同；
- trace 失败/丢弃的原因未逐条分类（日志上限 vs 超时）；
- 100% 采样下 T2 尝试只有 ~50 次，样本小。
