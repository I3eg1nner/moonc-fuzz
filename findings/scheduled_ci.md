# Scheduled CI：pin 工具链 + seed 归档 + 真实 QEMU trace + artifact

Date: 2026-11-21. 依据：本轮第 5 项。工具链 pin 未改。

## 为什么另开一个 workflow

每次 push 的 `CI` 跑验收门禁，但用 `--profile core` 跳过了需要宿主机
`afl-qemu-trace` 的三项 trace 检查，也不跑 campaign。定时任务补的是另一半：
**真实 trace 的短 campaign**，证明"反馈链"在干净机器上能启动。

## 内容（`.github/workflows/scheduled.yml`）

- 触发：每日 cron + `workflow_dispatch`；
- 工具链：v0.1.0 release 附件，sha256 校验；
- seed：仓库内 `seeds_min.tar.gz`（25 个模板 + dict），sha256 校验；
- QEMU：`qemu-user-static`，`qemu-x86_64-static --version` 写入 artifact；
- 运行：240 s、2 workers、T1/T2 20%、`baseline-trace-max-mb 256`、
  `--seed-dir` 解包目录；
- 断言：`baseline_state=complete`、`baseline_done==expected`、
  `trace_completed ≥ 1`、`coverage_records ≥ 1`；
- artifact：整个 `out/` 与 QEMU 版本文件，失败也上传。

## 验证（本地等价路径）

用同一套参数在本地跑过一次 90 s 烟测（qemu-x86_64-static）：

```json
{"it":0,"trace_completed":16,"trace_failed":0,
 "baseline_state":"complete","baseline_done":16,"baseline_failed":0}
```

`it=0` 是因为 90 s 全被 baseline 用掉（16 条 trace，含 T1/T2），这正是
scheduled job 用 240 s 并断言 baseline 而非迭代数的原因。

## 边界

- QEMU 版本没有真正 pin：distro 包会漂移，只能记录版本并对照 trace 数；
- cron 只在默认分支运行，PR 不触发；
- artifact 保留期用 GitHub 默认值，仓库不承诺长期归档；
- seed 归档是 25 个模板，不是完整语料；它只保证 baseline 可完成，不代表
  探索多样性。
