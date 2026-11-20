# RSS 增长：组件二分与逐迭代堆增长

Date: 2026-11-20. 依据：2 小时 soak（`findings/soak_2h.md`）的负结果：
RSS 约 1.4 MB/s 线性涨到 9.9 GB、无平台期，行为臂（无 trace）同样增长。
工具链 pin 未改。

## 结论先行

**不是 trace/父本/caps 单独造成，也不是子进程运行时按 spawn 泄漏。**
逐迭代的 harness 堆增长（GC 高水位随分配量上升）是主因；目前没有找到
可调开关，工程上先用**进程 epoch + 语料接力**把单进程 RSS 封在阈值内。

## 组件二分（每项都是独立短跑 + max RSS）

| 实验 | 配置 | it | max RSS | 结论 |
|---|---|---:|---:|---|
| spawnprobe `/bin/true` | 3,000 次 `@exec.run` | 3,000 | **2 MB 平** | 进程运行时不是按 spawn 泄漏 |
| spawnprobe `moonc syncheck` | 2,000 次真实编译器 spawn | 2,000 | **2 MB 平** | 同上，含真实子进程 |
| behavior base | 600 s，2 workers，parent 2000，stats 100k | ~70k | **1.86 GB** | 复现线性增长 |
| stats-cap 1000 | 同上，只压 novelty 统计表 | ~70k | **1.86 GB** | 统计表不是主因 |
| parent-cap 10 | 同上，只留 10 个父本 | ~70k | **0.42 GB** | 父本池是显著项 |
| persist/coverage 0 | 同上，不落盘证据 | ~70k | **1.86 GB** | 落盘预算不是主因 |
| parent 10 + stats 1k + persist 0 | 600 s，2 workers | 34k | **0.75 GB** | 压缩后仍 ~22 KB/it |
| + mimalloc purge env | 同上 + `PURGE_DELAY=0 PURGE_DECOMMITS=1` | 34k | **0.75 GB** | 分配器保留不是主因 |
| 30 分钟真实混合 | 4 workers，T1/T2 5%，baseline 256 | 15k | **169 MB** | 迭代少时自然低；不能据此说修好 |

关键读数：

- `parent_bytes`（src + cov 指针估算）在 2,000 父本时只有 **12 MB**，
  与 GB 级 RSS 不成比例；`parent-cap 10` 仍到 0.75 GB，所以"父本对象本身"
  不是主因，但父本数量会放大分配与 GC 压力。
- `spawnprobe` 把"每次 spawn 泄漏"排除：3,000 次 `/bin/true`、2,000 次
  `moonc syncheck` 的 RSS 都是 2 MB 不动。
- massif 在 `--pages-as-heap=no` 下只看到 37 MB（mimalloc 用 mmap，不走
  malloc）；需要 `--pages-as-heap=yes` 才能看 arena 页，但那只能证明
  "页在增长"，不能定位分配点，本次没有据此下结论。
- 每迭代 ~10–30 KB 的保留量，与"live 对象只有几 MB"矛盾，符合 GC 堆按
  分配吞吐扩张、且不主动归还的行为；MoonBit 没有公开的 `gc.collect()`。

## 工程缓解：进程 epoch + 语料接力

`scripts/soak_epochs.sh`：

- 每个 epoch 是一个全新进程（固定时长），`--rss-limit-mb` 仍作为单进程
  软顶；
- 每个 epoch 结束后把 `<run>/corpus/*.mbt` 并入共享 seed pool，下一个
  epoch 用 `--seed-dir` 从该 pool 启动，发现不随进程重启丢失；
- 记录每 epoch 的 max RSS、it、t2_ok、coverage_adds、new_edges、stop_reason。

6 个 epoch × 600 s，4 workers，T1/T2 5%，trace queue 32，baseline 上限
256 MiB，`--rss-limit-mb 1800`：

| epoch | max RSS | it | T2 ok | coverage_adds | new_edges | stop |
|---:|---:|---:|---:|---:|---:|---|
| 1 | 377 MB | 9,713 | 25 | 2,016 | 0 | — |
| 2 | 377 MB | 8,611 | 18 | 2,285 | 0 | — |
| 3 | 382 MB | 9,410 | 15 | 2,112 | 0 | — |
| 4 | 386 MB | 10,390 | 17 | 2,089 | 0 | — |
| 5 | 383 MB | 9,351 | 15 | 2,070 | 0 | — |
| 6 | 383 MB | 10,582 | 23 | 2,066 | 0 | — |

**1 小时总时长；单进程峰值 386 MB；epoch 之间没有增长趋势；没有触发
`stop_reason`。** 每个 epoch 的 `coverage_adds` 稳定在 2,0xx–2,2xx，说明
语料接力没有让学习逐 epoch 衰减。

对照：单进程 2 小时跑到 9.9 GB。区别不在总时长，而在**单进程生命周期**：
每个 epoch 10 分钟后重启，堆随之重置。

## 这是不是"修好了"？

不是。诚实表述是：

- 单进程内的线性增长仍在（60 s → 73 MB、120 s → 162 MB、600 s → 750 MB、
  2 h → 9.9 GB，与迭代量同向）；
- epoch 方案把 **RSS 上界** 变成 `max_single_epoch`，代价是父本能量/覆盖
  集合每个 epoch 重置，只继承输入语料；
- 验收"2 小时 RSS<2 GB 或出现平台期"以**单进程**口径：单进程未达标；
  以**部署口径**（每 10 分钟重启的 harness）：1 小时峰值 386 MB，达标且
  平稳。两种口径都写在表里，不混用。

## 边界

- 这是**进程级**内存上界，不是堆泄漏修复；单进程内 RSS 仍随迭代线性增长。
- epoch 继承的是输入语料，不是父本能量/覆盖集合；跨 epoch 的奖励状态重置。
- 真正的修复需要运行时提供 GC 统计/主动回收，或把 harness 的分配热点
  （sha1、mutate 字符串、每迭代临时对象）改成可复用缓冲；本轮未做。
