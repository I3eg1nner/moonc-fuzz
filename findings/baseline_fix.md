# Baseline 完整性：让 coverage learning 真正开启

Date: 2026-11-20. 依据：2 小时 soak 的负结果
（`baseline_state=incomplete`、`coverage_adds=0`、`new_edges` 停在 18,229）。
工具链 pin 未改。

## 根因（三条，不是"64 MiB 上限"一条）

1. **baseline 与候选共用一个日志上限**：真实 seed 的 trace 日志明显大于
   64 MiB，被 `fsize` 截断后 `collector_failed`，`baseline_failed` 增长；
2. **baseline 任务和候选抢同一个有界队列**：启动时 16 个 baseline 同时提交，
   `trace_queue` 只有 8/32，超出的直接计为 `baseline_failed`——这一条在
   2 小时 soak 里贡献了和日志上限一样多的失败；
3. **fast worker 不等 baseline**：U0 还没冻结就开始变异，运行结束时队列里
   仍有 baseline 任务，被 `trace_drop_remaining` 记成失败。

4. **（读数修正）baseline 集合从未写进 `by_key`**：即使 U0 complete，候选
   trace 的第一次 delta 也是相对空集合，`coverage_adds` 被高估、奖励发给了
   只是复现 seed 覆盖的输入。

## 改动

- `--baseline-trace-max-mb`（默认 256）：baseline 任务用自己的上限，
  候选仍用 `--trace-max-mb`；
- baseline 任务绕过队列容量检查（U0 必须在 campaign 前全部入队，队列随后
  被排空）；
- fast worker 在 `baseline_settled` 之前等待，不再与 baseline 竞争；
- baseline 的每个 `(stage|outcome|config)` 函数集记入 `baseline_by_key`，
  U0 settle 时并入 `by_key`；novelty 从此只算"超出 seed 的新函数"；
- `--trace-t1/--trace-t2/--trace-t3/--p-deep/--p-run/--trace-cpu` 改为严格
  整数百分数：非法值（如 `0.02`）打印错误并以 **2** 退出，不再静默回落默认。

## 结果

**验收运行**：30 分钟、4 fast workers、T1 5% / T2 5%、trace_queue 32、
baseline 上限 256 MiB、候选上限 64 MiB。

| 指标 | 值 |
|---|---|
| baseline_state | **complete** |
| baseline done/failed/expected | 16 / 0 / 16 |
| it | 14,970 |
| T2 / T2 ok | 149 / 17 |
| trace completed / failed / dropped | 199 / 38 / 94 |
| **coverage_adds** | **2,439** |
| new_edges（候选新增） | 0 |
| coverage_written / skipped | 191 / 0 |
| parents / parent_bytes | 2,000 / 12.0 MB |
| RSS（结束时） | **169 MB** |
| candidate_witnesses | 0 |

对照：修复前同一口径的 30 分钟运行（`baseline_state=incomplete`）里
`coverage_adds=0`、`new_edges` 停在 baseline 值；2 小时 soak 同样为 0。

**关于 `new_edges=0`**：边 universe 对**所有**完整 trace（含 baseline）更新，
16 条 seed trace 已经把可达边集合覆盖掉大部分；30 分钟内候选没有再引入新边。
这与 `coverage_adds=2439` 不矛盾：函数计数按 `(stage|outcome|config)` 分键，
候选确实走到了 seed 没覆盖的函数；边是更宽的全映射 scope，更容易饱和。

## 判读

- **coverage learning 现在真的开着**：U0 完整、函数 novelty 非零、奖励路径
  走的是 `trace_apply_delta` 而不是空集合。验收条件
  "30 分钟 baseline_state=complete 且稳态 coverage_adds>0" 满足。
- **第 4 条读数修正很重要**：如果不把 baseline 集合写进 `by_key`，修复后的
  运行会报出 2,164 的"新函数"，但那是把 seed 覆盖当新颖度。现在 2,439 是
  超出 seed union 的真实增量（同一 30 分钟口径，数值相近但语义不同；
  这次是正确口径下的结果）。
- **RSS 反而低**（169 MB）：这次 30 分钟只有 14,970 次迭代（trace 处理
  占用了不少 CPU），比 2 小时 soak 的 326,421 次少了 20 倍。它说明 RSS 与
  迭代量强相关，而不是与 wall time 相关；也再次排除了"父本池是主因"
  （parents 2,000 只占 12 MB）。
- **边 novelty 为 0 值得单列**：函数学习打开了，边学习在这组 seed 上已饱和；
  下一步要么换更"边多样"的输入面，要么把边奖励去掉以免制造噪声。

## 边界

- 单 seed、单 pin、单机；30 分钟是一个预算点。
- `coverage_adds` 仍按配置键分别累计，跨键不可直接相加解释。
- baseline 上限 256 MiB 是实测够用（16/16 完成），不是理论上限；日志仍可能
  有更大的 seed 需要提高该值。
