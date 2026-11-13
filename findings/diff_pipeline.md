# 差分测试流水线：从 0% 可运行到有产出

> 上一轮的教训：`--diff` 早就接通了，但 0 个发现。原因不是 oracle 不行，是**输入到不了 oracle 面前**。
> 本文记录按"先补前置条件"的顺序做的事、量化指标和产出。

---

## 1. 第一步：5 个手写探针（30 分钟）

目的：先回答"是没跑起来，还是跑了但一致"。

| 探针 | 语义面 | wasm | js | 结论 |
|------|--------|------|----|------|
| p1_int | Int 溢出/除法/取模/移位 | run | run | **SAME** |
| p2_float | Double NaN / -0.0 / 0.1+0.2 / 1/3 | run | run | **SAME** |
| p3_string | Unicode 长度/切片/插值 | run | run | **SAME** |
| p4_struct | struct + derive(Show, Eq) | run | run | **SAME** |
| p5_match | enum 匹配/守卫/元组匹配 | run | run | **SAME** |

结论：**不是"没跑起来"，是"跑了而且一致"**——但同时探针在加边界时咬到了第一个真实分歧（见 §5 D1）。这正好说明：基础语义面 codegen 很稳，分歧集中在**边界值**。

顺带确认了两个未知：

| 未知 | 结论 |
|------|------|
| native 后端是否可用 | 可用：`moon run cmd/main --target native` 正常输出（走 cc + libmoonbitrun.o） |
| wasm-gc 怎么跑 | 可用：`moon run --target wasm-gc`，由 `moonrun` 执行；25 个模板三后端全一致 |

---

## 2. 第二步：模板 + 函数体变异 + 强制可运行门槛

### 2.1 输入形态

每个模板固定骨架，只留一个 `compute` 函数体作为变异区：

```moonbit
fn compute() -> String {
  ...          // ← 只有这里被变异
  "..."
}
fn main { println(compute()) }   // ← 永远在
```

- 模板集：`templates/`，**25 个**，覆盖 int/float/string/struct/enum/array/option/result/
  loop/closure/trait/generic/char/bytes/recursion/math/tuple/escape/int64/boundary/trap。
- 确定性：模板里禁止 HashMap 迭代序、时间、随机数、地址；输出全部是固定字符串。

### 2.2 变异

两档：
- **gentle（默认 85%）**：只做"类型安全"的操作——整型/浮点/字符串字面量替换成边界值、
  同类运算符互换（`+`↔`-`↔`*`、`==`↔`!=`、`&&`↔`||`）、配平小块复制；
- **aggressive（15%）**：复用之前的通用变异子（token 替换、语句插入、包裹）。

第一版全用 aggressive，可运行率只有 25.6%；切到 gentle 后到 **72%**。

### 2.3 门槛与分类

一次执行 = 两个（或三个）后端各自 `build-package → link-core → run`：

| 分类 | 条件 |
|------|------|
| `SAME` | 两端都跑通，stdout 完全一致 |
| `FORMAT_DIFF` | 两端都跑通，数值归一后一致（`1` vs `1.0`、`-0` vs `0`、`nan` 大小写） |
| `REAL_DIFF` | 两端都跑通，归一后仍不同 → **真误编译候选** |
| `TRAP_DIFF` | 一端跑通、另一端 runtime trap/异常 → **后端语义分歧候选** |
| `WASM_BUILD` / `JS_BUILD` / `*_LINK` / `*_RUN` | 停在具体阶段，用于算可运行率 |

`TRAP_DIFF` 单独归类很重要：`Int::min / -1` 这种在 wasm 里是规范 trap，在 js 里可能是回绕，
不能和"误编译"混在一起统计。

---

## 3. 指标

| 阶段 | 输入形态 | 执行数 | 双后端跑通 | 可运行率 | REAL | FORMAT | TRAP |
|------|----------|-------:|-----------:|---------:|-----:|-------:|-----:|
| 改造前（旧 fuzz 语料抽样 100） | 随机变异体 | 100 | 0 | **0.0%** | 0 | 0 | 0 |
| 模板 + aggressive 变异 | 25 模板 | 115,674 | 29,593 | 25.6% | 0 | 0 | 0 |
| 模板 + gentle 变异 | 25 模板 | 32,160 | 23,080 | **71.8%** | 0 | 0 | **10** |
| 模板 + gentle + 语义去重 | 25 模板 | 9,705 | 6,978 | 71.9% | 0 | 0 | 2（去重后 1 类） |

- 可运行率：**0% → 71.8%**（目标 50%+ 达成）；
- 差分候选：**3.11 / 万次执行**（全部是 TRAP 类），真误编译 0；
- 失败分布：build 8,191、run 889（双端都 trap，多半是除零）、link 0。

### 3.1 三后端

25 个模板在 **wasm / js / wasm-gc** 上逐字节一致；`--triple` campaign 正在跑，
用来观察 wasm-gc 是否引入新的 trap 分歧。

---

## 4. 去重问题（下一步要修）

最初按内容哈希存目录，10 个候选存成了 6 个目录，全是同一根因（`d = -1` 触发 `Int::min / -1`）。

已改成按 **(分类, 归一化输出对)** 做语义去重：9,705 次执行里 2 个候选归并为 **1 类**。
这样"候选/万次执行"才不虚高（2.06/万次 vs 去重前的 3.11/万次）。

---

## 5. 产出：D1（跨后端语义分歧）

```moonbit
fn main {
  let a = -2147483648
  println((a / -1).to_string())
}
```

| 后端 | 行为 |
|------|------|
| wasm | `RuntimeError: divide result unrepresentable`（trap，退出码 1） |
| js | `-2147483648`（回绕，退出码 0） |
| wasm-gc | 同 wasm（trap） |

由 fuzzer 自动复现：模板 `21_trap_div` 的 `let d = 3` 被变异成 `-1` 后触发，
10 次/32k 执行的命中率与手写探针一致。

**定性待确认**：需要对照 MoonBit 规范——`Int` 除法溢出是"陷阱"还是"回绕"。
若是陷阱 → js 后端应改成 trap；若是回绕 → wasm 后端应显式文档化目标差异。
不管哪种，这都是一条应该在文档/测试里被固定的语义。

---

## 6. 复现

```bash
# 探针（5 个手写程序，含 D1 复现）
python3 harness/difftpl.py probe /tmp/diffprobe

# 模板自检（25 个模板 × 2/3 后端，应全部 SAME）
python3 harness/difftpl.py probe templates --triple

# 差分 campaign
python3 harness/difftpl.py run --workers 64 --duration 300
python3 harness/difftpl.py run --workers 64 --duration 300 --triple   # 加 wasm-gc

# 历史语料的可运行率（基线对比）
python3 harness/difftpl.py rate out/corpus --limit 100
```

产物：`out/diff/diffs/{REAL_DIFF,FORMAT_DIFF,TRAP_DIFF}/<hash>/{case.mbt,meta.json}`。

---

## 7. 下一步

1. **语义去重**：按 (模板, 分类, 输出对) 归并，重算"候选/万次"。
2. **补模板**：wasm-gc 特有语义（GC 类型、`String` 与 `Bytes` 边界）、native 的
   `Int`/`Float` 行为、以及 `try/raise` 的跨后端差异。
3. **把模板接到主 fuzz 循环**：`mbtfuzz.py` 的 T3 现在只跑冻结的种子程序；
   改成"模板 + body-only 变异"后，T3 的输入才真正可运行（当前 T3 命中率 9k/608k ≈ 1.5%）。
4. **native 纳入差分**：单独验证（构建成本高），先做夜间批处理。
