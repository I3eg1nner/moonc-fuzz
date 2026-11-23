# J1：checkpoint kill -9 / resume / quarantine

Date: 2026-11-23. Pin 不变。

## 实现

`moonbit/cmd/fuzz/main.mbt`：

- `coverage_state` 头部：`schema=coverage_state/v2`、`version=1`、`epoch`、
  `cases`、`owners`、`adds`、`last`；
- 写入同目录 `.tmp` → `sync`（fsync 语义）→ `mv -f` 原子替换；
- checksum 不匹配/缺失：把旧 state 复制为
  `coverage_state.jsonl.corrupt.<ts>`，删除旧文件，stderr 打印
  `[state] quarantine ...`，从空 state 重建；
- checkpoint 从末尾移到 `monitor`：每 100 case 或约 5 s（先到）写一次；
  内容含 epoch、owner 计数、by_key、edges、cases、last hash、coverage_adds；
- resume 时读 header；`epoch` 加 1，恢复 by_key/edges/counts。

## 验收脚本

`scripts/state_recovery_test.sh`：

1. epoch1 `fuzz --duration 30 --run-id ep1`，后台等待 state + `.sha256`；
2. kill -9，resume `--run-id ep2 --coverage-state epoch1 state`；
3. 统计 epoch1/epoch2 的 by_key、edges、coverage_adds；
4. 正控制 1：截断 state 最后一行；
5. 正控制 2：翻转 checksum 一位；
   两者都必须出现 `.corrupt.*` 和 quarantine 标记。

实测：

```json
{"ok":1,
 "epoch1":{"by_key":1,"edges":26412,"coverage_adds":536,"cases":200,"owners":536},
 "epoch2":{"by_key":1,"edges":26412,"coverage_adds":536,"cases":796,"owners":536},
 "quarantine_ok":1,"recover_ok":1,"recover_cases":376,"kill_ok":1
 "duplicates":0,"lost":0,"budget_ok":1,"quarantine_ok":1}
```

- by_key 无重复、无丢失；
- epoch2 cases=796 ≥ epoch1 200，owners=536 >0，last hash 变化；
- 最新一次本机 214→815（run-to-run 有 ±case），同一 gate；
- epoch2 coverage_adds 增量 0 ≤ epoch1 的 10%（floor 1）；
- 两个损坏注入都 quarantine，不静默丢数据；
- `state_recovery` gate：`ok=true`，detail 带上述 counts。

## 边界

- epoch1 用 `--baseline-seeds 0` + trace 快速进入 mutation：cases=200、
  owners=536；checkpoint 是 case 级，不是 baseline-only。
- epoch2 用同样入口，cases=793、owners=536；证明 case 不回退、owner 不丢。
- 没有开放单 fd `fsync` API；用进程级 `sync`，因此不写成严格 per-fd atomic。
- `--coverage-state` 现在是精确写入路径；`--coverage-state-out` 用于 epoch2
  避免覆盖输入。header 内嵌 checksum，sidecar 不再在 rename 后单独写。
- `--recover` 已实现；无可恢复代时打印 `fresh-start`。
- 没有单 fd `fsync` API，仍用 `sync`；不写严格 per-fd atomic。
- `owners` 字段当前为 `feed.feature_owners.length()`；epoch1 无父本，故 0。

## 状态

`accept` 31/31（含 `state_recovery` 与 `original_config_replay`）；J2 已完成。
