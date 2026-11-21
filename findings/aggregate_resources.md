# 聚合资源边界：当前可做什么、部署需要什么

Date: 2026-11-21. 依据：第三轮复核 P1-D；本轮实测容器限制。

## 实测限制

- 本机 cgroup v2 存在但 `/sys/fs/cgroup` 只读（`mkdir` 失败），没有 systemd
  user bus（`systemd-run --user` 连接失败），所以**不能在会话内创建 cgroup**；
- 现有 `prlimit --as` 是逐进程地址空间上限，不是 campaign 总量；
  多 worker/子进程可以各自接近上限；
- `--rss-limit-mb` 是 harness 软顶（monitor 读取后停止接新任务），
  不是内核强制的总量。

## 已做的边界

| 层 | 机制 | 边界性质 |
|---|---|---|
| 子进程地址空间 | `prlimit --as`（moonc/qemu/harness 各自） | 逐进程 |
| harness 内存 | `--rss-limit-mb` + monitor 干净停机 | 进程级软顶，写 summary |
| QEMU 日志 | `prlimit --fsize` + 不读超限日志 | 单文件硬顶 |
| 输出 | `max_output_bytes`（cap 后截断；semdiff 用 digest） | 单次运行 |
| 磁盘证据 | `--persist-cap` / `--coverage-cap` | campaign 上限 |
| 长跑内存 | 进程 epoch + 语料/覆盖 state 接力 | 单进程生命周期 |

## 部署要求（长跑前必须满足）

1. **cgroup v2**：`memory.max`（建议 4–8 GiB）、`memory.peak` 记录、
   `pids.max`（worker + trace + 子进程）、`io.max` 或磁盘配额；
2. **磁盘**：`--persist-cap`/`--coverage-cap` 之外再用文件系统配额，
   避免 QEMU 日志瞬时峰值打满；
3. **记录**：每次长跑保存 `memory.peak`、`pids.peak`、输出目录字节峰值、
   `trace_dropped`/`edge_saturated`，并与 `summary.json` 一起归档；
4. **不得**把 `prlimit --as` 或 `--rss-limit-mb` 描述为 campaign 总内存上限。

## 本轮没有做

- 没有创建 cgroup（环境只读）；
- 没有在 cgroup 下跑 1 小时记录 `memory.peak`（需要可写 cgroup 的宿主）；
- 因此**不声称**聚合资源边界已验证，只记录机制与部署条件。
