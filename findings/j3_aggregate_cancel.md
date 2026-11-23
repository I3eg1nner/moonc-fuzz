# J3：可移植 supervisor 与聚合取消

Date: 2026-11-23. Pin 不变。

## 实现

`scripts/supervisor.sh`：

```
--agg-rss-mb N   每 0.5 s 对进程组 RSS 求和，超过 N 即取消
--max-procs N    进程组进程数上限
--deadline S     墙钟上限
```

启动 `setsid`，得到独立进程组；超限先 `kill -TERM -PGID`，等 2 s，再
`kill -KILL -PGID`；取消后 `wait`/reap，并统计组内剩余 PID。
结果 JSON：`incomplete/reason/orphans/rss_kb/procs/elapsed_ms`；
取消时 exit 42，正常 exit 0。

## 正负控制

`scripts/aggregate_cancel_test.sh`：

- 正控制：4 个 worker 各分配约 120 MiB，`--agg-rss-mb 100`；必须在 10 s
  内被杀，`incomplete=1`；
- 负控制：一个小 worker，`--agg-rss-mb 1000 --deadline 10`；正常完成，
  `incomplete=0`。

实测：

```json
{"ok":1,
 "positive_incomplete":1,
 "positive_orphans":0,
 "positive_killed_ms":505,
 "negative_incomplete":0}
```

- 组内无孤儿进程；
- `incomplete` 标成未完成，不写成成功。

## cgroup 边界

本机 `findmnt`：

```
cgroup2 /sys/fs/cgroup
```

`/sys/fs/cgroup` 不可写（`cgroup_writable=0`）。因此本轮**没有**运行 60 s
cgroup memory.peak/pids.peak；只记录 mount 证据，不声称聚合资源已由
cgroup 实测。supervisor 的进程组 RSS 求和是可移植替代。

## Gate

`aggregate_cancel`：正控制 incomplete=1、orphans=0、killed<10s；负控制
incomplete=0。accept 33/33。
