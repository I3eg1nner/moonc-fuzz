# 上游 issue 草稿

## 2026-11-22 oracle asset snapshot

历史 issue 的采集、归一和逐条复现见
[`findings/issue_oracle_a_b.md`](../findings/issue_oracle_a_b.md)。原始 JSON 在
`issues/raw/`，26 条派生最小复现和状态在 `oracle_cases/<category>/<issue>/`，
索引是 `issues/curated.json`。本文件下面的 8 份草稿只是其中“我们提交过”的子集。

这里的 8 份草稿对应 `poc/` 中已复现的缺陷。11 个 PoC 不拆成 11 条 issue：
F1b、F2b、F4b 与各自的主缺陷共用栈顶或异常签名，作为同一条 issue 里的第二个
witness。

## 提交位置

`moonbitlang/moonbit-compiler` 的 Issues 已关闭（`has_issues=false`），不能直接
在那里提交。ICE banner 指向的是 `moonbitlang/moonbit-docs` 的 ICE 模板：

```
https://github.com/moonbitlang/moonbit-docs/issues/new?template=ice.md
```

- 标题前缀：`ICE: `
- 草稿 front matter 声明 `bug`、`ICE`；编译器类再加 `moonc`，formatter 类加
  `moonfmt`
- F5、P1 不是 ICE，用同仓库的普通 bug 报告，标题不加前缀

## 去重

2026-11-13 在 `org:moonbitlang` 范围内检索过标题和正文：

- F1、F2、F3、F5、F6、P1 没有找到同签名 issue。
- F4 与已关闭的
  [#861](https://github.com/moonbitlang/moonbit-docs/issues/861) 同属
  `Basic_utf8` 解码异常，但路径不同。#861 是 v0.6.18 的 `.mbt` +
  `build-package`；在 v0.10.20 上该路径已返回 3001 诊断。本缺陷是
  `.mbt.md` + `syncheck`/`build-package`，异常模块也已改名为
  `Basic_utf8_decode`。草稿里已注明这层关系。

## 提交顺序

按“证据强度 × 影响”排：

1. `04-f4-invalid-utf8-mbtmd.md` — 解码器 ICE，有已修复的同类 issue 作对照
2. `02-f2-invalid-escape-ice.md` — 阶段分裂清楚，输入 38 B
3. `03-f3-parser-oom.md` — 19 B 输入耗尽内存，DoS
4. `01-f1-moon-pkg-segv.md` — 内存安全，但只确认显式 `syncheck`
5. `06-f6-native-export-closure.md` — 链接期诊断缺陷，非 miscompile
6. `05-f5-prefix-plus-formatter.md` — formatter 产生不可解析代码
7. `07-p1-interp-perf.md` — 性能观测，只有两个点

## 写作边界

草稿只写已复现的事实和期望行为：

- 不写根因（F1 的越界假设、F2 的 `Char.chr` 位置都没有证明）；
- 不写“独立根因数量”；
- P1 不写复杂度阶数；
- F6 明确标注“诊断/工具链缺陷，不是 miscompile”；
- F1 明确标注影响面仅限显式 `moonc syncheck moon.pkg`，`moon build` 走自己的
  配置解析器，输入同样文件时正常报错。

每个 PoC 的完整命令和版本见 `poc/<id>/README.md`，复现次数见
`findings/validation.md`。

## 已提交

2026-11-13 从 `I3eg1nner` 账号用 `gh issue create` 提交：

| issue | 草稿 | 标题 |
|---|---|---|
| [#1364](https://github.com/moonbitlang/moonbit-docs/issues/1364) | `04-f4-invalid-utf8-mbtmd.md` | ICE: invalid UTF-8 in a `.mbt.md` file reaches Basic_utf8_decode.MalFormed |
| [#1365](https://github.com/moonbitlang/moonbit-docs/issues/1365) | `02-f2-invalid-escape-ice.md` | ICE: invalid escape in a string literal reaches the typer as Invalid_argument("Char.chr") |
| [#1366](https://github.com/moonbitlang/moonbit-docs/issues/1366) | `03-f3-parser-oom.md` | ICE: 19-byte parser input grows past 5 GiB and aborts (`moonc syncheck`) |
| [#1367](https://github.com/moonbitlang/moonbit-docs/issues/1367) | `01-f1-moon-pkg-segv.md` | ICE: SIGSEGV in `moonc syncheck` on a malformed `moon.pkg` |
| [#1368](https://github.com/moonbitlang/moonbit-docs/issues/1368) | `06-f6-native-export-closure.md` | ICE: native link rejects an exported closure-containing type with an ICE instead of a diagnostic |
| [#1369](https://github.com/moonbitlang/moonbit-docs/issues/1369) | `05-f5-prefix-plus-formatter.md` | `moon fmt` prints unary plus as `~+`, producing code that cannot be re-parsed |
| [#1370](https://github.com/moonbitlang/moonbit-docs/issues/1370) | `07-p1-interp-perf.md` | `moon fmt`: interpolation-heavy string costs ~9.5x more per doubling (1.6 s -> 15 s) |

提交账号没有 triage 权限，`--label` 被 GitHub 静默丢弃，七条目前都没有 label；
标题和正文按模板写，标签留给 maintainer。

## LSP 草稿（第 8 份，待决定是否提交）

`08-lsp-decode-exception-unresponsive.md` 与上面 7 份的来源不同：它不是编译器
缺陷，而是 `moon-lsp` 的会话可靠性缺陷，且 **F11 与 F12 合并为一份报告**。

合并理由是外部 Codex 复核（`findings/codex_lsp_review.md`）的结论，我们复验后
接受：两者都由“解码期异常逃出 `Lsp__Io.Make.read`”导致，进程存活、0% CPU、
stdout 未关闭、后续请求字节滞留管道；区别只在抛出点
（`Packet.t_of_fields` / `Packet.t_of_yojson` / `read_header`）。把它们写成两条
issue 会人为拆开同一个根因。

草稿与 F1–F6 的差异：

- 标题不加 `ICE:` 前缀（不是 ICE），也不宣称根因；
- 主证据用完整正确分帧的 `[1,2]`，BOM 作为“损坏传输”的补充触发；
- 显式写“15 秒观察窗口”，不写“永久”；
- 主动关联依赖层报告
  [ocaml-lsp#1330](https://github.com/ocaml/ocaml-lsp/issues/1330)，并说明它
  只覆盖抛出点、不覆盖产品层“活着但不服务”的行为；
- 与 [#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372)（F10，
  100% CPU 自旋）明确区分。

**已提交**：<https://github.com/moonbitlang/moonbit-docs/issues/1376>（2026-11-18）。

提交形式：`moonbit-docs` 的 **blank issue**（唯一模板是 ICE，本缺陷不是 ICE）。
标题 65 字符、无前缀、模块名开头。**标签未能加上**：`gh issue create --label`
没有生效，随后用 API 补加返回
`403 Must have admin rights to Repository`——该仓库只允许维护者打标签。
#1372 同样没有标签，所以无标签不是异常。

提交前经过两轮 Codex 审查：第一轮判 No-Go 并指出三处阻塞（BOM 分帧长度写错、
与 ocaml-lsp#1330 的关系描述失实、`never reads` 等超出证据的措辞），全部修正后
第二轮判 Go。审稿记录见 `findings/codex_lsp_review.md` 的提交说明段。
