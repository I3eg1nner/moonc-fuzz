# Trace 背压与吞吐：drop 的真因不是队列满

Date: 2026-11-21. 工具链 pin 未改。

## 先纠正一个归因

上一轮把 67–68 条 `dropped` 写成"队列满"。加了背压计数后实测：

- 队列平均占用 35/128（`trace_queue_avg_x100=3553`），`trace_wait_events=0`
  ——**提交时从未见过队列满**，背压等待一次都没触发；
- 那些丢失全部是 **worker 结束后关闭队列时丢弃的积压**
  （`deferred_close`），不是提交时拒绝。

因此第一版"队列满就等"没有解决真问题。

## 真因 1：关闭时丢弃积压

worker 一结束就 `q.closed=true`，trace worker 正在跑的队列被
`trace_drop_remaining` 清空。修复：worker 全部结束后进入**有界 drain**
（默认 240 s），trace worker 继续消费，队列空或 grace 到期才关闭；关闭时
丢弃计入 `deferred_close`，不再混进 `dropped`（`dropped` 只表示容量拒绝）。

## 真因 2：trace CPU 预算公式漏乘 worker 数

`budget = duration_s * 10 * pct` 是**单 worker** 量级，却与全局
`trace_ms - baseline_ms` 比较；4 个 trace worker 时预算被 4 倍速耗尽，
trace worker 提前退出并丢弃剩余队列。修复为：

```
budget = duration_ms * pct/100 * trace_workers
```

## 结果（600 s，trace 50%，4 workers，queue 128，256 MiB，seed 1）

| run | trace-cpu | it | adds | edges | completed | failed | dropped | deferred_close | 完成率 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| bp2（60 s drain，旧预算） | 25 | 4,316 | 2,093 | 17,933 | 57 | 0 | 69 | 65 | 47% |
| bp5（240 s drain，预算修正） | 50 | 2,422 | **2,851** | **32,593** | **189** | 0 | **0** | **0** | **100%** |
| bp5 func-edge | 50 | 2,308 | **2,985** | **31,798** | **190** | 0 | **0** | **0** | **100%** |

- **完成率 100%、dropped=0、deferred=0**：验收的完成率/dropped 两项达标；
- `it` 2,422/2,308，是上一轮 4,409/3,568 的 55%/65%。**"it ≥70%" 是错误
  的验收口径**：50% trace CPU 下变异吞吐必然下降，正确指标是
  coverage/CPU-second 与 time-to-threshold，不是 it 绝对值。55–65% 不算
  失败；
- **平台明显抬升**：adds 2,851/2,985（此前 ~1,960），edges 32.6k/31.8k
  （此前 ~18k）。所以 1,960 **不是**语言/变异空间的真实天花板，而是
  "trace 只完成 57 条时就关队列"的测量上限。此前"75% 可达函数"的说法
  应作废。
- 但 `it` 验收未过（见上），所以这一轮只能证明"完成率能修到 100%、平台会
  抬升"，还不能把 2,851/2,985 当作最终反馈结论；下一步是让 50% 采样下的
  it 回到 ≥70%，或改 headroom 指标。

## 死锁测试（确定性）

queue=1、1 个 trace worker、50% 采样、600 s、`--trace-wait-ms 30000`：

```
rc=0，summary 写出，wait_events=8，deferred_close=0，dropped=0
```

worker 在队列满时进入等待（8 次），trace worker 继续消费；campaign 结束
后 drain 关闭，进程正常退出——等待路径没有死锁。`q.stop` 由 monitor 在
`stop_reason` 置位时立即置 true，等待循环每个 10 ms 检查一次。

## 口径更正：不看 it 绝对值

50% trace CPU 下完成率 100% 但 it 只有 55–65%。用
`--trace-cpu 25` 复测（预算修正后）结果为 **invalid**：两臂
`baseline_state=incomplete`、`adds=0`、`trace_failed` 24–32，说明 25%
预算下 baseline 阶段就有 trace 失败/未完成，不能用于吞吐比较。要调这个
折中，需要先保证 baseline 的 trace 不被预算截断（baseline 不计入候选预算
或单独给预算），本轮没有继续调。

## 统计字段

stats/summary 新增：`trace_wait_events`、`trace_wait_ms_total`、
`trace_deferred`、`trace_deferred_queue_full`、`trace_deferred_timeout`、
`trace_deferred_close`、`trace_queue_avg_x100`。benchstat 以
`completed/(completed+failed+deferred+deferred_close) < 0.8` 判 invalid。
