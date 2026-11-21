# Coverage state 加固（第四轮复核 5）

Date: 2026-11-21. 工具链 pin 未改。

## 改动

- **缺 checksum 拒绝**：state 文件存在但 `.sha256` 缺失，视同损坏，返回
  `(0,0)`，不再放行；
- **写失败是 infra 错误**：`save_coverage_state` 返回 Bool，tmp 写失败、
  `mv` 失败、sha 写失败都会让 campaign 打印 `coverage_state write failed`
  并 `exit 2`；不再静默空状态；
- **恢复受 cap 约束**：加载边时按当前 `edge_cap` 截断，超出置
  `edge_saturated=true`；
- **epoch 复制摘要**：`scripts/soak_epochs.sh` 同时复制 `.sha256`；
- **sidecar**：单 trace 边预览上限从 2048 提到 8192，并在
  `edge_keys_truncated` 显式标记；它仍不是全量，全量在
  `coverage_state.jsonl`（cap 内）；
- **诊断 map 有界**：`edge_raw_owner`/`edge_collided` 上限 200000，
  超出不再插入（collision 计数是 best-effort）。

## 故障测试

`coverage state without checksum is rejected; edges respect the cap`：
删掉 `.sha256` 后 keys=0；把 cap 设为 0 时加载 0 条边且
`edge_saturated=true`。另有往返 + 篡改拒绝测试。

## 边界

- sidecar 的 8192 仍是上限，不是"cap 内全量"；超过会显式
  `edge_keys_truncated=true`。全量边在 state 文件里，两者不要混读；
- 写失败退出 2 会让该 epoch 的摘要不写，但保留已落盘的 corpus/state；
- 诊断 map 达上限后 collision 会少报，`edge_collisions` 是下界。
