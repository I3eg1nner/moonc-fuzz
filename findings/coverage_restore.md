# 跨 epoch 覆盖状态恢复

Date: 2026-11-21. 依据：本轮第 2 项；上一轮 `findings/baseline_sampling.md`
留下的"epoch 只接力输入、by_key 每轮重置"问题。工具链 pin 未改。

## 问题

`scripts/soak_epochs.sh` 只把上一轮 `corpus/*.mbt` 并入 seed pool。新进程
启动后 `by_key`、`edge_seen` 都是空的，U0 又只抽 8 个 seed，于是上一轮已经
覆盖过的函数在新一轮仍被算成 novelty。

## 实现

- 每个 epoch 结束时写 `<run>/coverage_state.jsonl`：
  - 每行 `{"key":"stage|outcome|config","funcs":[...]}`（by_key 的并集）；
  - 最后一行 `{"edges":[...]}`（campaign 边 universe，受 `--edge-cap` 限制）。
- 新参数 `--coverage-state PATH`：启动时加载上述文件，恢复 `by_key` 与
  `edge_seen`；summary 报告 `restored_keys` / `restored_edges`。
- `soak_epochs.sh` 把上一轮的状态文件复制到 pool，并在下一轮传入。

## 验收（2 × 240 s，3 workers，trace 5/5）

| epoch | restored_keys | restored_edges | coverage_adds | new_edges | baseline |
|---|---:|---:|---:|---:|---|
| 1 | 0 | 0 | 1,068 | 0 | complete |
| 2 | **4** | **50,000** | **118** | 0 | complete |

第二轮在恢复 4 个配置键与 5 万条边之后，`coverage_adds` 从 1,068 降到 118。
这与上一轮"修 spread 后 1963→890"同向，但幅度更大：恢复覆盖状态后，绝大部分
"新函数"确实是上一轮已经见过的。

## 边界

- `restored_edges` 撞到 `--edge-cap=50000`：边 universe 只恢复封顶部分，超出
  的边会在下一轮被重新发现（`new_edges` 仍为 0 说明这些边早已在 campaign
  内部观察到，但未写入状态文件）。
- 恢复的是函数并集与边集合，不是父本能量/奖励状态；跨 epoch 的选择压力仍重置。
- 只验证了 2 个 epoch、单 seed；更长链条与多 seed 未测。
- 状态文件是 JSONL 文本，大 campaign 可能达到数 MB；没有压缩。
