# Feature-preserving budget：owner 可重放、cap 满显式降级、state 可校验

Date: 2026-11-21. 依据：第三轮复核 P0-C。工具链 pin 未改。

## Owner 可重放

- `Feedback.feature_owners` 增量维护每个 feature 的 retained owner 数；
- 淘汰跳过"最后一个 owner"；
- 如果所有父本都持有唯一 feature，**拒绝新父本**（`feedback_upsert` 返回
  false）并累加 `parents_protected_forced`，不再强行淘汰——强行淘汰会把
  最后一份可重放 owner 丢掉。
- 测试：`if every parent owns a unique feature admission is refused, not
  forced`（entries 保持 2、forced=1、返回 false），以及
  `replacing a full parent registers the newcomer's features`（重算计数一致）。

## cap 满的语义

- 行为/覆盖预算满时：`persist_skipped`/`coverage_skipped` 自增，summary
  里的 `persist_written`/`coverage_written` 不增加——**不会记成已持久化**；
- 父本池满：正常淘汰非唯一 owner；全部唯一时拒绝接纳（上面）；
- 边 universe：到 cap 后下一条新边置 `edge_saturated=true` 并返回 0，
  `edge_refused` 计数；summary/stats 都带 `edge_saturated`，是显式降级
  而不是静默 0。

## Coverage state

`coverage_state.jsonl`：每行一个 `(key, funcs)`，最后一行是完整边 universe
（受 `--edge-cap` 限制）。saved 时：

1. 写 `coverage_state.jsonl.tmp`；
2. `mv -f` 原子替换；
3. 写 `<file>.sha256`。

load 时校验 sha256；缺失或不匹配则返回 `(0,0)`，不会从半个文件恢复。
测试 `coverage state roundtrip, checksum and atomic file` 覆盖正常往返与
篡改拒绝。

## 仍然保留的取舍

- coverage sidecar 里的 `edge_keys` 仍是**前 2048 条预览**，不是全量；
  全量在 `coverage_state.jsonl`（cap 内）。文档与字段名必须这样读，
  不能把 sidecar 当完整边集合。
- state 只保存函数并集与边集合，不保存父本能量/奖励；跨 epoch 的选择压力
  仍重置。
- cap 本身仍是固定值，没有自适应；"停止接纳"是设计选择，不是失败。
