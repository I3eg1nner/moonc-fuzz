# Baseline 抽样：2k/epoch 的 coverage_adds 是读数高估

Date: 2026-11-21. 依据：epoch soak 每轮 `coverage_adds≈2k` 不衰减的怀疑
（用户提出）。工具链 pin 未改。

## 验证

代码确认（修复前，`cmd/fuzz/main.mbt` baseline 提交循环）：

```moonbit
let n = min(cfg.baseline_seeds, seeds.length())
for i in 0..<n {
  let src = seeds[i]        // seeds 已按文件名 sort()
```

`load_texts` 先 `files.sort()` 再按顺序读入，所以 U0 **永远是字典序前 8 个
文件**；`--seed-dir` 接力时语料池增大，这个前缀基本不变。于是每个 epoch 的
`coverage_adds` 实际是"相对同样 8 个 seed 的新函数"，而不是"相对上一轮语料
的新函数"——**2k/epoch 是高估**。

对照数据：

| 运行 | baseline | adds/epoch |
|---|---|---|
| 6-epoch soak（修复前，固定前缀） | 8 seeds | 2016 / 2285 / 2112 / 2089 / 2070 / 2066 |
| 2-epoch（spread 抽样后） | 8 seeds | **1963 / 890** |
| 300 s，baseline-seeds=8 | 8 → 16 个任务 | baseline 未完成（done 11/16），adds 0 |
| 300 s，baseline-seeds=32 | 32 → 64 个任务 | baseline 未完成（done 60/64），adds 0 |

spread 之后第二轮降到 890，说明"不衰减的 2k"里至少一半是读数伪影；两个
300 s 实验因为 baseline 没跑完（每个 seed 会提交 T1+T2 两个 trace）不能用来
比较 adds。

## 修复

- `spread_indices(total, k)`：把 baseline 均匀铺开到整个语料，而不是取前缀；
  有单元测试（长度、首尾、去重、越界、语料少于 k）。
- epoch 脚本不改 baseline 大小；读数按"相对 U0 样本"解释。

## 仍未解决

- U0 只抽 8 个文件（约 2000 个里的 0.4%），即使 spread 也代表不了接力后的
  语料。正确做法是把上一轮的 `coverage_funcs` sidecar 读回来作为 by_key
  初值（sidecar 已保存该字段），或者按语料规模放大 baseline；
- 当前 `baseline_seeds` 的每个 seed 会提交 T1 与 T2 两个 trace，实际任务数
  是 2×；短跑里 baseline 经常跑不完，`incomplete` 又关闭学习。长跑（600 s
  epoch）能完成，但这解释了两个 300 s 实验的 0 adds。
- 在修复"跨 epoch 覆盖状态恢复"之前，不能把 epoch adds 相加当总收益。
