# issue→oracle D：缺陷导向变异（D1/D2/D3）

Date: 2026-11-22. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. 未发上游 issue/comment，未改 pin。
候选一律不叫 confirmed；本报告没有新候选，全部结果与 F1–F13 已知签名去重。

## 预算（固定）

| 子阶段 | seed / 形态 | 预算 |
|---|---|---|
| D1 F5 | `poc/f5_prefix_plus` | 300 mutants，stage format，5 s/例 |
| D1 F13 | `poc/f13_fmt_nested_minus` | 300 mutants，stage format |
| D1 健康模板 | `templates/`（25 个） | 300 mutants，format |
| D1 形态语料 | `regressions/fmt_shapes/`（12 个） | 300 mutants，format |
| D2 F1 | `oracle_cases/crash_ice/1367` | 300 mutants，stage package |
| D2 clean | `poc/f6_native_export_closure_min` | 20 mutants，package 负控 |
| D2 F8/F9 | 1340/1344 | 300 mutants，stage build（先前 L2 已跑） |
| D3 LSP | `cmd/lspfuzz --family all` | 136 case，700 ms/例 |

## D1 formatter 闭环谓词

给 `cmd/seedfuzz` 加 `--stage format`。每个 mutant 只有在候选本身
`moonc syncheck` rc0 时才进入谓词；三条谓词：

1. **reparse**：`moonfmt` 输出必须 `moonc syncheck` rc0；
2. **idempotence**：第二次 `moonfmt` 输出必须与第一次 byte-identical；
3. **semantic**：若候选可运行，格式化前后 `moon run --target wasm-gc`
   的 stdout 必须相同。

结果：

| 输入 | runs | defects | 命中签名 | 结论 |
|---|---:|---:|---|---|
| F5（`+y`） | 295 | 43 | `fmt/reparse`（E3001 `~`） | 已知 F5；同时是 C 的 1369 L2 证据（5/11） |
| F13（`-(-2147483648)`） | 289 | 23 | `fmt/not_idempotent` | 已知 F13，非新根因 |
| `templates/` 25 | 293 | **0** | — | 负控通过 |
| `regressions/fmt_shapes/` 12 | 290 | **0** | — | 负控通过 |

`regressions/fmt_shapes/` 覆盖：可选参数、行/位置注释、字符串转义、嵌套插值、
match guard、struct/array trailing、嵌套 lambda、泛型、enum payload、循环、
doc comment。
**覆盖的形态**：F5/F13 的一元/嵌套一元、注释、可选参数、label（通过模板外
的生成源）、guard、泛型、字符串插值边界。  
**没覆盖**：doc comment 内的 fenced code、极深泛型嵌套、trait impl 注释；
这些仍属于 D 的缺口，不当作饱和。

正控制：F5/F13 seed 本身 `seed_defects=1`；负控 25 模板与 11 形态均 0。
新 accept gate：`formatter_sensitivity`。

## D2 package 形态变异

### 先修工具自身崩溃

L2 时 11 个 seedfuzz 并行出现 SIGSEGV。根因不是 moonc：`seedfuzz` 使用固定
临时目录 `/tmp/mbtfuzz_seedfuzz`，并发进程互相 `rm_rf`/写同一个目录。
修复：临时目录改为 `/tmp/mbtfuzz_seedfuzz_<out-path>`（`--out` 唯一化），
并重跑 4 个 package seed 并行（1340/1344/1322/1368）——全部正常退出，无
SIGSEGV。这是**工具缺陷**，已修；不是 compiler candidate。

### `moon.pkg` / `moon.mod` 变异

加 `--stage package`：在 seed 目录中挑 `moon.pkg`/`moon.mod`，文本变异后跑
`moonc syncheck target`；命中信号/ICE 记为 `pkg/sigsegv` / `pkg/ice`。

| 输入 | runs | defects | 签名 |
|---|---:|---:|---|
| F1（101 B moon.pkg） | 257 | 87 | `pkg/sigsegv`（已知 F1） |
| F6-min（clean 包） | 20 | **0** | — |

正控制 F1 命中（本轮 20 mutants：defects=7, seed_defects=1；上条 300 mutants 为 87/257），负控 0；新 accept gate `package_sensitivity` 断言 **defects>=1 且 seed_defects>=1**，detail 打印 `pos_defects/pos_seed/neg_defects/neg_seed`。

Formatter gate 是 **seed 级证明**：`seed_defects=1` 证明已知 F5/F13 破坏能被抓；变异级证据是 F5 43/295、F13 23/289，不能把 seed 级当变异级。

限制：`moon.mod` 的正例尚未构造；F8/F9 只跑了 `.mbt` 变异（279/277 runs，
0 同签名），没有做到“保留 package 形状的 F8/F9 变异”。这是覆盖缺口，不是
“没发现问题”。

## D3 LSP 请求变异

复用现有 `cmd/lspfuzz --family all` 的 136 个 framing/JSON 字段/方法 case
（半帧、错 Content-Length、粘包、BOM、顶层非对象、标量 params、超长 params、
header 拆分等），700 ms/例，fresh `moon-lsp`。

| 结果 | 数量 |
|---|---:|
| OK | 70 |
| ERROR_RESPONSE | 33 |
| HANG | 14 |
| DESYNC | 14 |
| STALL（expected_wait） | 2 |
| UNSUPPORTED | 2 |

14 HANG 与 14 DESYNC 全部落在 F10（format-nth 无尾换行）、F11（标量 params）、
F12（BOM/顶层非对象/坏 header）的已知签名；**0 个新签名**。现有
`lsp_regress_6` 与 `lspneg` 已覆盖断言，没有新增 gate。

## C 的 L2 更新（D 后续运行覆盖）

D1 的 `--stage format` 运行补上了 C 的 1369 L2：F5 seed 295 次中 43 次命中
`fmt/reparse`；1368 在临时目录修复后 seedfuzz 为 15/291。C 的 L2 因此从
4/11 更新为 **5/11 = 45.5%**（1364 饱和、1365、1367、1368、1369）。

## 去重与三档分类

本轮观察到的所有签名：

| 签名 | 去重到 | 档 |
|---|---|---|
| `fmt/reparse` E3001 `~` | F5 | 规范要求一致：formatter 输出必须可重解析；已知缺陷 |
| `fmt/not_idempotent` | F13 | 规范要求一致：formatter 必须幂等；已知候选 |
| `pkg/sigsegv` | F1 | 规范要求一致：moonc 不应 SIGSEGV；已知缺陷 |
| LSP HANG / DESYNC | F10 / F11 / F12 | 规范要求一致：LSP 应返回响应/错误，不应死锁；已知缺陷 |

**没有新候选**，所以没有新的三档判定；也没有 PoC/regression 可加。这不是
“编译器没 bug”，而是 D 的形态预算内全部落在已知签名或已知形态缺口。

## 验收

- `accept`：27/27，`formatter_sensitivity` 与 `package_sensitivity` 正负控
  通过；`issue_regress` 仍 normal 0/tamper 1。
- `moon_test`：385/385。
- `accept` 实测：`checks=27 ok=true skipped=[]`。

## 交付

- `cmd/seedfuzz` 新增 `format`/`package` stage 与唯一临时目录。
- `regressions/fmt_shapes/`：12 个健康 formatter 形态。
- `findings/issue_oracle_d.md`（本文件）。
- 新 gate：`formatter_sensitivity`、`package_sensitivity`（accept 27）。
- 无新 PoC/regression；未发上游，未改 pin。
