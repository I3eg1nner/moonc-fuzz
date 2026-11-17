# 下一阶段改进的成本与缺陷发现收益评估

日期：2026-11-17。工具链：`moon 0.1.20261104`、`moonc v0.10.20+65efd5b93`。
机器：128 vCPU，1.0 TiB RAM；以下 wall time 都是本机实测，不可直接外推。

逐 artifact 的聚合数据在 `findings/improvement_evaluation_data.json`。

这份报告只回答两个问题：

1. 当前四条路线继续加样本，边际成本是多少；
2. 在已有零结果上，继续投入是否还可能达到“发现真实缺陷”的预期。

它不是编译器正确性结论。零候选只说明“在这批包、这批测试、这个 seed 下没有观察到状态差异”。

## 1. 实验设计与原始数据

### 1.1 真实包：从 3 包扩到 142 个包目录

`seeds/` 下有 142 个含 `moon.pkg` 的目录（不是 54 个顶层目录）。对每个目录单独运行：

```bash
optdiff --module /data/audit/mbtfuzz/seeds \
  --out /tmp/eval-all2/<tag> \
  --packages moonbitlang/core/<rel> \
  --target wasm-gc --four-cell --repeats 1
```

12 路并行，全部目录跑完 wall time 约 81 s，临时目录 5.2 GB。

分类：

| 结果 | 数量 | 含义 |
|---|---:|---|
| 进程 exit 0 | 93 | 四格完整跑通 |
| `cannot parse four-cell runtime commands` | 37 | 没有可重放的 test driver / 零测试，四格不适用 |
| `test run invalid` | 7 | async/native 语义包，wasm-gc 测试不成立 |
| 其他 | 5 | 3 个 async 包 + `diff`/`test` 的测试环境问题 |
| 有有效 artifact 的包 | **94** | 下面统计的有效分母 |
| 有效 artifact | **162** | 每个 artifact 有四格 |
| 有效 test ID | **8,849** | 来自测试 metadata，不是估计值 |
| candidates | **0** | 没有状态差异 |
| changed | **0** | 同上 |

失败包不能被计入“零候选”：37 个没有 runtime，7 个测试本身无效，5 个环境/测试失败。它们既不是通过，也不是缺陷。

### 1.2 四格不是空转：162/162 个 artifact 的 code section 都变了

对每个有效 artifact 取四个 wasm 的 section 10（code section）哈希：

| 对比 | 有差异的 artifact |
|---|---:|
| `B0L0` vs `B0Ld`（仅 link 默认） | 162 / 162 |
| `B0L0` vs `BdL0`（仅 build 默认） | 162 / 162 |
| `B0L0` vs `BdLd`（两者都默认） | 162 / 162 |
| 四臂 code section 全同 | 0 / 162 |

build 侧 core 文件也有实际变化：有效包的 4,449 对 O0/default core 中，3,729 对哈希不同（720 对相同）。这说明 `Bd*` 不是只改了路径。

code section 大小中位数：

| 臂 | code size / `B0L0` |
|---|---:|
| `B0Ld`（link 默认） | 1.008 |
| `BdL0`（build 默认） | 0.927 |
| `BdLd`（都默认） | 0.934 |

即 build 默认让 code section 中位数缩小约 7%，link 默认让它增大约 0.8%；两种变换都真实发生。注意：section 哈希不同只证明“编译器产出了不同字节码”，不证明语义一定改变；语义是否改变仍由测试状态判定。

### 1.3 IR：1,008 例，0 错误，但只有 9 种结构组合

运行：

```bash
irprobe /data/audit/mbtfuzz /tmp/eval-ir1000 \
  --four-cell --random 1000 --seed 2026
```

结果：

| 指标 | 值 |
|---|---:|
| cases（8 手写 + 1,000 随机） | 1,008 |
| `ok` | 1,008 |
| 四臂 reason 非 `ok` | 0 |
| wall time | 340.04 s |
| 单例成本 | 0.337 s |
| 输出体积 | 59 MB |

四臂 code section 也都有变化：link 1,008/1,008，build 1,005/1,008，both 1,008/1,008。

但 1,000 个随机样本的特征分布是：

| 特征 | 出现率 |
|---|---:|
| bounded loop / `if` / `return` / `choose` / `abs` / `let mut` / `Emit` | 100% |
| 数组（`Array[Int]`） | 69.6% |
| `Len`（emitter 的 `.length()`） | 68.6% |
| 数组别名 `b = a` | 35.1% |
| 除法、浮点、字符串、闭包、泛型、trap、嵌套函数 | 0% |

按“数组个数 × 是否有别名 × loop 条件是否用 Len × loop 内是否有 if × 末尾是否有赋值 if”粗分，1,000 例只落在 **9 种结构组合**：

```
(2, alias, loop-if, final-if)  191
(1, no-alias, loop-if, final-if) 169
(0, no-array, loop-if, final-if) 157
(2, alias, loop-if, no-final)   98
(1, no-alias, loop-if, no-final) 96
(0, no-array, loop-if, no-final) 86
(1, no-alias, no-loop-if)        80
(2, alias, no-loop-if)           62
(0, no-array, no-loop-if)        61
```

所以“1,000 例”不能当作 1,000 个独立程序。它们主要是同一个 `main` 模板上的常量、分支、数组大小变化；有效结构多样性远低于样本数。

### 1.4 native：build/link 两维都真实改变产物

先做 link-only 抽查（不修改仓库代码）：对 5 个包 `argparse/json/list/bigint/string`，捕获 `moonc link-core` 和 `/usr/bin/cc`，只做 link O0/default 两臂，直接运行生成的 native 测试可执行文件。

| 指标 | 值 |
|---|---:|
| 包 | 5 |
| artifact | 13 |
| native link L0/Ld 状态差异 | 0 |
| 每个 artifact 的 native object 大小是否变化 | 13 / 13 |
| 5 包串行 wall time | 34.3 s |
| 单包 wall time | 3.8–11.1 s |

随后对 `argparse` 做了完整四臂原型：先构建 O0，再把 default 树里的 45 个 `.core` 全部删除，重放 45 条去掉 `-O0` 的 `build-package` 命令，再分别链接/运行四臂。

| 指标 | 值 |
|---|---:|
| build-package 重放 | 45 |
| O0/default core 哈希相同 | 8 / 45 |
| O0/default core 哈希不同 | **37 / 45** |
| artifact | 3 |
| 测试 | 164 |
| 四臂输出差异 | 0 |
| 单包 wall time | 10.4 s |

native object 大小也随 build/link 改变，例如 `argparse.blackbox_test`：

```
B0L0  9,944,752
B0Ld  9,895,160
BdL0  9,813,656
BdLd  9,741,960
```

结论修正：native 的 **build 维度不是空转**；之前“45/45 相同”的原型重放了 O0 路径且未删除旧 core，属于缓存/路径错误，已作废。native 需要四格，不能只做 link-only。

这个原型的限制：

- 没有 native 正控（没有做源码注入并验证测试能捕获）；
- 没有 timeout/truncation 分类，只比较了 rc 和 stdout；
- 只覆盖 1 个包的完整四臂和 5 个包的 link-only，不能外推到全部 native 包；
- 没有把 native 适配器接进 `optdiff`，只是可行性原型。

## 2. 成本模型

### 2.1 直接测量

| 实验 | 规模 | wall time | 临时空间 | 换算 |
|---|---:|---:|---:|---|
| 真实包四格 | 162 artifact | 81 s（12 路） | 5.2 GB | ≈6 CPU-s/artifact，≈0.5 s/artifact（12 路） |
| IR 四格 | 1,008 case | 340 s（串行） | 59 MB | 0.337 s/case，≈3 case/s |
| native link-only | 13 artifact / 5 包 | 34.3 s（串行） | 未统计 | ≈2.6 s/artifact，含构建 |
| native 四格 | 3 artifact / 1 包 | 10.4 s（串行） | 未统计 | ≈3.5 s/artifact，含构建 |

### 2.2 下一步改动的实现成本

| 改动 | 代码/实验成本 | 实测或估算 | 主要风险 |
|---|---|---|---|
| 继续加 IR seed，1k → 30k | 0 行代码 | 2.8 h 串行；12 路约 15 min；约 1.8 GB | 9 种结构组合不变，信息增量低 |
| 给 IR 增加一类特性（字符串/浮点/trap/嵌套函数） | 300–600 行 + 测试，2–4 天 | 需要同时改 typechecker、interpreter、emitter、generator、reducer | emitter/interpreter 先出现自洽性错误，掩盖编译器问题 |
| IR 改成多模板生成（不增加类型） | 100–200 行 + 测试，1–2 天 | 可把“9 种组合”扩成矩阵；现有 0/1000 才有可比性 | 模板设计仍有偏置 |
| native 四格 adapter | 200–300 行 + 正控/测试，1–2 天 | 1 包 10.4 s；94 个有效包估计 16 min 串行 / 1.5 min（12 路） | `cc` argv、runtime 路径、test args 解析；正控必须补 |
| 真实包扩到 300/3,000 artifact | 主要是语料获取 | 300 约 2.5 min（12 路）；3,000 约 25 min（12 路） | 当前 core 只有 162 个有效 artifact，需外部包；测试质量不可控 |
| 真实包增加随机输入/多配置 oracle | 1–2 周 | 需要逐包 API/输入模型 | 成本高，但可能比加包更有效 |

代码量基线：`cmd/optdiff` 2,575 行；`ir/` 核心 1,225 行；`cmd/irprobe` 659 行；`oracle/` 710 行。

## 3. 未来缺陷发现：样本量与概率

### 3.1 零结果的置信上限

对 0 次观察，rule-of-three 的 95% 上限约为 `3/n`：

| 样本 | 0 次观察 | 95% 上限 |
|---|---:|---:|
| 162 个有效 artifact | 0 | 1.85% / artifact |
| 1,008 个 IR case | 0 | 0.30% / case |

这不是“缺陷率低于上限”的证明；它只给出在独立同分布假设下的保守上界。真实包和 IR 的“独立”假设本身就不成立（同一模板、同一测试套件、同一编译器）。

### 3.2 如果真实缺陷率是 p

零观察概率 `(1-p)^n`：

| n | p=1/100 | p=1/1,000 | p=1/10,000 |
|---:|---:|---:|---:|
| 162 artifact | 19.6% | 85.0% | 98.4% |
| 1,008 IR case | 0.004% | 36.4% | 90.4% |

要达到 95% 的“至少发现一次”概率，需要约：

| 真实率 | 需要样本 |
|---:|---:|
| 1/100 | 299 |
| 1/1,000 | 2,995 |
| 1/10,000 | 29,956 |

因此：

- 162 个 artifact 的零结果，**不能排除** 1/1,000 的缺陷率，甚至不能排除 1/100；
- 1,008 个 IR case 的零结果，对 1/1,000 也只有 36% 的零概率，样本量并不算大；
- 但继续加 IR seed 的问题不是样本量，而是**有效结构只有 9 种**，`(1-p)^n` 的独立性假设不成立。

### 3.3 成本换期望发现数（仅为假设）

若把 artifact/case 当作独立机会：

| 路线 | 1/1,000 率下的期望发现 | 1/10,000 率下的期望发现 | 达到 1 个期望发现所需 |
|---|---:|---:|---:|
| 真实包（162 artifact，81 s） | 0.16 | 0.016 | 约 6 倍语料 / 8 min |
| IR（1,000 case，5.7 min） | 1.0 | 0.1 | 1,000 case / 5.7 min |
| native link-only（13 artifact，34 s） | 0.013 | 0.0013 | 约 77 倍语料 / 44 min |

这些数字不是预测，只是把“时间 × 假设率”摆出来。它们说明：**在相同假设下，IR 的单位时间机会最多；但 IR 的结构多样性最差，真实包的结构多样性最好。** 两者不能直接相加。

## 4. 结论：是否达到预期

### 4.1 如果预期是“低成本、可复现地找到真实编译器缺陷”

**当前证据不支持。** 具体理由：

1. 162 个有效 artifact、8,849 个测试、0 candidate；四格 code section 162/162 都变，说明不是空转，但仍无状态差异。
2. 1,008 个 IR case、0 错误；但 1,000 个随机样本只有 9 种结构组合，且缺少除法、浮点、字符串、闭包、泛型、trap、嵌套函数。
3. native 原型证明 build/link 两维都会改变产物，但没有正控，也没有跨包缺陷证据。

零候选不能证明优化器正确；同样，也不能支持“再加同样的样本就会出缺陷”。在 1/1,000 的假设下，现有 162 个 artifact 有 85% 概率全零，1,008 个 IR case 有 36% 概率全零，所以当前结果既不意外，也不足以定论。

### 4.2 如果预期是“形成可复用的负证据 + 明确下一步边界”

**部分达到。** 真实包部分比 IR 部分强：

- 94 个包、162 个 artifact、8,849 个测试是有效分母；
- 四格 build/link 两维都真实改变 code section；
- 失败包被显式分类，没有混入零候选；
- native 原型明确了“build/link 两维都活、但缺正控”的边界。

但还不足以写成“优化器在这些包上正确”的论文级结论，因为测试是固定断言，不是随机输入；也没有 branch/edge 覆盖。

### 4.3 建议的投入顺序

1. **做 native 四格 adapter，而不是 link-only。** 37/45 个 core 在 O0/default 下不同，build 维度真实存在；只做 link-only 会丢掉一半机制覆盖。预计 1–2 天，能覆盖一个与 wasm 不同的后端。
2. **先改 IR 模板矩阵，再扩类型。** 现在 1,000 例只有 9 种组合；用 100–200 行把控制流/数组/别名/循环条件做成显式模板，比直接加字符串/浮点更便宜，也更能解释 0/1000。
3. **在做大语料前，先测测试套件的变异杀伤率。** 8,849 个测试是否能发现实现级变化，目前只有 argparse/json 两个注入控制；如果测试对变异不敏感，扩到 3,000 个 artifact 也只是增加零候选。
4. **最后再考虑字符串/浮点/trap/嵌套函数。** 这些会同时改类型系统、解释器、emitter 和 oracle，成本 2–4 天，且可能先暴露 harness 自洽性问题，而不是编译器问题。

**不建议**把下一轮预算花在“同样生成器再加 10k seed”或“同样测试再跑更多 wasm-gc 包”上；这两项的边际信息最低。

## 5. 可复现命令

真实包：

```bash
# 142 个含 moon.pkg 的目录，逐个运行；12 路并行
find /data/audit/mbtfuzz/seeds -name moon.pkg -printf '%h\n' \
  | sed 's#^/data/audit/mbtfuzz/seeds/##' | sort \
  | xargs -P 12 -I{} /tmp/eval-one.sh '{}'
```

IR：

```bash
moon run cmd/irprobe -- /data/audit/mbtfuzz /tmp/eval-ir1000 \
  --four-cell --random 1000 --seed 2026
```

native link-only 原型是 `/tmp/native_link.py`，native 四格原型是 `/tmp/native_full2.py`；两者都不是仓库交付物，只用于本轮可行性测量，不能当作 native 四格已接入。

## 6. 边界

- 函数级/测试级状态比较，不是分支覆盖、行覆盖或可行路径覆盖。
- `default` 是省略 `-O0`，不是显式 `-O2`，也没有切换到 `assert_release.mbt`。
- code section 哈希不同只证明产物不同，不证明语义变化。
- 162 个 artifact 的 0 candidate 不是“无缺陷”；IR 的 0/1,008 也不是“IR 正确”。
- native 原型没有正控、没有 timeout/truncation 分类；完整四格只覆盖 1 个包，link-only 覆盖 5 个包。
- 所有时间数字都绑定本机、当前工具链和当前缓存状态。
