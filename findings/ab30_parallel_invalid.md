# 无效批次记录：9 路并行 30 分钟 A/B

Date: 2026-11-21. 工具链 pin 未改。

`scripts/bench_ab_30m.sh` 一次启动 9 个 30 分钟 campaign（3 臂 × 3 seed，
每个 2 workers + 2 trace workers）。结果：**6/9 的 `baseline_state=incomplete`**，
只有 `function s1` 与 `deep s7` 完成。

| arm | seed | it | t2_ok | adds | edges | baseline |
|---|---|---:|---:|---:|---:|---|
| function | 1 | 14,219 | 13 | 1,893 | 0 | complete |
| function | 7 | 94,234 | 250 | 0 | 472 | incomplete |
| function | 2026 | 84,173 | 130 | 0 | 600 | incomplete |
| func-edge | 1 | 88,136 | 129 | 0 | 0 | incomplete |
| func-edge | 7 | 85,222 | 116 | 0 | 3,882 | incomplete |
| func-edge | 2026 | 90,703 | 220 | 0 | 2,088 | incomplete |
| deep | 1 | 103,536 | 748 | 0 | 548 | incomplete |
| deep | 7 | 18,228 | 1,343 | 1,955 | 0 | complete |
| deep | 2026 | 110,794 | 760 | 0 | 6,477 | incomplete |

判读（仅作为批次失效原因，不作反馈结论）：

- 18 个 trace worker 同时解析 64–256 MiB 日志，baseline 的 16 条 trace
  在 30 分钟内没有全部完成；baseline 不完整时学习关闭，`adds=0` 是后果，
  不是发现。
- 完成的两条 run 反而说明单进程路径可用（`deep s7` 98% T2 成功率）。
- 因此这 9 条数据不能用于"function vs adding edge vs deep"的比较；重跑改为
  **seed 主序、每批 3 臂并行**（`scripts/bench_ab_30m_seq.sh`），把 trace
  并发从 18 降到 6。

这份记录保留下来，是因为"并行度过高导致 baseline 失败"本身是可复现的
运行约束；后续任何多臂实验都应先检查 `baseline_state`。
