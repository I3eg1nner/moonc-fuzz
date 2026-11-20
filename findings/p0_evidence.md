# P0-2：新覆盖、崩溃证据与重启回放不再丢

Date: 2026-11-20. 依据：`findings/codex_review_6.md`（P0-2）与评审 §2、§5。
工具链 pin 未改。

## 问题（逐条对应评审）

1. **覆盖证据和行为证据共享一个预算**（`--persist-cap`）。行为样本先写满，
   新覆盖只更新内存、不落盘（`persist_skipped` 只加计数）。
2. **边 key 不持久化**：sidecar 只有 `trace_edge_keys` 计数和 `edge_novel`，
   重启后无法重建 feature 归属。
3. **crash 落盘后不回灌父本**：`save_crash` 成功后直接 `continue`，下次变异
   从别处继续，唯一已知能触发该 bug 的输入不参与演化。
4. **`--seed-dir` 重启不能重放各 mode**：所有输入都以 `<sha1>.mbt` 存盘，
   而 pkg/mod/mbtmd 的 loader 按自己的后缀找文件，重启静默加载 0 个。
5. **淘汰不保护 feature 唯一拥有者**：按 energy 淘汰，可能删掉最后一个覆盖
   某条边/函数的父本，覆盖集合在磁盘上的可恢复性随之丢失。

## 改动

### 覆盖 witness 独立预算

- `Config.coverage_cap`（`--coverage-cap`，默认 4000）；
- `PersistBudget` 新增 `coverage_cap`、`covered`、`coverage_written`、
  `coverage_skipped`；
- `persist_admit_coverage` 只查自己的预算与集合，行为预算设为 0 也不影响
  覆盖落盘；
- `summary.json` / `manifest.json` 增加 `coverage_cap`、`coverage_written`、
  `coverage_skipped`。

### 边 key 与 feature sidecar 可恢复

coverage sidecar 新增（每 `(input, config, stage, outcome)` 一条）：

```json
"trace_edge_keys": 1234,
"edge_keys": ["a1b2,c3d4", "..."],   // 前 2048 条，排序后原样
"edge_keys_truncated": true
```

`edge_keys` 与实际 `mapped_edges` 同源（`TraceResult.edge_keys`），因此重启后
可以按 (input, config) 重建 feature 归属；超过 2048 条时显式标 truncated，
不假装完整。

### crash 回灌父本

`save_crash` 成功后立即 `feedback_upsert(feed, src, 空集合, 0, 0)`：崩溃输入
以最低能量进入父本池，下一轮变异从它出发。能量给 1 而不是 32，避免单个
崩溃刷满父本池。

### 重启按 mode 命名

`corpus_file_name(h, mode)`：`h.mbt` / `h.moon.pkg` / `h.moon.mod` /
`h.mbt.md` / `h.mbti` / `h.mbtx`。行为 meta 里的 `source` 也改用它。
测试用 `load_texts([dir], ["moon.pkg"], ...)` 证明写出的名字能被 loader 找回。

### 淘汰保护最后一个 feature owner

- `Feedback.feature_owners : Map[String, Int32]` 增量维护（插入/并集/淘汰时
  ±1），不需要每次全量重算；
- 淘汰时跳过 `owns_unique` 的父本；若全部父本都拥有唯一 feature，则退回
  最低能量策略，并累加 `parents_protected_forced`（进 summary），不静默。
- `parents_protected_forced` 在正常淘汰下应为 0；非零表示父本池已经装不下
  当前 feature 多样性，是扩容或提高 cap 的信号。

## 验证

```text
moon test --target native        350 / 350 pass
新增测试                         naming 6 种 mode、pkg witness 可被 loader 找回、
                                 淘汰保留唯一 owner、全 unique 时 forced 计数
accept                           19/19（见提交记录）
```

新测试直接覆盖评审的反例：行为预算 0 + 覆盖预算 1 → 第二条 sidecar 不写、
`coverage_skipped=1`、两条 trace 仍在内存计数；`cap=2` 时插入第三个父本，
唯一 owner 被保留。

## 边界

- `edge_keys` 每 sidecar 只存前 2048 条，超出部分只留计数；这对“可恢复
  feature 归属”是部分恢复，不是全量。全量边语料需要独立的压缩列存，未做。
- `coverage_cap` 默认 4000 是工程选择，不是测量结果；长跑时应按磁盘预算调整。
- 崩溃回灌只回灌 t1 崩溃；t2/t3 的候选仍只在 finding 目录里，等 triage 流程
  （P1-3）处理。
- 淘汰保护是增量计数，依赖 `FuncSet` 的并集/差集语义；若上游函数集合实现
  改变（例如带去重以外语义），计数需要重新验证。
