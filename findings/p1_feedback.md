# 反馈链：10 分钟三臂 A/B，以及 trace 丢失率的实测

Date: 2026-11-20. 依据：独立评审 P1-1（`findings/codex_review_6.md`）与
P0-3 的 30 分钟 soak。工具链 pin 未改。

## 问题

主循环的反馈是"每次执行都可能产生覆盖"，但实测 trace 极稀疏：60 秒校准
只有 22 条 trace / 48,880 次 T1，`trace_dropped=1245`。评审的要求：

1. 量化 `trace_dropped` 与完成比；
2. T1 饱和后不要把 trace 预算继续给 T1，优先行为新颖的 T2/T3；
3. behavior-only / function / function+edge 三臂同预算，记真实子进程 CPU，
   报新稳定 feature 中位数，不预设提升。

## 实现

- `--no-edge-reward`：边新颖度仍更新 universe，但不给父本 +8 奖励
  （function-only 臂）；
- T1 饱和退让：连续 40 条 T1 trace 既无新函数也无新边时置
  `t1_trace_off`，此后不再采样 T1 trace，并把 T2 trace 概率翻倍（上限 0.95）。
  计数器 `t1_dry` 与 `t1_trace_off` 进 summary；
- 三臂脚本 `scripts/bench_campaigns.sh` 串行跑 3×600 秒，用 GNU time 记录
  user+sys 与 max RSS（time 会包含 wait 的子进程）；
- 汇总器 `cmd/benchstat`（MoonBit；主分支不允许 `.py`）读
  `summary.json`/`stats.jsonl`/`<arm>.time`，计算每 30 个样本窗口（约 60 秒）
  的 feature 增量中位数。

## 采样率的口径（先说清楚）

`--trace-t1/--trace-t2` 收的是**百分数整数**（20 = 20%）。首版脚本传了
`0.02/0.05`，整数解析器拒绝小数，回落到默认值——所以下面两条 trace 臂
实际跑在 **T1 20% / T2 70%** 的默认采样率上，不是原计划的 2%/5%。
行为臂传的是 `0`，确实关闭了 trace。脚本已改为传 `2/5`，但下面的 A/B 数据
是默认采样率下的结果；这反而让 trace 丢失的结论更强（70% 采样仍然只有
22–24% 完成率）。

## trace 丢失率（600 秒，trace_queue=8，trace_workers=1，T1 20% / T2 70%）

| 臂 | completed | dropped | failed | 完成比 |
|---|---:|---:|---:|---:|
| function | 44 | 123 | 32 | 22.1% |
| func-edge | 50 | 129 | 30 | 24.0% |

绝大多数 trace 任务在队列满时被丢弃，而不是执行失败；`trace_max_mb=64`
的硬上限把 30 条左右判成 `trace_log_capped`（`failed` 的主要来源）。
**结论**：在 10 分钟预算、4 个 fast worker 下，trace 通道是饱和的，反馈
采样率由队列容量而非 T1 数量决定。`t1_trace_off` 在这两次运行中**没有触发**
（`t1_dry=0`），因为 T1 持续产生新边（18,229 条），没有出现"饱和后仍抢
trace"的场景；该机制存在但在这组预算下未被激活，不能声称它有效。

## 三臂同预算（各 600 s，4 workers，seed=1）

| 臂 | it | t2_ok | 新函数 | 新边 | trace 完成 | CPU (user+sys) | max RSS | 中位新 feature/60s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| behavior | 69,860 | 57 | 0 | 0 | 0 | 1,372 s | 1,044 MB | 0 |
| function | 66,956 | 53 | 0 | 18,229 | 44 | 1,508 s | 1,816 MB | 0 |
| func-edge | 67,098 | 57 | 0 | 18,229 | 50 | 1,502 s | 1,817 MB | 0 |

（新函数=summary `coverage_adds`；新边=`new_edges` 观测值，function 臂不奖励
它但仍然统计。）

判读，按证据强度从强到弱：

1. **中位新 feature/60s 为 0，三臂一致。** 所有边新颖度都集中在开头的
   baseline/seed 阶段；进入稳态后 10 分钟没有持续的新 feature。这不是
   "A/B 无差异"，而是"这组预算下三臂都没有稳态增益"。
2. **function 与 func-edge 的观测边数完全相同（18,229），t2_ok 53 vs 57、
   trace 完成 44 vs 50。** 差异在单次运行的波动范围内，不能声称 edge bonus
   提高了探索；只能说没有观察到可重复的差异。
3. **行为臂用少 9% 的 CPU、一半的 RSS 达到同样的 t2_ok（57）。** 覆盖反馈
   在这 10 分钟里没有换来更多类型检查器触达。
4. **新函数为 0**：三臂都没有触达新的 `camlMoonc*` 函数，与 P0-3 soak 的
   `coverage_adds=0` 一致。短预算下函数反馈没有可测量的产出。

## 2 小时 soak 的对照

同一组 flags（T1 2% / T2 5%）跑 7200 秒：`trace_completed=697`、
`trace_failed=207`、`trace_dropped=101`，完成比 69%，远高于 10 分钟默认
采样下的 22–24%。结论：短预算下的高丢弃是队列容量问题，长跑会排空；
`t1_trace_off` 在 2 小时里同样没有触发（`t1_dry=0`），因为边覆盖持续
增长到 18,229 后停止，没有出现"饱和后仍抢 trace"的窗口。

## 边界与不做的事

- 每个臂只跑了 1 个 seed、1 次；上面的差异不是显著性结论，只是同一预算下
  的观测值。要下"edge 反馈有用/无用"的结论需要多 seed 重复。
- CPU 是 `time` 报告的整个进程树（含 waited children），不是按阶段拆分。
- 10 分钟不足以让 `t1_trace_off` 触发；2 小时 soak 才会检验它。
- 这组数字支持的说法是：**在 IR/字节变异这组输入上，10 分钟内的新 feature
  全部来自早期，三种反馈策略没有可区分差异**；不支持"反馈无用"的一般结论。

## 多 seed A/B（含 deep 队列）

`scripts/bench_multi_seed.sh`：4 臂 × seeds 1/7/2026，各 300 s、2 workers、
parent-cap 500、trace T1/T2 5%，12 个进程并行跑。中位数（每臂 3 个 seed）：

| 臂 | it | t2_ok | coverage_adds | new_edges | max RSS |
|---|---:|---:|---:|---:|---:|
| behavior | 22,238 | 6 | 0 | 0 | 399–625 MB |
| function | 16,557 | 54 | 0 | 4,085 | 602–608 MB |
| func-edge | 17,235 | 61 | 0 | 0（seed 间 0–4,845） | 536–633 MB |
| deep-edge（--deep-p 30） | 18,693 | 34 | 0 | 1,361 | 585–603 MB |

判读：

1. **300 秒口径下 `coverage_adds` 全为 0**：baseline 现在会等 U0 完成
   （60–90 s），再扣掉生成/解析，稳态只剩 ~3 分钟；函数 novelty 在这段时间
   内没有出现。这不是"learning 坏了"——30 分钟口径下同一代码有 2,439。
2. **`new_edges` 的 seed 间方差大于臂间差异**：function 的 0/4085/4845 与
   func-edge 的 0/0/4005 交叠，不能据此声称 edge 奖励有效。
3. **deep 臂 t2_ok 中位数 34，低于 func-edge 的 61**：接入方式还有缺陷——
   IR 生成的是函数集合，没有为 `pkgtype(executable)` 的 T2 包准备入口点，
   部分 deep 输入在 T2 处以"缺 main"失败。这是接线问题，不是 IR 程序的
   问题（`cmd/deepfuzz` 单独跑 11,451 例 100% 通过，因为它自己写了饰品包、
   也不要求 main）。
4. 结论仍是**没有观察到反馈策略的可重复收益**；多 seed 只是把"单次噪声"
   变成"seed 间方差"，没有变成正向证据。

下一步若要继续这条线：给 deep 源补入口点/包类型后再跑，并延长到 30 分钟
以越过 baseline；在此之前不应把 deep 结果算作正收益。

## 第二轮复核补修（计数器）

- `t1_trace_off` 原来用 `covset.len() == 0` 判"干"，但每条 T1 trace 都有函数，
  条件永远不成立；现在用 `trace_apply_delta` 返回的 **delta**（相对该
  key 的新增函数）与边增量判断，dry 计数才可能触发。
- 父本池满、替换 victim 的分支漏了对新父本 cov 的 `owner_add`，所有权计数
  会少一个父本；已补，并用"重算计数 vs 增量计数"的测试钉住。
