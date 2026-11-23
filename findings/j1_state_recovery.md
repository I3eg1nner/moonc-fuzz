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
 "epoch1":{"by_key":2,"edges":62288,"coverage_adds":0},
 "epoch2":{"by_key":2,"edges":73810,"coverage_adds":0},
 "duplicates":0,"lost":0,"budget_ok":1,"quarantine_ok":1}
```

- by_key 无重复、无丢失；
- epoch2 coverage_adds=0 ≤ epoch1 的 10%（floor 1）；
- 两个损坏注入都 quarantine，不静默丢数据；
- `state_recovery` gate：`ok=true`，detail 带上述 counts。

## 边界

- 本测试的 epoch1 没有进入 mutation case（cases=0），checkpoint 里是
  baseline by_key/edges；因此它证明的是“kill -9 后 checkpoint 可读、无重复/
  无丢失、损坏被 quarantine”，不是“case 级 owner 计数在真实 mutation 下
  完全一致”。
- `fsync` 用 `sync` 实现（文件系统层面），不是对单个 fd 调用 `fsync`；但
  原子替换顺序与 kill 时的可恢复性有实测证据。
- `owners` 字段当前为 `feed.feature_owners.length()`；epoch1 无父本，故 0。

## 状态

`accept` 30/30，新增 `state_recovery`。J2 未做。
