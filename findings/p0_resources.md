# P0-3：总资源硬边界与可观测性

Date: 2026-11-20. 依据：`findings/codex_review_6.md`（P0-3）与评审 §5。
工具链 pin 未改。

## 问题

1. `bytefuzz`、`semdiff`、formatter 走 `@exec.run`，没有地址空间上限，
   也没有进程组回收；主 T1/T2 才用 `run_isolated`。
2. `prlimit --as` 是**每进程**虚拟地址上限，不是 campaign 总量；注释里写的
   "whole group" 是错的。
3. QEMU 日志 256 MiB 的检查发生在退出之后：日志可以先写满磁盘再被丢弃。
4. `corpus.append_line` 读全文件再重写，stats 每 2 秒一次 → 随运行时间
   二次 I/O。
5. T3 snapshot 命名只用 `sha1(src).core`；同一 src 的第二个 worker 提交被拒
   后会删掉第一个排队任务仍在用的文件。
6. （实施中发现，评审未提）`--persist-cap` 分支漏了 `i += 2`，传这个参数
   会让参数解析死循环：100% CPU、无子进程、无输出目录。

## 改动

### 统一隔离 runner

- `bytefuzz` 的 `moonc syncheck`、`semdiff` 的 build/run、`fuzz` 里的
  `moonfmt`（含二次格式化）全部改走 `@exec.run_isolated`，带
  `mem_mb` 与 `max_output_bytes`；
- `run_isolated` 新增 `fsize_mb`：通过 `prlimit --fsize` 给出**硬写盘上限**，
  只在"子进程唯一输出就是一个文件"时使用（QEMU 日志），不用于会写构建
  产物的编译器；
- 修正注释：`--as` 是逐进程上限，campaign 总量需要外层 cgroup/容器，
  本仓库不再声称它覆盖进程组总量。

### QEMU 日志：写盘与内存同时封顶

`trace/collect`：

- 以 `max_trace_bytes` 设置 `fsize_mb`，日志写到上限时 QEMU 收到
  `SIGXFSZ`（rc=-25），不会先写满磁盘；
- 达到上限的日志**不读入内存**（避免 256 MiB 字符串）；
- 分类为 `collector_failed`，`failure=trace_log_capped`，不再进入编译器
  结果判定。

实测（30 分钟 soak 的每一行）：

```json
{"stage":"t2","outcome":"collector_failed","rc":-25,
 "failure":"trace_log_capped","trace_bytes":67108864}
```

`rc=-25` 与 `trace_bytes` 恰好 64 MiB 证明上限是硬的，而不是事后检查。

### stats 真 append

`@exec.append_line(path, line)` 用 `sh -c 'printf "%s\n" "$1" >> "$2"'`
实现 O_APPEND（`x/fs` 不提供 append 句柄）；载荷作为位置参数传入，不经过
shell 插值。`stats.jsonl` 与 asyncfuzz 的结果行改用它；`trace_failures.jsonl`
上限 2048 行，保留同步版本，代价有界。

### T3 snapshot 唯一化

snapshot 名改为 `sha1(src|worker|clock).core`，一个任务一个文件；
提交被拒时只删除自己刚写的那个，`trace_cleanup_core` 也只删自己的。

### 参数解析死循环

`--persist-cap` 补 `i += 2`，并用脚本审计了其余所有 `i + 1 <
args.length()` 分支，没有第二处。

## 30 分钟有界 soak

配置（写进 `manifest.json`）：

```text
workers=4 duration=1800s mode=mbt body-only
trace_t1=0.02 trace_t2=0.05 trace_t3=0 trace_max_mb=64 trace_workers=1
coverage_cap=200 persist_cap=400 parent_cap=2000 edge_cap=50000
qemu=/tmp/AFLplusplus/afl-qemu-trace
```

采样：每 60 秒记录 harness 进程 RSS、累计 CPU ticks、输出目录文件数与字节数、
stats 行数、`trace_dropped`。

| elapsed | RSS (MB) | files | bytes | stats lines | trace_dropped |
|---:|---:|---:|---:|---:|---:|
| 0 s | 136 | 813 | 2.1 MB | 24 | 120 |
| 180 s | 418 | 905 | 5.3 MB | 103 | 120 |
| 421 s | 682 | 1018 | 9.3 MB | 187 | 120 |
| 601 s | 901 | 1118 | 12.7 MB | 262 | 120 |
| 842 s | 1078 | 1159 | 14.1 MB | 361 | 120 |
| 1021 s | 1411 | 1159 | 14.2 MB | 458 | 120 |
| 1262 s | 1789 | 1159 | 14.2 MB | 567 | 120 |
| 1442 s | 2132 | 1159 | 14.2 MB | 664 | 120 |
| 1683 s | 2503 | 1159 | 14.3 MB | 772 | 120 |
| 1803 s（结束） | 2669 → 3（退出） | 1160 | 14.3 MB | 804 | 120 |

最终 summary：`it=142795`、`t1=142795`、`t2=213`、`t2_ok=100`、
`crash_events=3`、`candidate_witnesses=1`、`confirmed_witnesses=0`、
`trace_completed=174`、`trace_failed=59`、`trace_dropped=157`、
`trace_bytes=11,526,355,861`（11.5 GB 写入、逐条删除）、
`coverage_written=174`（cap 200）、`persist_written=403`（cap 400）、
`persist_skipped=130781`、`parents_retained=2000`、
`parents_evicted=126772`、`parents_protected_forced=0`、`edge_keys=50000`、
`baseline_state=incomplete`。

**磁盘有界。** 文件数在 842 s 后停在 1159，字节数停在 14.1–14.3 MB，
尽管同一时段 trace 共写入 11.5 GB——QEMU 日志在解析后即删，`fsize` 保证单条
不超过 64 MiB（59 条 `rc=-25 trace_log_capped`）。

**stats 不再二次增长。** 30 分钟 804 行，文件 <1 MB；旧实现每 2 秒重写整文件，
同样时长会反复复制累计到数百 MB 的日志。

**覆盖预算独立。** 行为预算 400 在约 400 个输入后饱和（`persist_skipped`
130,781），覆盖仍写到 174 条（cap 200），证明 P0-2 的预算拆分生效。

**内存仍然没有硬边界——这是本次 soak 的主要负结果。** RSS 从 136 MB 单调
涨到 2.67 GB，约 1.4 MB/s，30 分钟内没有平台期；退出后立即回落到 3 MB。
文件、边集合（50k 上限）、父本池（2000 上限）都已经封顶，所以增长来自
harness 堆上的保留状态或 GC 高水位，而不是磁盘/caps。已加的 `--stats-cap`
（默认 100,000）只封住 novelty 统计表（`inputs`/`sigs`/`diag_families`），
不解释全部增长。剩余选项是外层 cgroup 内存上限或对父本 cov 集/feature 计数
做堆分析，本次没有做，也不声称已封住。

**覆盖学习在这次 soak 中是关闭的。** `baseline_state=incomplete`（16 个基线
里 6 个被日志上限打断），`coverage_adds=0`。所以这次 30 分钟证明的是
"资源边界与保存路径在长跑下成立"，不是"fuzz 有效"。这是上限过紧的直接
后果：64 MiB 的日志上限在本机把 25% 的 trace 判成 capped。

**一个未确认候选。** `findings/t1/OOM/558d85552a72d365/in.mbt`：T1 在 5.6 s
内触发 `Fatal error: out of memory`（rc=-6，2 GiB 上限）。它是 `candidate`
而不是缺陷：既可能是输入导致的真实内存放大，也可能是 2 GiB 限额对该输入
过紧。`confirmed_witnesses=0` 是诚实值。

## 边界

- `fsize` 只用在 QEMU 上；编译器的 stdout/stderr 仍是"退出后截断"，
  真正的流式上限需要自管 pipe 读取循环，本次未做，已在 `p0_resources.md`
  与 `codex_review_6.md` 里保留为开放项。
- `--as` 与 `--fsize` 都是单进程上限；campaign 总量仍依赖外层容器/cgroup。
- `append_line` 每次起一个 shell（约 3 ms）；对每 2 秒一次的 stats 可忽略，
  但不应被放到每迭代路径上。
- 64 MiB 的日志上限在本机把 59/233 条 trace 判成 `trace_log_capped`：这是
  上限过紧的信号，不是缺陷；提高上限或改 collector 属于 P1-1。
- `--stats-cap` 只覆盖 novelty 统计表；父本池的 cov 集与 feature 计数仍在
  内存里，长跑的 RSS 需要 cgroup 或堆分析，见上。
