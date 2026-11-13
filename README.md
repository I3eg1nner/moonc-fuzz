# moonc-fuzz

面向闭源 MoonBit 编译器 `moonc` 的黑盒/灰盒测试工具，主分支实现为
MoonBit。Python 参考实现和归档 pilot 在 `python-reference` 分支，不参与
主分支构建或验收。

- 仓库：<https://github.com/I3eg1nner/moonc-fuzz>
- 固定工具链：`moon 0.1.20261104 (940aa18)`、`moonc v0.10.20+65efd5b93`、
  `moonrun 0.1.20261104`
- 当前覆盖结果：`camlMoonc*` 函数符号 7,916 / 26,611 = 29.75%

## 1. 方法

`moonc` 当前发行版无法由公开源码构建。二进制未 strip，`nm` 可见约 3 万文本
符号，因此采用以下组合，而不是纯黑盒随机测试：

- **T1**：`moonc syncheck`，覆盖 lexer/parser。
- **T2**：`moonc build-package`，覆盖 typer、core IR 和 wasm codegen。
- **T3**：`link-core` + `moonrun`/`node`，并做 wasm/js、wasm/native 差分。
- **覆盖**：QEMU `-d exec` 记录 PC，按 `nm -n` 最近前置符号归因到函数。
- **oracle**：崩溃/ICE/OOM/超时分类；跨后端输出与退出码比较；诊断码签名。
- **变异**：括号/字符串配平的 token 级变异，以及字节级无效 UTF-8 变异。

覆盖率是**函数符号级**，不是源码行、分支或可行代码覆盖。分母包含
8,038 个匿名闭包和 4,200 个 Menhir action。

## 2. 快速开始

```bash
git clone https://github.com/I3eg1nner/moonc-fuzz.git
cd moonc-fuzz
./scripts/fetch_assets.sh          # F6 第三方包；seed 语料可选
./scripts/reproduce_all.sh         # 逐个复现缺陷

cd moonbit
moon test
moon run cmd/accept -- /path/to/moonc-fuzz
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
poc/            每个缺陷的最小复现和版本说明
templates/      25 个可运行程序，用于跨后端差分
findings/       技术报告、验证记录、外部 review
issues/         对外 issue 草稿
scripts/        资产下载、一键复现
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

trace 转换器的 native release 实现在 101 MB check trace 上约 0.48 s，
Python 参考约 1.80 s。该数字仅指转换器，不代表整体吞吐。

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
  `regress`、`f6matrix`、`accept`。

当前 54 个测试通过，`moon check` 无警告。`cmd/regress` 覆盖 12 例缺陷；
`cmd/accept` 是迁移验收门禁。主分支不包含 `.py` 文件；独立参考实现和
`syntax_boundary`、`olddiff`、`iface`、`typegen` 等归档 pilot 位于
`python-reference` 分支，仅用于对拍和历史复现。

迁移细节和对拍数据见 `findings/migration_moonbit.md`。

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
| [python-reference 分支](https://github.com/I3eg1nner/moonc-fuzz/tree/python-reference) | Python 参考实现与归档 pilot |
| `findings/codex_review_5.md` | 外部 review 及逐条修正 |
| `findings/codex_defect_review.md` | Codex 对每个缺陷的独立复验与修正 |
| `moonbit/README.mbt.md` | MoonBit 模块、命令和边界 |
