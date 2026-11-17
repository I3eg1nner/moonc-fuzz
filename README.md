# moonc-fuzz

[![ci](https://github.com/I3eg1nner/moonc-fuzz/actions/workflows/ci.yml/badge.svg)](https://github.com/I3eg1nner/moonc-fuzz/actions/workflows/ci.yml)

面向闭源 MoonBit 编译器 `moonc` 的黑盒/灰盒测试工具，主分支实现为
MoonBit。Python 参考实现和归档 pilot 在 `python-reference` 分支，不参与
主分支构建或验收。目前复现 6 个缺陷（F1–F6）和 1 个 formatter 性能异常
（P1），7 个 issue 已提交至 `moonbitlang/moonbit-docs`；另在固定版本上复现
3 个上游仍开放的链接期 ICE（F7/F8/F9）。

- 仓库：<https://github.com/I3eg1nner/moonc-fuzz>
- 包：<https://mooncakes.io/docs/I3eg1nner/mbtfuzz>（`moon add I3eg1nner/mbtfuzz`）
- 许可证：Apache-2.0
- 固定工具链：`moon 0.1.20261104 (940aa18)`、`moonc v0.10.20+65efd5b93`、
  `moonrun 0.1.20261104`
- 当前覆盖结果：`camlMoonc*` 函数符号 7,916 / 26,611 = 29.75%

## 1. 方法

`moonc` 当前发行版无法由公开源码构建。二进制未 strip，`nm` 可见约 3 万文本
符号，因此采用以下组合，而不是纯黑盒随机测试：

- **T1**：`moonc syncheck`，覆盖 lexer/parser。
- **T2**：`moonc build-package`，覆盖 typer、core IR 和 wasm codegen。
- **T3**：`link-core` + `moonrun`/`node`，并做 wasm/js、wasm/native 差分。
- **覆盖**：QEMU `-d exec` 记录 PC，按 `nm -n` 最近前置符号归因到函数；
  T1/T2/T3 候选进入有界后台 trace 队列，按阶段和配置计算真实增量后
  才保留输入并奖励父本。
- **oracle**：崩溃/ICE/OOM/超时分类；跨后端阶段感知判定；JSON 诊断签名。
- **变异**：括号/字符串配平的 token 级变异，以及字节级无效 UTF-8 变异。

覆盖率是**函数符号级**，不是源码行、分支或可行代码覆盖。分母包含
8,038 个匿名闭包和 4,200 个 Menhir action。

## 2. 快速开始

需要 `moon`/`moonc`，版本不低于 0.10.16；本文数据固定在 0.10.20。

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

完整仓库包含复现脚本、PoC 和第三方 fixture：

```bash
git clone https://github.com/I3eg1nner/moonc-fuzz.git
cd moonc-fuzz
./scripts/fetch_assets.sh          # F6 第三方包；seed 语料可选
./scripts/reproduce_all.sh         # 逐个复现缺陷

cd moonbit
moon test
moon run cmd/accept -- /path/to/moonc-fuzz
```

启动一个 campaign（每次都会增量构建，不复用过期二进制）：

```bash
./run.sh hybrid 8 120          # T1 + 采样 T2/T3，默认
./run.sh parser 8 120          # 只跑 lexer/parser
./run.sh typer 8 120           # 解析通过的输入都进 typer
./run.sh semantic-diff 4 120   # 每个可构建输入都做 wasm/js 差分
SEED_DIR=$PWD/templates ./run.sh typer 8 120   # 用可运行模板作为种子
```

trace 候选权重默认 T2 70%、T1 20%、T3 10%，调度器同时按 70/20/10 的
完成时间份额约束，并把在飞任务的预留时间计入份额；没有其他阶段候选时
借用份额，暂不可调度时等待而不是清空队列。3 个后台 worker 消费一个有界
队列，`TRACE_CPU=25` 限制自适应 trace 时间。运行目录是
`out/mb_runs/<UTC 时间>-<pid>/`，包含 `manifest.json`、`stats.jsonl`、
`summary.json` 和 `trace_failures.jsonl`。

最小可运行示例（`nm -n` + QEMU `-d exec` 日志 → 函数集 JSON）：

```bash
./examples/trace2funcs.sh
```

`cmd/accept` 依次检查：工具链 pin、`moon build`、`moon test`、`moon check`、
12 例缺陷回归、合成 trace 精确输出、真实 QEMU trace 的 599 函数集合、
覆盖并集、25 个模板的 wasm/js 差分、负控制。任一项失败即非零退出。

仓库不提交 `out/`、`seeds/`、`assets/`、`moonbit/_build/` 和 12 MB 的
`WeiR-h/moonldif@0.7.6`。F6 另有 10 行最小复现，不依赖下载。

## 3. 目录

```
harness/        运行时资产：all_pkgs.json、moonbit.dict、tpl/
moonbit/        MoonBit 主实现：trace/cov/mutate/exec/corpus/oracle + cmd/*
                + featuregen/（native 布局矩阵）、asyncgen/（async 状态机矩阵）
poc/            每个缺陷的最小复现和版本说明
templates/      25 个可运行程序，用于跨后端差分
findings/       技术报告、验证记录、外部 review、负证据
issues/         对外 issue 草稿
scripts/        资产下载、一键复现、特性探针
run.sh          MoonBit fuzz 入口
```

## 4. 缺陷

11 个 PoC（含 F6 外部包）在固定版本上全部复现。独立复验（2026-11-13）未发现
假阳性，并排除了四类误报来源：文件不存在、cwd 错误、缺 core library、
`_build` 缓存；F2 和 F6 另在全新副本上重跑。同一轮复验修正了 8 处数字或措辞
过度声明（见 `d1447bd`），`scripts/reproduce_all.sh` 也从“打印 rc”改为带断言
的 13 项检查。

每个 PoC 的完整命令和预期输出见 `poc/<id>/README.md`，索引见 `poc/README.md`。
7 条 issue 已提交到 `moonbitlang/moonbit-docs`
（[#1364](https://github.com/moonbitlang/moonbit-docs/issues/1364) 到
[#1370](https://github.com/moonbitlang/moonbit-docs/issues/1370)）；该仓库是
ICE banner 指定的入口，`moonbitlang/moonbit-compiler` 的 Issues 处于关闭状态。

| ID | 最小输入 | 结果 | 复现 | 口径 |
|---|---|---|---|---|
| F1 | 101 B `moon.pkg` | SIGSEGV，rc 139 | 3/3 | 限定：显式 `syncheck`，根因未证 |
| F1b | 672 B `moon.pkg` | SIGSEGV | 3/3 | 同帧 witness，不单列根因 |
| F2 | 38 B 源码 | `moon check` rc 1，ICE | 3/3 | 可直接引用 |
| F2b | `\` + U+200B | syncheck 0；build-package 199 | 3/3 | 阶段分裂 witness |
| F3 | 19 B 源码 | 6 GiB cap 下 5.66 GiB、rc 134 | 2/2 | 可直接引用：有界资源耗尽 |
| F4 | 40 B `.mbt.md` | rc 199 | 3/3 | 可直接引用：解码 ICE |
| F4b | 6.7 KB `.mbt.md` | rc 199 | 3/3 | 同异常类 witness |
| F5 | 前缀 `+` | parse 0；check 2；fmt 后 reparse 2 | 5/5 | 限定：语法往返 |
| F6 | 10 行单包 | `moon build --target native` rc 255 | 3/3 | 限定：链接期诊断缺陷 |
| P1 | 2,048 段插值 | 15.1 s vs 纯串 7 ms | 3+5 | 限定：两点实测，不推阶数 |

F7/F8/F9 是**上游仍开放**的链接期 ICE，不计入 F1–F6 的“已修复”集合：F7 是
native debug 下 `#valtype` 记录（标量 + 含 GC 引用的 enum）经 `Array::push`
触发 `lower_array_make` ICE；F8 是 async 挂起后调用 `raise?` 参数触发
`link-core` 断言；F9 是 native debug 下 `extern "C"` stub 接收 `V128` 触发
`finish_stub_wrapper_shell` ICE。最小复现见 `poc/f7_valtype_array_ice/`、
`poc/f8_async_raise_ice/`、`poc/f9_native_v128_stub_ice/`；覆盖缺口分析见
`findings/coverage_depth_review.md`，独立 codex 复验见
`findings/codex_open_ice_review.md`。

对外口径按证据强度分三档：

- **可直接引用**：F2 的 T1/T2 阶段分裂与 ICE、F3 在固定上限下的内存耗尽、
  F4 的 `.mbt.md` 解码 ICE、P1 的实测曲线。
- **发布前限定措辞**：F1 仅限显式 `moonc syncheck moon.pkg`；F1b/F2b/F4b 是
  同签名 witness，不声称独立根因；F5 限语法往返，不是语义错误；F6 是链接期
  诊断缺陷，不是 miscompile。
- **仍需补实验**：根因身份与独立缺陷数、F3 无上限时的终止性、P1 的复杂度
  阶数、F5 的全矩阵。

F1 的已确认影响面仅限显式 `syncheck`：同一文件交给 `moon build`/`moon check`
时，`moon` 用自己的配置解析器，正常报解析错误（rc 255）。F6 外部包的 `.core`
可生成，包级 `moon build --target native src` 成功，native/js 包级测试均通过；
模块级 native build 和测试链接失败。

F1b/F2b/F4b 是额外 witness，暂按栈或异常签名归入 F1/F2/F4，不声称新的根因类。

## 5. 覆盖率与对拍

| 项目 | 结果 |
|---|---|
| 冻结函数覆盖 | 7,916 / 26,611 = 29.75% |
| 第三方包覆盖下界 | 4,455（16.74%），对基线 +42；7,958 = 29.90% |
| trace → 函数集 | 1,864 / 1,354 / 599，与 Python 版本集合完全一致 |
| 覆盖并集 | 6,547，与 Python 版本一致 |
| 跨后端模板 | 25/25 在 wasm/js 都到 `run` 且输出一致 |
| 第三方测试 | 12 包 × 5 target；3,503/3,503 pass（wasm/wasm-gc/js） |

覆盖口径、深度缺口与本轮 F7/F8/F9 的边界见 `findings/coverage_depth_review.md`。
改进成本与样本量评估见 `findings/improvement_evaluation.md`：有效真实包
162 个 artifact、8,849 个测试、0 candidate；IR 12,096 例（v1）/ 12,096 例（动态索引 v2）、0 错误；
native 四格：111 个有效包、184 个 artifact、9,249 个 test ID、0 个确认候选；`async/http` 的网络候选经 `--repeats 3 --aa` 复核后消失；111 包 `repeats=2 --aa` 复核为 0 candidate/0 changed（`diff` blackbox baseline 不绿）。另跑 native `--llvm-opt 3`：184 artifact、9,249 test ID、0 candidate。JS 四格：103 个有 evidence 的包、173 artifact、9,031 test ID、0 candidate；`repeats=2 --aa` 为 0 candidate/0 changed（`diff` blackbox baseline 不绿）。详见 `findings/native_fourcell.md`、`findings/js_fourcell.md`。

trace 转换器的 native release 实现在 101 MB check trace 上约 0.48 s，
Python 参考约 1.80 s。该数字仅指转换器，不代表整体吞吐。

### 5.1 精确 TB 块/边覆盖

`trace/summarize_trace` 现在同时输出 QEMU TB 级精确计数：`unique_pc`、
`mapped_unique_pc`、`edges`、`mapped_edges`，以及按函数排序的
`func_depth[{func, blocks, edges}]`。去重使用精确 PC 和精确 `(pc_i, pc_i+1)`
对，不是有损 bitmap。这是 **TB 转移覆盖**，不是源码行/基本块/分支覆盖：
QEMU TB 边界不等于源码分支，因此不报“分支覆盖率”百分比。定义、示例与不做
的声明见 `findings/exact_block_coverage.md`。

### 5.2 特性定向搜索与负证据

下一阶段的三个工具及其边界：

| 工具 | 作用 | 已验证结果 |
|---|---|---|
| `cmd/featfuzz` + `featuregen/` | 160 个 curated native 布局 case，分阶段 check→build→test --build-only→test | 100 case：90 OK / 10 ICE，唯一签名是已知 F7 `lower_array_make`，plain struct 控制全过 |
| `cmd/asyncfuzz` + `asyncgen/` | 82 行 async 状态机矩阵，F8 作为带标签的正控 | 82 case：72 OK / 10 `known_f8`，0 新签名 |
| `cmd/verify` | 每次重复用全新副本，3/3 稳定性 + 控制组 | F9 debug 3/3 `reproduced`，release 3/3 `ok` |

跨后端执行差分（`cmd/xdiff`）对同一份生成源码在 wasm-gc/wasm/js/native 上
真正执行并比较规范化的 stdout 与 rc：160 个布局 case × 4 target 共 640 次构建、
620 次执行，得到 **140 ALL_EQUAL / 20 KNOWN_LINK_ICE / 0 OUTPUT_MISMATCH**；
20 个已知 ICE 全部是 native-only 的 F7 签名，四个字段族各 5 个操作，且每族的
plain-struct 控制在四个后端都 ALL_EQUAL。async 侧改为比较测试驱动的逐测试状态：
6 case × 3 target，15 次执行，**5 ALL_EQUAL / 1 KNOWN_LINK_ICE（F8）**，
无状态分歧。详见 `findings/xdiff_mvp.md`、`findings/xdiff_async.md`。

边覆盖已经进入调度：`feedback_upsert` 增加一个**严格小于**函数新颖度的加法奖励
（函数 32、边 8，能量上限 64 不变），边 key 宇宙有 200,000 的硬上限，达到上限
后置 `edge_saturated` 并停止计入，`new_edges` 来自真实集合差。6 秒冒烟 campaign
（1 worker、1 trace worker）得到 `edge_keys=41485`、`new_edges=3652`；把
`--edge-cap` 降到 64 时得到 `edge_saturated=true`、`new_edges=0`。这是调度信号，
**不是**缺陷发现效果的证明；`29.75%` 的函数口径没有改动。
详见 `findings/edge_feedback.md`。

独立探针（`scripts/probe/native_feature_probe.py`）跑了 269 个 native
布局/ABI/async case，**只**命中 F7/F8/F9 三个已知签名，没有第四个：
`findings/feature_probe_negative.md`。同一份记录还说明：并行跑大量 `moon`
会产出 `[4021]`/`[0055]` 一类**伪诊断**，串行重跑干净副本后均为 rc=0，
所以这类结果不能计入缺陷。这也是后续所有驱动默认低并发的原因。

第三方 native 结果中的环境/包问题与 F6 分开记录，见
`findings/thirdparty.md`。

## 6. MoonBit 主路径

`moonbit/` 是默认执行路径，包含：

- `trace/`、`cov/`：符号化和函数集代数；
- `mutate/`：结构感知变异；
- `exec/`：带硬超时的异步子进程；
- `corpus/`：种子遍历、SHA-1、finding 存储；
- `oracle/`：wasm/js 与 wasm/native 差分；
- `cmd/`：`trace2funcs`、`cov`、`fuzz`、`bytefuzz`、`diffprobe`、
  `regress`、`f6matrix`、`accept`、`optdiff`、`irprobe`、`featfuzz`、
  `asyncfuzz`、`verify`；
- `featuregen/`、`asyncgen/`：特性定向源生成器（native 布局矩阵、async 状态机矩阵）。

当前 195 个测试通过，`moon check` 无警告。GitHub Actions 在每次 push 和 PR
上跑 `moon check`、`moon build`、`moon test`、`moon fmt --check` 和最小示例。`cmd/regress` 覆盖 12 例缺陷；
`cmd/accept` 是迁移验收门禁。主分支不包含 `.py` 文件；独立参考实现和
`syntax_boundary`、`olddiff`、`iface`、`typegen` 等归档 pilot 位于
`python-reference` 分支，仅用于对拍和历史复现。

迁移细节和对拍数据见 `findings/migration_moonbit.md`。

### 6.1 campaign 内的反馈闭环

快速路径只负责产生候选；trace 流水线负责判断候选是否值得保留：

1. T1 用 `-error-format json`，签名保留 `error_code`、`message` 和 `loc`；
   不同诊断不再合并成 `ERR`。T1 正常接受/报错、T2 的接受/拒绝、T2 成功
   后的 link 都是候选。
2. 候选在提交时冻结源码、阶段和配置；后台 worker 在独立目录里重放完全
   相同的 argv，不读取正在被 fuzz worker 覆写的 `in.mbt`。
3. 有界队列默认 32，3 个 trace worker；T2 优先于 T3，T1 只使用半队列。
   份额计算包含已完成时间和在飞预留；缺少其他阶段候选时借用份额。
   `Wait`（暂时不可调度）与 `Closed`（生产者结束且队列为空）分开，
   前者不会清空队列。队列满、trace 超预算或日志超限都会记录，不伪装成
   “零覆盖”。
4. 覆盖按 `(config, stage, outcome)` 分开维护。只有
   `Coverage(x) − U` 非空才保存输入、更新 U、准入并发放覆盖 energy；
   无增量的重复 trace 不再次奖励。
5. 启动时先对少量种子测 U0，并用完成屏障冻结：baseline 未完成前候选结果
   只缓存，不计算增量。任一 baseline 失败或丢弃时，summary 标记
   `baseline_state=incomplete`，缓存候选转为 `baseline_unresolved`，不发放
   覆盖奖励；不会把部分 U0 当作完整基线。只有 `baseline_state=complete`
   时 `relative_new` 才是数字，否则为 JSON `null`，`observed_funcs` 仍保留。
6. T2/T3 分别统计 build 成功、run 完成、语义差分、纯运行期差分、接受性差分、
   编译器异常和 inconclusive；编译器异常和 inconclusive 不会以 `same=true`
   进入 finding。
7. 输出截断只作用于证据；完整 stdout 的 SHA-1 和字节数参与差分判定，截断后
   的后缀差异不会变成 `SAME`。
8. 源码按内容 SHA-1 写入 `corpus/<sha1>.mbt`；覆盖证据按
   `(input_hash, config_hash, stage, outcome)` 分文件写到
   `corpus/coverage/<stage>/<outcome>/`，行为证据写到
   `corpus/behavior/<sha1>/`，二者不互相覆盖。可用
   `--seed-dir <run>/corpus` 重放源码。

`cmd/diffprobe --inject` 对构建/链接故障做真实判定函数的注入检查。

## 7. 复现

```bash
./scripts/reproduce_all.sh
```

脚本按顺序执行 F1、F1b、F2、F2b、F3、F4、F4b、F5、F6-min；若
`assets/f6_external/moonldif` 存在，再执行 F6 外部复现。

F3 需要 `prlimit`，并限制在 6 GiB。不要在没有内存限制的共享机器上直接运行
uncapped 版本。

F6 外部包：

```bash
./scripts/fetch_assets.sh
cd assets/f6_external/moonldif
moon test --target native
```

## 8. 限制

- 不声称编译器正确性或代码生成成熟度；跨后端一致不等于正确。
- 不声称剩余函数不可达，也不把 29.75% 解释为可行代码覆盖率。
- F1 根因仍是基于符号和栈的假设；IDE/LSP 调用路径未验证。
- 旧编译器、接口往返、类型生成等 pilot 是有限样本的负结果，不是普遍结论。
- 诊断字符串数量不作为覆盖率；F6 不计为误编译。
- trace 由有界后台队列执行，默认 T2/T1/T3 候选权重 70/20/10，3 个 worker，
  队列 32；过载会丢弃并记录 `trace_dropped`。`TRACE_CPU=25` 是软预算，
  已在飞的 T3 trace 仍可能超出。
- 覆盖仍是函数级；同一函数内的新分支不会增加集合。T3 第一版没有种子基线。
- 60 秒 16-worker 校准写出 88,775 个文件（437 MB），feedback 父本增至
  45,546。现在父本池默认上限 20,000（`--parent-cap`，按 energy 淘汰、
  同 energy 先淘汰最旧），持久证据默认上限 2,000 个输入
  （`--persist-cap`，crash/ICE/diff candidate 不受限），
  `trace_failures.jsonl` 上限 2,048 行，T3 core 快照用后即删。文件数和
  父本选择开销因此不再随 campaign 时长线性增长，代价是保留的父本和证据
  变成有界样本；被淘汰的输入仍会被执行和计数，只是不再保留。细节、
  counter 和逐项文件审计见 `findings/campaign_caps.md`。
- 采集器返回非零时，只有带编译器诊断的退出才算正常拒绝。wrapper 保留的
  124–127 优先判为 `collector_failed`，即使命令已写出 OOM 文本；moonc 的
  199 ICE 仍保留为 `compiler_abort`。无诊断退出和信号也单独分类，失败记录
  保留 rc 和原因。
- campaign 的 T1/T2/T3 走 `run_isolated`：GNU `timeout` 负责进程组回收，
  `prlimit` 设地址空间上限（T1 2 GiB、T2 6 GiB、T3 4–6 GiB）。原始
  `@exec.run` 仍不隔离，formatter 等直连路径未覆盖；输出在收集后截断到
  1 MiB，但完整 stdout 的 SHA-1 和字节数参与差分判定。

## 9. 文档

| 文件 | 内容 |
|---|---|
| `poc/README.md` | 缺陷 PoC 索引、命令、预期结果 |
| `issues/README.md` | 上游 issue 草稿、已提交链接（#1364–#1370）、去重和顺序 |
| `findings/validation.md` | F1–F6/P1 多次复现表 |
| `findings/cov_audit.md` | 符号化、重放、并集口径审计 |
| `findings/thirdparty.md` | 12 包 × 5 target 测试与 triage |
| `findings/evidence_package.md` | 论文级证据包与声明边界 |
| `findings/migration_moonbit.md` | Python → MoonBit 迁移证据与验收 |
| `findings/feedback_loop.md` | 诊断签名、动态 corpus、coverage 反馈与故障注入记录 |
| [python-reference 分支](https://github.com/I3eg1nner/moonc-fuzz/tree/python-reference) | Python 参考实现与归档 pilot |
| `findings/codex_review_5.md` | 外部 review 及逐条修正 |
| `findings/codex_defect_review.md` | Codex 对每个缺陷的独立复验与修正 |
| `findings/upstream_issues.md` | 已提交的 7 个 upstream issue 与 PoC 映射 |
| `findings/exact_block_coverage.md` | 精确 QEMU-TB 块/边覆盖的定义与边界 |
| `findings/exact_coverage_wiring.md` | 精确 TB 计数接入 collect 与 fuzz 证据；调度仍未使用 |
| `findings/featfuzz_mvp.md` | native 布局特性生成器与分阶段 oracle |
| `findings/asyncfuzz_mvp.md` | async 状态机矩阵与 F8 校准 |
| `findings/feature_probe_negative.md` | 269 case 特性探针的负结果与并发伪诊断 |
| `findings/feature_probe_summary.json` | 该探针的逐族计数与签名集合 |
| `findings/verify_tool.md` | 新鲜副本候选验证器与 F9 烟测 |
| `findings/exact_coverage_wiring.md` | 精确块/边覆盖接入 fuzz 证据 |
| `findings/edge_feedback.md` | 边新颖度进入调度：权重、上限、口径与限制 |
| `findings/campaign_caps.md` | 父本池/持久证据上限、counter、文件审计与 before/after |
| `findings/xdiff_mvp.md` | 跨后端执行差分：布局矩阵、判定优先级 |
| `findings/xdiff_async.md` | async 逐测试状态差分与 160 case 全矩阵结果 |
| `moonbit/README.mbt.md` | MoonBit 模块、命令和边界 |
| `examples/trace2funcs.sh` | 最小可运行示例 |

## 10. 许可证

Apache-2.0，见 `LICENSE`。仓库内的第三方 fixture（如
`WeiR-h/moonldif@0.7.6`）按各自许可证使用，且不提交到本仓库。
