# 聚合资源：可移交的 cgroup 包装脚本

Date: 2026-11-21. 依据：本轮 (4)。工具链 pin 未改。

## 脚本

`scripts/cgroup_run.sh`：

```
scripts/cgroup_run.sh --out DIR --memory-max 8G [--pids-max 512] -- CMD...
scripts/cgroup_run.sh --dry-run
```

正常路径：在可写的 cgroup v2 下创建 `$CGROUP_ROOT/$NAME`，写
`memory.max`/`pids.max`；supervisor 不进组，子 shell 写自己的 pid 后 exec
命令；每 2 s 采
`memory.peak` 和 `du -sb $OUT`，结束时写 `OUT/memory.peak` 与
`OUT/disk_peak_bytes`，清理 cgroup。

不可写时：`--dry-run` 打印完整计划并 **exit 0**（只是计划，不代表执行）；
非 dry-run 且不可写时打印同样的计划并 **exit 2**，明确 "limits not enforced"。

## 本机 dry-run

```
cgroup v2 plan (not executed):
  root:        /sys/fs/cgroup
  memory.max:  8G
  memory.peak: /sys/fs/cgroup/mbtfuzz-<pid>/memory.peak
  pids.max:    512
status: NOT WRITABLE on this host; limits not enforced
```

本容器 `/sys/fs/cgroup` 只读，符合预期；因此**没有** 1 小时的
`memory.peak` 实测数据，findings 不声称已验证聚合边界。

## 使用约定

- 长跑必须通过该脚本启动，并把 `OUT/memory.peak`、`disk_peak_bytes` 与
  `summary.json` 一起归档；
- `--memory-max` 是 cgroup 总量，与逐进程 `prlimit --as` 不是同一层，不能
  用后者相加来推导前者；
- `pids.max` 要覆盖 worker + trace + moonc/qemu 子进程；
- 脚本不修改 pin，也不依赖 systemd。
