# 历史 issue → oracle 资产：A（采集/归一）+ B（逐条复现）

Date: 2026-11-22. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. 禁止改 pin；本阶段未发任何上游 issue/comment。

## A. 采集与归一

用已认证 `gh`（不是 curl）分页拉取 `moonbitlang/moonbit-docs` 的
`state=all` issue：

- 原始行 1,361 条，去掉 PR 后 **561 个 issue**（57 open / 504 closed）；
- 其中正文含 fenced code block 的 **292 条**；
- 标题+正文关键词粗筛（crash/ICE/panic/segfault/assertion/wrong code/
  miscompile/type-check 误接受或误拒绝/formatter/LSP 挂死）得到 **172 条**；
- 去掉 feature request、文档、性能/优化、环境安装、无法给出最小复现的条目，
  并保证每个保留条目有可执行最小输入后，得到 **26 条 curated 用例**。

原始 JSON：`issues/raw/moonbit-docs-issues-2026-11-22.json`（3.3 MB，
sha256 `0d80d3dcfe8333f9350056c5e9aaf62dd7fdd94c3761dc83a9b37f772cd46af9`）。
派生用例：`oracle_cases/<category>/<issue>/`，每个目录只放 `case.json`
（number/title/state/日期/URL/分类/期望/实际/后端/命令/状态/证据）和最小
repro 文件；不搬运完整 issue 正文。索引：`issues/curated.json`。

分类口径：

| category | 数量 | 说明 |
|---|---:|---|
| `crash_ice` | 12 | crash/panic/ICE/SEGV/OOM/assertion |
| `miscompile` | 5 | wrong code/result、后端生成错误 |
| `typecheck` | 1 | 误接受/误拒绝/诊断错误 |
| `formatter` | 5 | 格式化不可解析/非幂等/错误改写 |
| `lsp` | 2 | 挂死/会话卡死 |
| `runtime` | 1 | native 运行时截断/崩溃 |
| **合计** | **26** | |

## B. 在 pin 上逐条复现

命令、rc、关键输出片段都在每个用例的 `result.json`；下表是摘要。

| issue | state | category | 状态 | 关键证据 |
|---|---|---|---|---|
| 1364 | open | crash_ice | **reproduced** | rc 199; `Basic_utf8_decode.MalFormed` |
| 1365 | open | crash_ice | **reproduced** | rc 1; `Invalid_argument("Char.chr")` |
| 1366 | open | crash_ice | **reproduced** | rc -6; `Fatal error: out of memory`（6 GiB cap） |
| 1367 | open | crash_ice | **reproduced** | rc -11；无输出 |
| 1368 | open | crash_ice | **reproduced** | rc 255; `reject_export_type_containing_unsupported_callback` |
| 1340 | open | crash_ice | **reproduced** | rc 1; `moonc.ml:125623 Assertion failed` |
| 1344 | open | crash_ice | **reproduced** | rc 1; `finish_stub_wrapper_shell` |
| 1322 | open | crash_ice | **reproduced** | rc 1; `lower_array_make` |
| 861 | closed | crash_ice | **fixed** | rc 1; `[3001] invalid UTF-8 streams`（无 ICE） |
| 654 | closed | crash_ice | **fixed** | rc 1; `[4038] Trait object for Eq is not allowed` |
| 596 | closed | crash_ice | **fixed** | rc 1; `Cannot use @lib`（无 `Unresolved_type_variable`） |
| 573 | closed | crash_ice | **fixed** | rc 1; `[0044] invalid_inline_wasm`（无 `Key_not_found`） |
| 1328 | open | miscompile | **fixed** | `wasm-gc` rc 0；`(nz+0.0)` bits = `0`，不再是 `8000000000000000` |
| 1326 | open | miscompile | **fixed** | `native --release` rc 0；`80000001 / 2147483649 / 40000000` |
| 1006 | closed | miscompile | **fixed** | `moon test` rc 0；1 passed / 0 failed |
| 448 | closed | miscompile | **unclear** | rc 255 `not in a Moon project`；缺包 + C stub，无法判定 |
| 860 | closed | miscompile | **unclear** | rc 1 `Cannot use @utils`；完整 List 包未带入 |
| 968 | closed | typecheck | **fixed** | rc 1；`E4095 Integer literal 12345678912 is out of range` |
| 1369 | open | formatter | **reproduced** | fmt 0 → `~+(...)`；reparse rc 2 `E3001` |
| 197 | closed | formatter | **fixed** | fmt 两次 byte-identical；reparse rc 0；注释在顶层 |
| 68 | closed | formatter | **needs_old_toolchain** | 当前 rc 2 `E3002`；源用 2023 `func`/`init` |
| 45 | closed | formatter | **needs_old_toolchain** | 当前 rc 2 `E3002`；源用 2023 `func`/destructuring |
| 875 | closed | formatter | **not_reproducible** | 源现在 `[E4003] "Option" is a reserved type name`，无法构造原合法输入 |
| 1372 | open | lsp | **reproduced** | `HUNG (no response in 10s)` |
| 1376 | open | lsp | **reproduced** | `WEDGED`；id2/id3 均无响应；stderr `Internal error` |
| 1155 | open | runtime | **fixed** | native rc 0；length `268435456`；`b[0]=42` |

### 状态×类别

| category | reproduced | fixed | needs_old | not_repro | unclear |
|---|---:|---:|---:|---:|---:|
| crash_ice | 8 | 4 | 0 | 0 | 0 |
| miscompile | 0 | 3 | 0 | 0 | 2 |
| typecheck | 0 | 1 | 0 | 0 | 0 |
| formatter | 1 | 1 | 2 | 1 | 0 |
| lsp | 2 | 0 | 0 | 0 | 0 |
| runtime | 0 | 1 | 0 | 0 | 0 |
| **合计** | **11** | **10** | **2** | **1** | **2** |

五类都有证据：

- **reproduced**：11 条，全部在当前 pin 上给出原签名/原错误行为；
- **fixed**：10 条，当前 pin 上观察到期望行为（旧 ICE/错误消失）；
- **needs_old_toolchain**：2 条（68/45），源用 2023 年 `func`/`init` 语法，
  当前 parser 直接 `E3002`；要复现需 2023 工具链，不能拿当前 pin 下结论；
- **not_reproducible**：1 条（875），原输入现在因 `Option` 是保留类型名而
  无法成为合法程序，无法重建“原合法输入被格式化破坏”的前提；
- **unclear**：2 条（448/860），issue 只给片段，需要 C stub / `@utils.List`
  完整包；没有这些依赖时只能记录 `not in a Moon project` / `Cannot use @utils`，
  不猜是否仍复现。

## 当前边界

- 本阶段只做 A+B；C（灵敏度验收）和 D（缺陷导向变异）尚未开始。
- 11 条 reproduced 还没有逐条跑“现有 oracle 是否识别”；这是 C 的核心。
- 10 条 fixed 还没有进 `regressions`/`accept`；这是 C 的另一半。
- 26 条不是全部 172 条粗筛的最终状态；剩余条目多为 feature request、文档、
  性能、环境安装或缺少最小复现，未纳入。
- 没有发上游 issue/comment，未改 pin。

## Evidence

- `issues/raw/`：完整原始 JSON + sha256
- `issues/curated.json`：26 条索引
- `oracle_cases/<category>/<issue>/case.json`：归一化元数据
- `oracle_cases/<category>/<issue>/result.json`：命令、rc、stdout/stderr tail
- `oracle_cases/**`：最小 repro（源文件/包文件/请求）
