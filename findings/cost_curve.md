# Trace CPU 成本-收益曲线（600 s，seed 1）

Date: 2026-11-21. 工具链 pin 未改。

| trace-cpu | it | adds | edges | completed | failed/deferred | baseline | CPU s | adds/CPU-s | edges/CPU-s |
|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|
| 25% | 2,239 | 2,889 | 29,685 | 196 | 0 | complete | 1,157.3 | **2.496** | 25.65 |
| 50% | 2,422 | 2,851 | 32,593 | 189 | 0 | complete | 1,163.9 | 2.450 | **28.00 |

- 两个配置都 100% 完成、零丢弃，平台都在 2,850–2,900 adds、30k–33k edges，
  远高于旧的 ~1,960；
- 25% 的 `adds/CPU-s` 略高（2.50 vs 2.45），50% 的 `edges/CPU-s` 更高
  （28.0 vs 25.6）；CPU 总量几乎相同，因为 trace worker 是并行开销；
- 结论：**25% 是更省的默认**（相同 adds、略低 edges、略高 it），50% 适合
  以边为主要指标时使用。两者都有 headroom，旧平台不是天花板。

## 边界

- 单 seed、单次；CPU 是 GNU time 的 user+sys，不含 I/O 等待；
- 25% 的 baseline 预算隔离是刚修的（baseline 不参与候选预算），此前 25%
  复测 invalid 是那个 bug；
- 20% 采样未在这轮重测；曲线的形状（25 vs 50）不保证线性。
