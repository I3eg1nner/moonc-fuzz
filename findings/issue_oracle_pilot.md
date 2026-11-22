# Issue→oracle pilot：从历史缺陷构造“新性质”，而不是复现旧 witness

Date: 2026-11-22. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`, Linux x86_64。

目标：验证“历史 issue 能否转成新 oracle 目标”这件事本身，而不是再测一遍
F5/F7。两个 pilot 都只生成**邻域新程序**，用性质判定，不把“原 witness 是否
仍复现”当成功标准。

## Pilot A：F5 → formatter 往返/幂等/语义 oracle

输入：`templates/` 的 25 个可运行程序（含 int/float/string/struct/enum/array/
trait/generic/closure/pattern/escape 等）。每个程序：

1. `moonfmt o.mbt -o f1.mbt`；
2. `moonc syncheck f1.mbt`；
3. `moonfmt f1.mbt -o f2.mbt`，比较 `f1 == f2`（幂等）；
4. 分别 `moon run o.mbt --target wasm-gc` 与 `moon run f1.mbt --target wasm-gc`，
   比较 stdout（格式化是否改变语义）。

结果：**25/25 全部通过**。`fmt_rc=0`、`syn_rc=0`、`idem=true`、
`run_o=run_f=0`、stdout 相同。没有出现 F5 之外的 formatter 破坏。

边界：

- 这 25 个模板是 curated 的，不含 `~+` 触发形态；F5 本身仍由 `regress` 覆盖。
- 没有比较 AST，只比较“可重解析 + 二次格式化稳定 + 运行输出”。因此
  “格式不同但语义相同”不会被判失败，判据偏保守。
- 注释、doc comment、可选参数、label 顺序、match guard 等格式化敏感形态
  覆盖不足。

## Pilot B：F7 → 数组构造方式等价 oracle

输入：60 个新生成程序（不是 F7 的原 witness）：

- enum 形状：payload-first `A(Int); B`、all-payload `A(Int); B(Int)`、
  nullary-first `B; A(Int)`、single `A(Int)`；另有 scalar 控制；
- struct：两字段 `id + kind`、三字段 `id + tag + kind`；scalar 用 `id + n`；
- 构造方式：literal、`[] + push`、`Array::make`、`Array::makei`、`map`、
  `filter`；
- n=3；期望值由生成器独立计算（`id` / enum payload / `B` / scalar `n`）。

Oracle：同一组值经六种构造方式，在 `wasm-gc`、`js`、`native --release`
上必须产生相同序列，并与生成器的期望一致。

结果（180 次 release 运行）：

| 类别 | 数量 | 说明 |
|---|---:|---|
| 三后端 rc=0 且 stdout == expected | **60/60** | 没有语义分歧 |
| 新 crash/ICE 签名 | **0** | 没有出现 F7/F8/F9 之外的签名 |

同一批 60 个程序在 `native` **debug** 下重跑：

| 类别 | 数量 | 说明 |
|---|---:|---|
| rc=0 | 30 | literal、nullary-first、scalar 等 |
| `lower_array_make`（F7） | 30 | payload-first / all-payload / single 的 push/make/makei/map/filter |
| 其他签名 | **0** | 没有第四个 debug 签名 |

这与 F7 已记录的条件表一致：literal 不走空数组分配；nullary-first 的 enum
是 nullable，不触发；scalar 控制不触发。也就是说，**这个邻域已经被 F7
条件表覆盖得比较完整**，60 个新程序只是再次确认边界，没有新根因。

## 这次 pilot 说明了什么

1. **issue→oracle 是可行的**：F5 的“格式化不变量”和 F7 的“构造方式等价”
   都能写成与 witness 无关的性质，并在新程序上运行。
2. **但历史 issue 的邻域很可能已经饱和**：F7 的 60 个邻居全部落在已知条件
   或已知签名里；F5 的 25 个模板也没有新破坏。继续在旧邻域加样本，收益低。
3. **要发现新根因，应该把 oracle 迁移到新表面**，而不是继续扩旧 witness：
   - F7 的构造等价 → `Option/Result`、嵌套数组、`FixedArray`/`ArrayView`、
     多 enum 字段、4/8 字段布局；
   - F5 的往返/幂等 → 可选参数、label、guard、doc comment、泛型；
   - 没有历史 issue 的表面：trait object / 可变别名 / 指针、Float32/NaN、
     async 随机 3–4 层 + 取消、优化器四cell。
4. **负结果要保留**：60/60 和 25/25 不支持“moonc 没问题”，只支持
   “在这个邻域、这个 oracle 下没有新反例”。

## 复现

Pilot 脚本在 `/tmp/pilot_issue_oracle/`（临时，不入主分支）：

```bash
python3 /tmp/pilot_issue_oracle/fmt_roundtrip.py   # 25 templates
python3 /tmp/pilot_issue_oracle/f7_gen.py          # 60 cases, 3 targets release
python3 /tmp/pilot_issue_oracle/f7_debug.py        # same 60, native debug
```

F7 结果：`/tmp/pilot_issue_oracle/f7/results.jsonl`（release）与
`/tmp/pilot_issue_oracle/f7/debug_native.jsonl`（debug）。
Formatter 结果：`/tmp/pilot_issue_oracle/fmt/results.jsonl`。

这些是临时证据，不替代 `poc/`、`regress` 或 `lspregress` 的正式回归。
