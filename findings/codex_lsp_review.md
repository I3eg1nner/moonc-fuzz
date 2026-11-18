# Codex review of F10/F11/F12 (LSP surface)

Archived verbatim below. Reviewer: Codex CLI, model `gpt-6.1-sol`, high reasoning,
reached through the `127.0.0.1:7890` proxy, read-only sandbox, run 2026-11-18
against `9fdd821`.

Scope: independently re-run the F11 and F12 PoCs, look for harness false
positives, check the JSON-RPC/LSP specification claims, decide whether F10/F11/F12
are independent, search upstream, and audit the inverted-oracle regression gate.

## What the review changed in this repository

All three of the reviewer's factual corrections were re-verified locally before
being accepted; none was taken on trust.

| Reviewer finding | Our check | Action |
|---|---|---|
| F11 also raises an uncaught exception (`invalid structured value` via `Jsonrpc__Import.Option.map` → `Packet.t_of_fields` → `Lsp__Io.Make.read`); it is not a silent deadlock | confirmed by re-running with stderr captured | F11 and F12 re-described as one defect with two entry points; the "silent vs stack" distinction was removed |
| F12's BOM trigger raises `Error: content length absent` from `Lsp__Io.Make.read_header`, not a Yojson error | confirmed | F12 README corrected |
| "The LSP spec shows `params: null` for `shutdown`" is false; the spec says no params, while historical clients such as Eglot send `null` | confirmed against the quoted spec and client source | F11 README narrowed to "historical client behaviour" |
| The inverted oracle has a demonstrable false pass: a response with `id: null` or a string id is treated as silence, so `HANG` is reported and the gate passes | confirmed by reading the parser and by the reviewer's fake-server counterexample | `cmd/lspregress` now refuses to report `HANG` once any response frame has arrived; F11 additionally requires a follow-up health request to go unanswered |
| The F12 control (two consecutive `shutdown` requests, both required to succeed) is not spec-conformant | confirmed | control replaced with a non-`shutdown` health request |

## What the review confirmed

- F11 and F12 both reproduce independently, including after `didOpen` of a real
  file and a successful `hover`, and with a 15 s observation window.
- The "alive but not processing" state is real: process state `S`, ~1 CPU tick
  over 15 s, stdout not readable (`EAGAIN`, not EOF), and 314 bytes of later
  requests left unread in the stdin pipe.
- F10 is a distinct defect (100% CPU spin inside `format-nth`, 120 ticks in
  1.2 s), not the same mechanism.
- No upstream report matches F11 or F12; the closest dependency-level report is
  [ocaml-lsp#1330](https://github.com/ocaml/ocaml-lsp/issues/1330), which should
  be linked if these are filed.

## Statement boundaries kept after the review

- The defects are described as "no response and no recovery within the observed
  window", not as a proof of permanent failure.
- Root cause is not claimed. The escape path is evidenced by the server's own
  stderr backtrace; the fix is not.
- "Any method" is an inference from the shared packet-decoding stack, not an
  exhaustive test. Measured: `hover` with four scalar types, `shutdown` with
  `null`, an unknown method with `null`.

---

**验收结论：F11、F12 的“进程存活但停止处理后续请求”均独立复现，未发现本次现象由 harness 漏读、EOF 混淆或提前 kill 造成。**

但证据链有三处重要问题：

- **F11 也有未捕获异常栈，并非静默死锁。F11、F12 很可能是同一异常恢复缺陷的不同触发入口，不宜算作两个已证实独立根因。**
- **“LSP 规范以 `params: null` 示例 shutdown”不成立。**规范写的是无参数；历史客户端确实存在发送 null 的行为。
- **反向 oracle 存在实测可触发的假通过。**它会把收到 null/string id 错误响应的情形误报为 `HANG`。

以下区分实测事实、推断和建议。全程未修改仓库文件；最后工作区仍干净，`pgrep -a -x moon-lsp` 无输出。

**A．独立复现：事实**

实际核验：

```text
HEAD: 9fdd821206e496c115a7b4f95b0ae82973727ada
moon: 0.1.20261104 (940aa18 2026-11-04)
moonc: v0.10.20+65efd5b93 (2026-11-05)
moon-lsp sha256:
5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d
```

在 F11 PoC 目录，逐条实际运行 `python3 -B replay.py <文件> 3`：

| 文件 | 实际输出 | rc |
|---|---|---:|
| `hang_null.json` | `HUNG ... elapsed 3.00s, server cpu 0.0%, alive=True` | 0 |
| `hang_number.json` | 同上 | 0 |
| `hang_string.json` | 同上 | 0 |
| `hang_bool.json` | 同上 | 0 |
| `ok_object.json` | `OK: {"code": -32602, ... position textDocument ...}` | 0 |
| `ok_array.json` | `OK: {"code": -32602, ... list instead of atom ...}` | 0 |
| `ok_omitted.json` | `OK: {"code": -32602, "message": "params are required"}` | 0 |
| `shutdown_null.json` | `HUNG ... cpu 0.0%, alive=True` | 0 |
| `shutdown_object.json` | `OK: null` | 0 |
| `unknown_null.json` | `HUNG ... cpu 0.0%, alive=True` | 0 |
| `unknown_object.json` | `OK: ... "code": -32601, "message": "Unknown method"` | 0 |

注意：**这个 F11 replay 的 rc=0 本身不表示验收通过**，它主要靠打印结果分类。

在 F12 PoC 目录，实际运行：

| 命令 | 实际关键输出 | rc |
|---|---|---:|
| `python3 -B replay.py control` | `CONTROL_OK`, `init_ok=true`, `ids=[2,3]`, `alive=true`, CPU `0.0` | 0 |
| `python3 -B replay.py bom` | `WEDGED`, `ids=[]`, `alive=true`, CPU `0.0`, stderr `Internal error: Uncaught exception.` | 0 |
| `python3 -B replay.py array` | 同上 | 0 |

三次观察分别约为 2052、2053、2052 ms。

随后使用**独立的内联 Python 驱动**复验：`Popen(bufsize=0)`、`os.write`、非阻塞 `os.read`、同时读取 stdout/stderr，不按响应 id 过滤原始输出；所有进程均在 `finally` 中 kill/wait。临时文档仅创建于自动清理的 `/tmp`。

关键补充结果：

| 场景 | 实际结果 |
|---|---|
| F11 标量 params，后接正常 `format-nth` 请求 | 两者均无响应 |
| F11 打开真实文件并成功 hover 后，再发送 hover/null | 仍停止处理 |
| F12 array/BOM，在打开文件、成功 hover、再等待 3 秒后触发 | 仍停止处理 |
| 未知方法/`{}`，后接正常 `format-nth` | 收到 `-32601` 和格式化 result |
| F11 null、F12 array、F12 BOM，各延长观察到 15 秒 | stdout 均为 **0 字节**；进程仍存活 |

15 秒测试还在第 10 秒追加了另一条健康请求：

```text
                         F11 null    F12 array   F12 BOM
elapsed                  15.012s    15.016s    15.011s
/proc state              S          S          S
CPU tick delta           1          1          1
SC_CLK_TCK               100        100        100
poll()，kill 前          None       None       None
select(stdout)，末次     不可读     不可读     不可读
非阻塞 os.read(stdout)   EAGAIN     EAGAIN     EAGAIN
stdin 未读字节           314        314        314
kill/wait 后子进程 rc    -9         -9         -9
```

314 字节恰好是两条完整健康请求。对照组请求处理后，stdin 未读字节为 0。

**最重要的新事实是 F11 的 stderr：**

```text
Internal error: Uncaught exception.
Jsonrpc: json conversion failed: invalid structured value
Raised at Jsonrpc__Import.Json.error
  ... "ocaml-lsp/jsonrpc/src/import.ml", line 22
Called from Jsonrpc__Import.Option.map
Called from Jsonrpc.Packet.t_of_fields
  ... "ocaml-lsp/jsonrpc/src/jsonrpc.ml", line 264
Called from Lsp__Io.Make.read
  ... "ocaml-lsp/lsp/src/io.ml", line 103
Called from Fiber__Scheduler.exec
  ... "fiber/src/scheduler.ml", line 73
```

F12 array 则是：

```text
Jsonrpc: json conversion failed: invalid packet
Jsonrpc__Import.Json.error → Jsonrpc.Packet.t_of_yojson
→ Lsp__Io.Make.read → Fiber__Scheduler.exec
```

**当前提交的 BOM payload 实际报错是：**

```text
Error: content length absent
Lsp_fiber__Fiber_io.Io.raise → Lsp__Io.Make.read_header
→ Fiber__Scheduler.exec
```

因此，[F12 README](/data/audit/mbtfuzz/poc/f12_lsp_frame_wedge/README.md:111) 关于 BOM 产生 Yojson 异常的描述，**未被本次同 pin、同 payload 复现支持**。

有限观察不能数学上证明“永远”；这里证明的是至少 15 秒持续失效，伴随解码异常和后续请求留在内核管道中。

**B．假阳性排查**

| 项目 | 判定 | 依据 |
|---|---|---|
| 1．F11 是 harness 漏读、id 不同或响应藏在缓冲中 | **本次不成立；原 harness 风险成立** | 原脚本确实混用 `select` 和缓冲读，并只接受匹配 id，见 [replay.py:17](/data/audit/mbtfuzz/poc/f11_lsp_scalar_params_deadlock/replay.py:17)。独立驱动不按 id 过滤，实际收到 0 stdout 字节。 |
| 2．F12 是 EOF 被误当静默 | **本次不成立；原脚本区分不足成立** | 原 [read_all:58](/data/audit/mbtfuzz/poc/f12_lsp_frame_wedge/replay.py:58) 遇到空读直接退出，未把 EOF 返回给 oracle。本次明确得到不可读＋`EAGAIN`，不是返回 `b''` 的 EOF。 |
| 3．服务端合法地等待更多字节 | **不成立** | F11 正确按 UTF-8 字节数构帧；array 的长度 5 与 `[1,2]` 精确匹配；后续帧也完整写入。BOM 虽是非法头部输入，但服务端已明确抛出缺少长度异常，而非仍等待正文。 |
| 4．kill/回收制造“活着但无响应” | **本次不成立** | liveness、`/proc` 状态、CPU、管道检查全部在 kill 前取得；状态为 `S`，不是 zombie。kill 后才产生 `-9`。 |
| 5．F11 只在没有 didOpen 的空会话成立 | **不成立** | `/tmp` 中建立真实 MoonBit 项目和文件，didOpen 后先成功得到 `fn answer() -> Int` 的 hover 内容，再触发，仍复现。 |
| 6．F12 只在 initialize 后立刻触发成立 | **不成立** | 完成初始化、didOpen、成功 hover，并额外等待 3 秒后，array 和 BOM 均复现。 |
| 7．只是上游库已知行为，因而不算 moon-lsp 缺陷 | **这种免责结论不成立；确切上游版本归属无法判断** | 库拒绝非法结构有源码及历史 issue 依据；产品在异常后留下活着、开放但失效的会话，仍是可报告的 moon-lsp 可靠性缺陷。 |

第 7 项需进一步分清两件事：

- **事实：**公开 ocaml-lsp 的 [`Structured.t_of_yojson`](https://github.com/ocaml/ocaml-lsp/blob/master/jsonrpc/src/jsonrpc.ml) 仅接受对象和数组，否则抛出 `invalid structured value`；其 [`Io.read`](https://github.com/ocaml/ocaml-lsp/blob/master/lsp/src/io.ml) 执行 JSON 与 packet 转换。与实际栈一致。
- **事实：**[ocaml-lsp #1330](https://github.com/ocaml/ocaml-lsp/issues/1330) 已报告字符串 params 导致未捕获异常，并讨论应使用数组。
- **无法判断：**moon-lsp 所带库的精确提交，以及上游是否已针对**同样的存活但读循环失效**行为修复。不能把当前 master 当作 pin 对应源码。
- **判断标准：**库抛异常可以是接口契约；是否向客户端返回错误、继续服务或明确关闭会话，是集成后的产品行为。依赖来源影响修复归属和新颖性，不抹掉产品缺陷。

**C．规范核对**

**1．非法 params 应返回错误，不能用持续沉默代替。**

JSON-RPC 2.0 要求 params 若存在，应为对象或数组；标量违反请求结构约束。严格按请求结构校验，可返回 `-32600 Invalid Request`；在方法参数校验层拒绝时，`-32602 Invalid params` 也符合常见分层。不能要求所有实现必须选同一个码，但本例并非可合法忽略的 notification。[JSON-RPC 2.0 §4、§5、§5.1](https://www.jsonrpc.org/specification)

LSP 的基础请求结构同样将 params 定义为可选对象/数组，并规定请求须获得响应。[LSP 3.17 基础协议源码](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/specification.md)

**2．shutdown/null：规范示例主张不成立，历史真实客户端行为成立。**

官方 shutdown 文档写的是 **`params: none`、响应 `result: null`**，没有给出 `"params": null` 示例。不能把响应中的 null 当成请求参数示例。[官方 shutdown 定义](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_includes/messages/3.17/shutdown.md)

但 Emacs 29 自带 Eglot 确实调用：

```elisp
(jsonrpc-request server :shutdown nil ...)
```

其 JSON-RPC 实现保留 `:params params`，并以 `:null-object nil` 编码，因此会发送 null。这证明真实客户端兼容性问题存在；不能据此宣称所有常见客户端都这样发送。[Eglot 调用](https://github.com/emacs-mirror/emacs/blob/emacs-29/lisp/progmodes/eglot.el#L923)、[发送及编码实现](https://github.com/emacs-mirror/emacs/blob/emacs-29/lisp/jsonrpc.el#L425)

所以 [F11 README:71](/data/audit/mbtfuzz/poc/f11_lsp_scalar_params_deadlock/README.md:71) 应改成“历史客户端存在此行为”，而非“规范示例保证其合法”。

**3．顶层非对象需要区分 JSON、batch 和传输错误。**

- 合法 JSON 标量但不是请求对象：应归入 **`-32600`**，不是 `-32700`。
- `[1,2]` 在通用 JSON-RPC 2.0 中可被识别为含两个非法成员的 batch；规范示例对应的是包含两个 `id:null`、`-32600` 错误的数组。故 README 简化成“必定返回单个 -32600”不够精确。
- 非法 JSON 文本才对应 **`-32700 Parse error`**。[JSON-RPC 错误与 batch 示例](https://www.jsonrpc.org/specification)
- BOM 位于头部之前，违反 LSP 的 ASCII 头部格式。**不能从规范推出服务端必须对这种损坏传输重新同步并继续读取。**明确终止连接可以是合理策略；当前“异常后进程不退出、stdout 不关闭、后续请求持续积压”仍是可靠性问题。[LSP 头部规定](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/specification.md)

还有一个对照问题：规范要求 shutdown 后收到的新请求返回 `InvalidRequest`。原 F12 control 连续两次 shutdown 且要求两次成功，并非符合规范的成功对照。[shutdown 生命周期要求](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_includes/messages/3.17/shutdown.md)

我补做的“未知方法/对象参数 → 正常格式化”避免了这一问题，并正常收到两个响应。

**D．区分性：事实与推断**

| 项目 | 触发入口 | 独立实测 CPU | stderr | 对照 |
|---|---|---:|---|---|
| F10 | `format-nth` 方法处理中的源码格式化 | 1.202 秒增加 120 ticks，约 100% | 空 | 加末尾换行即返回 |
| F11 | packet 字段转换中的标量 params | 15 秒增加 1 tick | `invalid structured value`，经过 `Io.read` | 对象/数组参数能返回错误；后续正常请求也处理 |
| F12 array | 顶层 packet 转换 | 15 秒增加 1 tick | `invalid packet`，经过同一 `Io.read` | 正常 packet 后仍处理后续请求 |
| F12 BOM | 头部读取 | 15 秒增加 1 tick | `content length absent`，经过 `read_header` | 去掉 BOM 后正常 |

**推断：**

- F10 与 F11/F12 有充分证据区分，符合独立缺陷判断。
- **F11 与 F12 应优先合并为“输入解码异常后会话失去处理能力”的不同触发面。**两者异常位置不同，但异常逃逸和停止处理的表现一致。
- 尚未取得对应 moon-lsp 源码或验证修复，不能证明它们必然由同一行代码修复；但现有证据也不足以宣称它们是两个独立根因。
- [F12 README:83](/data/audit/mbtfuzz/poc/f12_lsp_frame_wedge/README.md:83) 用“F11 静默、F12 有异常栈”区分二者，**已被本次实测推翻**。F11 原脚本在 [第 10 行](/data/audit/mbtfuzz/poc/f11_lsp_scalar_params_deadlock/replay.py:10) 丢弃了 stderr。

**E．上游查重：事实及范围**

截至本次检查日期 **2026-11-18**，使用 GitHub API 搜索开放及已关闭 issue：

- `moonbitlang/moonbit-docs`：`lsp` 查询返回 45 条；另查 `scalar`、`shutdown`、`jsonrpc`、`BOM`、`Content-Length`、`deadlock`，以及 `language server`、`unresponsive`、`freeze`、`never responds`、`malformed`。
- **F11、F12：未找到匹配报告。**
- 找到并核对了 [#1372](https://github.com/moonbitlang/moonbit-docs/issues/1372)，确实对应 F10。
- 最接近的 [#912](https://github.com/moonbitlang/moonbit-docs/issues/912) 是非法 warn-list 导致 LSP 失效；[#1240](https://github.com/moonbitlang/moonbit-docs/issues/1240) 是初始化期间读取配置产生错误。均不匹配本次触发。
- `moonbitlang/moonbit-compiler` 可读；API 元数据显示 `has_issues=false`，`is:issue` 搜索结果为 0。列表接口返回的条目为 PR，未发现匹配报告。[仓库元数据](https://api.github.com/repos/moonbitlang/moonbit-compiler)
- 依赖项目有前述 [ocaml-lsp #1330](https://github.com/ocaml/ocaml-lsp/issues/1330) 相近报告，提交时应主动关联。

“未找到”是公开检索结果，不是对不存在私有、未索引或不同措辞报告的保证。

**F．证据评级与最小改进建议**

| 项目 | 等级 | 提交边界 |
|---|---|---|
| F11 | **可直接对外提交** | 使用本次补充证据，描述为解码异常后的持续失效；作为与 F12 合并报告的触发变体 |
| F12 | **可直接对外提交** | 以完整正确分帧的 array 为主证据；BOM 作为损坏传输的补充触发 |

**原 README 不宜原样提交。**最小需要调整的是陈述与证据保留：

1. 附上完整 stderr，删除“F11 静默死锁、与 F12 无关”的结论。
2. 修正 shutdown/null 的规范依据、BOM 的实际异常类型。
3. 用非 shutdown 请求作为健康对照；明确记录 `EAGAIN/EOF`。
4. 写“观察 15 秒仍无响应且后续字节未被读取”，避免将有限观察写成严格证明永久不恢复。

对几个具体问题的判断：

| 问题 | 判断 |
|---|---|
| 只做 3/3 是否足够？ | **足以提交确定性最小复现，不足以证明所有方法、所有环境或严格永久性。**独立读取方式、健康对照、完整栈比机械增加重复次数更有价值。 |
| 是否需要抓包？ | stdio 没有网络包可抓；**建议附带字节级 transcript**，记录方向、时间、实际写入长度、所有 stdout 字节、EOF/EAGAIN 和 kill 时点。无需以抓包作为提交门槛。 |
| 是否需要另一个版本或机器？ | **不是确认该 pin 缺陷的必要条件。**另一版本用于判断修复范围，另一机器用于判断平台范围；不要未经测试扩展结论。 |
| 是否已证明任何方法都中招？ | 实测覆盖 hover 的四类标量，以及 shutdown/null、未知方法/null。共同 packet 解码栈支持方法无关推断，不能写成穷尽测试事实。 |

**反向 oracle：方向合理，实现有真实假通过风险。**

现有产物实跑：

```text
moonbit/_build/native/debug/build/cmd/lspregress/lspregress.exe
rc=0
{"ok":true,"passed":6,"failed":0}
```

它有一些有效防护：初始化失败单独处理，检查 EOF、坏头部、timeout 和非 zombie 存活状态；见 [evaluate](/data/audit/mbtfuzz/moonbit/cmd/lspregress/main.mbt:116)。

但存在以下盲点：

- [collect:447](/data/audit/mbtfuzz/moonbit/cmd/lspregress/main.mbt:447) 将无法解析成整数 id 的消息忽略；[inspect_response:226](/data/audit/mbtfuzz/moonbit/lsp/json.mbt:226) 只解析整数 id。**`id:null` 错误响应不等于 notification，却会被丢弃。**
- F11 gate 只断言首请求无响应，没有发送后续健康请求，因此不能独立证明整个会话失效。
- oracle 未验证 CPU、异常栈或二进制 SHA；其他原因造成的存活但慢响应也可能通过。
- F12 control 要求 shutdown 后的第二次 shutdown 成功，会误拒绝更符合规范的实现。
- 原 F12 Python replay 还没有将 EOF 纳入 verdict；F11 Python replay 的 rc 也不能作为缺陷断言。

我用**仅存于内存的模拟服务端**对现有 gate 做了反例测试，模拟端始终返回错误并继续读取：

| 首请求实际错误响应 id | `F11-hang,F11-control` 的 gate 结果 |
|---|---|
| 整数 `2` | rc=1，正确识别 `ERROR -32600` |
| `null` | **rc=0，错误报告 `HANG`，两例通过** |
| 字符串 `"2"` | **rc=0，错误报告 `HANG`，两例通过** |

其中 null-id 是必须处理的协议错误响应情形；字符串 id 即使属于错误关联，也足以推翻“未收到任何响应”的断言。

**建议最小加强 oracle：**保留全部原始帧；区分 notification、错误响应和无法关联的响应；任何错误响应都不能算静默；为 F11 增加后续健康请求，并要求所有挂起断言确实等待完整观察窗口。上述风险不影响本次真实 moon-lsp 的结论，因为独立复验确认其 stdout 确实为零字节。

## Second review: the upstream draft (2026-11-18)

The draft for `moonbit-docs` was reviewed twice before filing.

**Round 1 — No-Go**, with three blocking items, all of which we accepted after
reproducing them:

1. the BOM example declared `Content-Length: 63` for a 56-byte body, and the
   inline script repeated the mistake, so the sample mixed two errors;
2. the relation to [ocaml-lsp#1330](https://github.com/ocaml/ocaml-lsp/issues/1330)
   was wrong: that issue reports a `missing field error` for a **string**
   `params` on `ocamllsp/switchImplIntf`, the server dies, and its discussion
   recommends array params — not the same raising site;
3. several claims outran the evidence (`never reads`, `any malformed JSON`,
   `the mechanism is the same`, `the read loop is gone`), contradicting the
   draft's own limitations section.

**Round 2 — Go**, after the fixes: the BOM frame is now built with a computed
length, `#1330` is restated as a related precedent that does not establish the
same failure mode, and every open-ended claim is bounded to the 15-second
observation window.

One number did not survive review: the earlier text said 260 bytes of unread
follow-up requests. That figure came from the reviewer's own payload pair, not
ours, so it was replaced by a measurement we could reproduce: `FIONREAD` on the
pipe reported **254 bytes** after the trigger (an 85-byte `shutdown` plus a
169-byte `format-nth`), 0 before the trigger, and 0 in the control session that
answered the same two requests.

**Filed:** <https://github.com/moonbitlang/moonbit-docs/issues/1376>.
Labels could not be applied — the label API returns
`403 Must have admin rights to Repository` for outside reporters, and #1372 is
likewise unlabeled.
