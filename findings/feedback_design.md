# 下一轮反馈实验设计（先确认 headroom，再跑）

Date: 2026-11-21. 工具链 pin 未改。

## 前置条件（缺一不跑）

1. `baseline_state=complete`，否则该 arm 直接 invalid；
2. `edge_status=ok`（不允许 degraded_cap）；
3. **trace 采样充足**：记录 `trace_completed`、候选 trace 数、`trace_failed`、
   `trace_dropped`；候选 trace 完成率 <50% 时该 arm 不进入收益统计；
4. **主指标未饱和**：adds/edges 在运行结束前 80% 已到顶 → benchstat 判
   invalid（已实现）。

## 指标（有 headroom 优先）

| 指标 | 定义 | 为什么有 headroom |
|---|---|---|
| distinct T2 成功输入 | 唯一 `src` 且 T2 rc=0 的集合大小 | 300 s 只有几十次 T2，远未到顶 |
| distinct T3 matched | deep lane 全局去重（`deep_t3_distinct_global`） | 每源一次，未饱和 |
| 未在 baseline 的 (func,edge) 组合 | `coverage_adds` 的细粒度版本（按 key 分开） | 当前只到 75% 可达集 |
| time-to-threshold | 达到固定新增（如 500 新函数）所需秒数 | 不依赖最终平台值 |

不使用 `coverage_adds` 终值作为唯一主指标：六份 30 分钟数据已证明它在
t90≈2.5 min 后饱和。

## 实验形状

- 2 臂（function / func-edge）× 3 seeds，30 min，2 workers；
- trace 采样率按 `findings/trace100.md` 的结论选择（若 100% 抬升平台则用高
  采样，否则保持 20% 并接受 adds 只作辅助）；
- 每 seed 批次串行（3 臂并行已验证会压垮 trace 基线）；
- 开跑前先用 2 分钟 smoke 检查 `baseline_state`、`edge_status`、候选 trace
  完成率是否满足前置条件。

## 判读规则

- 先看前置条件；任何 arm 不满足 → 整轮 invalid，不给收益结论；
- 对 headroom 指标报告中位数、范围与 time-to-threshold；不引用饱和后的
  `coverage_adds` 差值；
- 若 edge 奖励在 headroom 指标上仍无差异，才可写"未观察到收益"；不能写
  "edge 无效"。
