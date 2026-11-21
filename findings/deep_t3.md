# 主 campaign 的 deep T3 语义链

Date: 2026-11-21. 工具链 pin 未改。

## 问题

deep 源在主 campaign 里只走到 T2 构建，`t2_ok` 被当成"深阶段成功"的替代；
没有把参考解释器输出带进主 campaign，也没有独立的 T3 matched 计数。同时
deep 源在 T2 的 novelty 路径上还会被写入父本池，与普通 lane 混在一起。

## 实现

- `is_deep` 迭代生成 IR 程序时立刻用 `@ir.run` 取参考输出
  （`deep_expected`）；
- T1 通过后，deep lane 执行 `moon run <fname> --target wasm-gc`，把 stdout
  与参考输出逐行比较：
  - `deep_t3_attempts`：执行次数；
  - `deep_t3_matched`：rc=0 且逐行一致；
  - `deep_t3_distinct`：按源 sha1 去重的 matched 输入数（worker 内）；
  - `deep_t3_mismatch`：rc=0 但不一致。
- deep 源在 T1/T2 的 novelty 路径上都不再 `feedback_upsert`，两条 lane 的
  父本池与计数互不污染（普通 `t2_ok` 仍包含 deep 的构建，但 deep 的语义
  成功只由 `deep_t3_*` 表示）。

## 冒烟结果（70 s，2 workers，`--deep-p 50`，trace off）

```json
{"it":69,"deep_t3_attempts":42,"deep_t3_matched":42,
 "deep_t3_distinct":42,"deep_t3_mismatch":0}
```

42 次执行全部与解释器一致、42 个 distinct 源；`parents` 保持 50（上限），
没有 deep 源被写入父本池的证据。

## 边界

- `it` 只有 69：每次 deep 迭代要编译+运行一次 wasm-gc，成本约 1 s；
  这不是吞吐对比，只证明语义链与计数可用。
- `deep_t3_distinct` 是每 worker 的去重，多 worker 可能重复计数；summary
  的语义是"至少这么多 distinct"。
- 主 campaign 默认仍按 `--p-deep` 采样 T2；deep T3 只在 `is_deep && k1==OK`
  时执行，所以非 deep 迭代不产生这些计数。
