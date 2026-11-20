# 2 小时有界 soak：外层硬顶 + 自我内存上限

Date: 2026-11-20. 依据：独立评审 P0-3/P1-4；前一轮 30 分钟 soak 的负结果
（RSS 136 MB → 2.67 GB，无平台期）。工具链 pin 未改。

## 目的

上一轮 soak 证明磁盘有界、内存没有。这一轮回答两个问题：

1. 给 harness 加**两层内存顶**后，长跑能否在顶到达时干净停下并留下 summary？
2. 在 2 小时预算内，磁盘、trace、候选证据是否仍然有界？

## 机制

- 外层：`prlimit --as=14 GiB`（内核硬顶，超了进程直接死）；
- 内层：`--rss-limit-mb 12000`，monitor 每 2 秒读 `/proc/$PPID/status`
  的 VmRSS，越线后置 `stop_reason=memory`，fast worker 不再接新任务，
  队列排空后**照常写 summary.json**；
- 监控脚本 `scripts/soak_capped.sh` 每 60 秒记录 RSS、CPU ticks、文件数、
  目录字节、stats 行数、`trace_dropped`。

## 配置

```text
workers=4 duration=7200s mode=mbt body-only seed=7
trace_t1=2% trace_t2=5% trace_t3=0 trace_max_mb=64 trace_workers=1 queue=8
coverage_cap=200 persist_cap=400 parent_cap=2000 edge_cap=50000
RSS_MB=12000 AS_MB=14336
```

## 结果

完整 7200 秒，`rc=0`，`stop_reason=""`（12 GiB 软顶与 14 GiB 硬顶都
没有触发）。121 个采样点：

| elapsed | RSS (MB) | files | bytes | stats lines | trace_dropped |
|---:|---:|---:|---:|---:|---:|
| 0 s | 5 | 2 | 0.2 KB | 0 | 0 |
| 720 s | 854 | 1210 | 15.8 MB | 262 | 95 |
| 1441 s | 1552 | 1210 | 16.0 MB | 529 | 95 |
| 2162 s | 2321 | 1210 | 16.2 MB | 807 | 95 |
| 2882 s | 3031 | 1210 | 16.4 MB | 1080 | 95 |
| 3603 s | 3997 | 1210 | 16.6 MB | 1403 | 95 |
| 4324 s | 5161 | 1210 | 16.8 MB | 1744 | 95 |
| 5044 s | 6331 | 1210 | 17.1 MB | 2084 | 95 |
| 5765 s | 7522 | 1210 | 17.3 MB | 2424 | 95 |
| 6485 s | 8717 | 1210 | 17.5 MB | 2764 | 95 |
| 7206 s | 9899（峰值 9899） | 1210 | 17.7 MB | 3102 | 95 |

最终 summary：

```json
{"it":326421,"t1":326421,"t2":248,"t2_ok":144,
 "trace_completed":697,"trace_failed":207,"trace_dropped":101,
 "coverage_adds":0,"new_edges":18229,
 "coverage_written":200,"coverage_skipped":497,
 "persist_written":402,"persist_skipped":300094,
 "parents_evicted":290438,"parents_protected_forced":0,
 "candidate_witnesses":1,"confirmed_witnesses":0,
 "stop_reason":"","rss_mb":9896,"baseline_state":"incomplete"}
```

## 判读

**磁盘有界，且这次是 2 小时。** 文件数在 12 分钟后就停在 1210，
字节数 15.8 → 17.7 MB（增长全部来自 `stats.jsonl` 本身，3102 行）。trace
共写出多少日志没有单独统计，但单条 64 MiB 的 `fsize` 上限仍然有效
（`trace_failed=207` 主要是 `trace_log_capped`）。

**trace 队列在低采样下没有饱和。** 2 小时的 `trace_dropped` 只从 95 涨到
101，完成 697、失败 207；完成比 69%（10 分钟默认采样时是 22–24%），说明
"丢弃"是短时间高采样下的队列容量问题，不是长跑必然。

**内存仍然线性增长，2 小时到 9.9 GB。** 约 1.4 MB/s，没有平台期；12 GiB
软顶在这轮没有触发。按这个斜率，约 4 小时会碰到 12 GiB，届时
`--rss-limit-mb` 会置 `stop_reason=memory` 并写 summary。该停机路径已在
低顶测试中验证：`--rss-limit-mb 60` 时 294 次迭代后 `stop_reason=memory`，
summary 正常写出。

**覆盖预算在 2 小时内被用满。** `coverage_written=200`（cap 200）、
`coverage_skipped=497`；行为预算更早饱和（`persist_skipped=300094`）。
也就是说长跑的"证据量"不是由运行时长决定，而是由 cap 决定——这是设计
意图，但意味着 2 小时之后的新覆盖不会再落盘。

**覆盖学习仍然是关闭的。** `baseline_state=incomplete`（16 个基线里 6 个
被 64 MiB 日志上限打断），`coverage_adds=0`，`new_edges` 停在 18,229——
和 10 分钟 A/B 的数值相同，全部来自开头。2 小时没有新的函数覆盖。

**一个候选，未确认。** `candidate_witnesses=1`（F3 家族，见
`findings/f3_triage.md`），`confirmed_witnesses=0`，没有新的确认缺陷。

## 边界

- 内存顶是"停止条件"，不是"内存效率"的证明；RSS 仍然随运行时间增长，
  只是被顶住。原因未定位（行为臂在无 trace 时同样增长，见
  `findings/p1_feedback.md`，所以不是覆盖/父本结构单独造成）。
- `prlimit --as` 是逐进程上限；campaign 总量仍要靠容器/cgroup，本机
  cgroup 只读，未能真正建 cgroup。
- 单机、单 pin、单 seed；2 小时是一个预算点，不外推。
