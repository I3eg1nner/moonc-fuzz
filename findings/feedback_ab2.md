# 正式 A/B（backpressure 修复后，headroom 指标）

Date: 2026-11-21. 工具链 pin 未改。

## 配置

25% trace CPU（成本曲线选的省点）、50% T1/T2 采样、4 trace workers、
queue 128、256 MiB、2 workers、15 min/run、3 seeds、function vs func-edge。

## 逐 seed（全部 valid：baseline complete、completion 100%）

| arm | seed | it | adds | edges | CPU s | adds/CPU-s | edges/CPU-s | t90 adds | t90 edges | distinct T2 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| function | 1 | 2,855 | 2,594 | 33,405 | 1,590.0 | 1.631 | 21.01 | 421 s | 582 s | 4 |
| function | 7 | 3,186 | 3,140 | 36,865 | 1,570.0 | 2.000 | 23.48 | 349 s | 505 s | 5 |
| function | 2026 | 2,919 | 3,075 | 36,417 | 1,587.0 | 1.938 | 22.95 | 432 s | 554 s | 8 |
| func-edge | 1 | 2,506 | 2,899 | 35,739 | 1,561.7 | 1.856 | 22.88 | 519 s | 622 s | 5 |
| func-edge | 7 | 2,640 | 2,983 | 34,126 | 1,529.5 | 1.950 | 22.31 | 488 s | 559 s | 5 |
| func-edge | 2026 | 2,571 | 3,775 | 41,528 | 1,547.4 | 2.440 | 26.84 | 409 s | 534 s | 7 |

中位数：

| arm | adds | edges | adds/CPU-s | edges/CPU-s | distinct T2 | t90 adds |
|---|---:|---:|---:|---:|---:|---:|
| function | 3,075 | 36,417 | 1.938 | 22.95 | 5 | 421 s |
| func-edge | 2,983 | 35,739 | 1.950 | 22.88 | 5 | 488 s |

## 判读

- **没有可重复的 edge 收益**：adds（-3%）、edges（-2%）、adds/CPU（+0.6%）、
  edges/CPU（-0.3%）都在 seed 方差内（function adds 2,594–3,140；
  func-edge 2,899–3,775，其中 seed 2026 明显偏高）；
- time-to-90% adds：function 421/349/432 s，func-edge 519/488/409 s，
  方向不一致；不能声称 edge 加速或减速；
- 与旧 A/B 的区别：这次 **6/6 baseline complete、completion 100%、
  平台 3,000 adds / 36k edges 有 headroom**，所以这是第一个可以引用其
  "无差异"的反馈实验；但仍只有 3 seeds，不能证明"edge 无效"。

## 边界

- 25% CPU 配置下 adds 与 50% 几乎相同但 edges 略低（见 cost_curve）；
- distinct T2 只有 4–8，样本太小，不能单独作为反馈指标；
- CPU 是 user+sys，跨 3 个并行进程的账本；time-to-90 来自 stats 的
  elapsed_ms（seed 1 有，其他也有）。
