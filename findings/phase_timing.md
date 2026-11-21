# func-edge 吞吐差：分阶段计时（300 s 成对）

Date: 2026-11-21. 工具链 pin 未改。

## 数据（同 seed=1、2 workers、T1/T2 20%、cap 200k、baseline complete）

| arm | it | ms_mutate | ms_t1 | ms_t2 | t2 | adds | new_edges |
|---|---:|---:|---:|---:|---:|---:|---:|
| function | 20,042 | 30,707 | 287,613 | 2,495 | 52 | 686 | 2,838 |
| func-edge | 6,872 | 10,055 | 267,050 | 1,727 | 49 | 1,429 | 7,086 |

每迭代：

| arm | T1 ms/it | mutate ms/it | T2 ms/it |
|---|---:|---:|---:|
| function | **14.4** | 1.53 | 0.12 |
| func-edge | **38.9** | 1.46 | 0.25 |

## 定位

- 总 T1 时间两臂接近（287 s vs 267 s，均约等于 300 s × 2 workers 的
  大部分），但 func-edge 的迭代数只有 1/3 —— 差距几乎全部来自
  **单次 T1（syncheck）成本 38.9 ms vs 14.4 ms**；
- mutate 每迭代成本相近（1.46 vs 1.53 ms），T2 总耗时 <3 s，不解释差距；
- 代码检查：边记账在 trace worker 的 `trace_apply` 里，只遍历**这条 trace
  的 edge_keys**，不存在"每次遍历全部 universe"的路径；T1 计时也不包含
  trace worker。因此不是 edge 记账吞收益。

## 机制（只到相关，不到因果）

edge 奖励改变父本能量/选择，func-edge 选中的父本平均更大或更慢，导致同一
syncheck 更贵——这与"每迭代 T1 成本 ×2.7"一致，但本轮**没有**测父本字节
分布，不能把"更大输入"写成已证机制。要钉死需要记录
`sum(src_bytes)/it` 与父本尺寸分布。

上一版 `findings/p1_feedback.md` 写的"edge 奖励把选择推向单位迭代更贵的
路径"是猜测；现在可以说的是：**贵在 T1 每次执行，不在 edge 记账**，
原因待测。

## 边界

- 单 seed、单次成对；300 s 内 baseline 约 70 s，学习窗口短；
- ms_t1 是跨 worker 求和，不是 wall；每迭代值用总时间/迭代数近似；
- 两臂的 trace 采样比例相同，但父本池不同，输入分布不是受控变量。
