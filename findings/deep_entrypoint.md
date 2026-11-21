# Deep 接线：从"IR 程序被变异后大量 T2 失败"到 99.2% T2 成功率

Date: 2026-11-21. 依据：多 seed A/B 里 deep 臂 `t2_ok` 反而低于 function 臂
（33–47 vs 51–71）。工具链 pin 未改。

## 诊断

先排除"缺入口点"这一假设：

- `@ir.emit_program` 生成的程序**自带** `fn main { ... }`（`ir/gen.mbt`
  的 `generate` 把 `main` 放进 funcs），`has_main` 也认得无括号形式；
- 手工用 campaign 的 T2 参数（`moonc build-package ... -pkg-type executable
  -all-pkgs ...`）编译一份生成源，rc=0；
- `deep-p 100` 的 60 秒运行里 T2 是 **59/59 成功**。

真正的原因：deep 源被当成普通候选**写进了父本池**。IR 程序语法健壮、体积小，
对它做字节变异很容易"T1 过、T2 挂"（类型错误），于是 deep 臂的
`t2_ok / t2` 从 10% 掉到 6–8%。缺 main 的失败没有出现。

## 修复

- `is_deep` 的迭代**不进入父本池**（不 `feedback_upsert`/`persist_behavior`），
  deep 源只直接作为 T2/T3 候选使用；
- 普通变异仍走原路径；deep 迭代仍计入 `it`/`t1`/统计。

## 验收（600 s，2 workers，seed=1，T1/T2 5%）

| 臂 | it | t2 | t2_ok | 成功率 | coverage_adds |
|---|---:|---:|---:|---:|---:|
| function | 7,495 | 48 | 5 | 10.4% | 1,815 |
| deep-edge（--deep-p 30） | 46,760 | 3,634 | **3,606** | **99.2%** | 684 |

- `deep 臂 t2_ok ≥ function 臂`：3,606 vs 5，满足；
- 没有缺 main 的失败：99.2% 的成功率里，失败 28 次，均为其他编译错误
  （不是入口点问题；`deep-p 100` 的 59/59 也直接证明）；
- 代价：deep 臂的迭代吞吐高（跳过父本记账、IR 源更小），两臂的
  wall-clock 不完全可比；deep 覆盖的函数更少（684 vs 1,815），因为 IR 语言
  受限。

## 边界

- 结论只针对 `pkgtype(executable)` + `--mode mbt` 的 T2/T3 路径。
- deep 源不入父本池是取舍：避免了"变异 IR 造成的假 T2 失败"，也失去了
  "从 deep 源继续演化"的机会；要两者兼得，需要类型保持变异，不是本轮。
- 单 seed、600 s、2 workers；不是多 seed 结论（多 seed 的 A/B 见
  `findings/p1_feedback.md`，那一轮 deep 数据在修复前）。
