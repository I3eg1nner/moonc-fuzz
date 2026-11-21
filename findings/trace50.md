> **2026-11-21 更正：本文结论作废（测量假象）。**
> 当时 `coverage_adds`/`edges` 的平台来自 "worker 结束就关队列、只完成 ~57 条
> trace"；修完 drain 与 trace CPU 预算后，同样 50% 采样下完成 189–190 条，
> adds 2,851/2,985、edges 32.6k/31.8k。本文中所有基于 ~1,960（或更低平台）
> 的"无收益/天花板"判断均为测量假象，不得引用。

# Trace 吞吐优先的 10 分钟对拍（50% 采样，4 workers / queue 128 / 256 MiB）

Date: 2026-11-21. 工具链 pin 未改。

| arm | it | adds | new_edges | completed | failed | dropped | baseline | edge_status |
|---|---:|---:|---:|---:|---:|---:|---|---|
| function | 4,409 | 1,988 | 18,476 | 54 | 0 | 68 | complete | ok |
| func-edge | 3,568 | 1,962 | 18,391 | 56 | 0 | 67 | complete | ok |

## 验收：未达标

- 完成率 = completed / (completed+failed+dropped) = 54/122 ≈ **44%**、
  56/123 ≈ **46%**，低于 ≥50% 的验收线；
- `trace_failed=0`，所以失败不是日志上限/超时/collector；**全部损失是
  `dropped`（67–68 条）**，即队列满（`--trace-queue 128` 仍不够）；
- 因此这一轮仍不能判定 platform：`adds` 1,962–1,988 比 20% 采样的
  1,960 只高约 1%，`new_edges` 18.4k 高于 17.2k，但完成率只有 44%，
  且每臂 it 只有 3.5–4.4k（trace 提交把 worker 拖慢）。

## 瓶颈定位

`trace_submit` 在队列满时直接 `dropped`（丢弃），而不是阻塞/背压。把
workers 4、queue 128、单 trace 上限 256 MiB 都加上后，4 个 trace worker
仍追不上 2 个变异 worker 的提交速率，于是丢 67–68 条。**下一步应该做
背压或按 stage 限流，而不是继续加队列**；否则任何 A/B 都在丢候选 trace。

## 边界

- 单 seed、10 分钟；baseline 8 条（complete）；
- 失败原因分类字段在本次运行后加入，本批 `trace_failed=0` 已足以判定
  "损失来自丢弃"；后续运行会带 timeout/too_large/collector 计数；
- 两个臂都未饱和（adds 1.96–1.99k 但完成率不足），不能用这轮做收益结论。
