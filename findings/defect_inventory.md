# 缺陷总清单与 2026-11-22 复核

Pin：`moon 0.1.20261104 (940aa18)`、`moonc v0.10.20+65efd5b93`、
`moonrun 0.1.20261104`、`moon-lsp` sha256
`5b9f19e9f4874a7ba56624ef3a9bdcd7571702efa01c8a365eede252c2f8801d`。
Host：Linux x86_64。

复核方式：每个 PoC 用各自的 canonical 命令重放；F1–F6 走
`scripts/reproduce_all.sh` 三轮（每轮 13/13 断言通过）并跑
`cmd/regress`（13/13）；F7–F12 每个 fresh 进程 3 次；P1 每个规模 3 次计时。
本文件只记录**当前 pin 上仍能复现**的结果，不把旧结论或上游报告当成本地证据。

## 1. 根因类清单

| 根因类 | 变体 / witness | 触发 | 现象（判别签名） | 本次复现 | 边界 / 上游 |
|---|---|---|---|---|---|
| **F1** `moon.pkg` 解析 SIGSEGV | F1（101 B）、F1b（672 B，同栈） | 显式 `moonc syncheck moon.pkg` | rc 139，无输出 | 3/3 | 只限显式 `syncheck`；`moon build`/`check` 走另一解析器，正常报错；根因未证。上游 #1367 |
| **F2** 转义 ICE | F2（38 B 文件，9 B 核心）、F2b（`\`+U+200B） | `\` 后接非 Latin-1 / 零宽字符 | `Invalid_argument("Char.chr")`；`moon check` rc 1，build-package rc 199 | 3/3 | 用户输入直接变 ICE；T1/T2 阶段分裂。上游 #1365 |
| **F3** 解析错误路径内存增长 | F3（19 B）、F3b（41 B `wild.mbt`） | `fn r(){y(for in ]` + `\n[` | 6 GiB cap 下 rc 134 / `out of memory` | 3/3（capped） | 19 B 即可打爆内存；uncapped 60 s 约 24.9 GB 是旧测量，本次未再跑无上限版本；根因描述为错误恢复不前进，未做源码级证明。上游 #1366 |
| **F4** `.mbt.md` 解码 ICE | F4（40 B）、F4b（6.7 KB，同异常类） | `.mbt.md` 含非法 UTF-8 字节 | `Moonc.Basic_utf8_decode.MalFormed`，rc 199 | 3/3 | 同类字节在 `.mbt`/`.mbtx` 中正常报 `E3001`；仅 Markdown 路径。上游 #1364 |
| **F5** 一元 `+` 格式化为 `~+` | F5 | 前缀 `+`（`+y`/`+(y)` 等） | parse 0；check 2（`~+` unbound）；`moonfmt` 输出 `~+(y)`，reparse 2 `E3001` | 3/3 | 语法往返缺陷，不是语义错误；`+1` 折叠为 `1` 是干净的。上游 #1369 |
| **F6** native 导出含闭包类型 | F6（moonldif 外部包）、F6-min（10 行单包） | `foreign_library` 用 `#export_name` 导出参数/返回值可达闭包类型的函数 | `reject_export_type_containing_unsupported_callback`；min rc 255，外部包 rc 1 | 3/3 | 链接期诊断/工具缺陷，不是 miscompile；包级 build 可过，模块级 test/build 失败。上游 #1368 |
| **F7** `#valtype` 数组 native debug ICE | F7（`repro.mbt`）、`minimal.mbt` | native debug 下 `#valtype` 记录（含非空 GC 引用 enum）经 `[]`+`push` 进 `Array` | `lower_array_make` / `uninitialized non-null GC ref arrays are not lowered`，rc 1 | 3/3 | `--release` rc 0；wasm/wasm-gc/js 正常；payload 类型无关。上游 #1322 |
| **F8** async `raise?` 回调 link-core 断言 | F8 | async 函数在挂起点之后调用类型带 `raise?` 的回调 | `moonc.ml` line 125623 `Assertion failed`，rc 1 | 3/3 | `moon check` rc 0；js/wasm/native 链接均中；无挂起、挂起前调用、非 `raise?` 均不触发。上游 #1340 |
| **F9** native `V128` stub wrapper ICE | F9 | debug test link，`extern "C"` stub 的**参数**为 `V128` 且被调用 | `finish_stub_wrapper_shell` / `aggregate stub wrapper arguments are not lowered in this batch`，rc 1 | 3/3 | `--release` rc 0；V128 只在返回位、标量参数、声明不调用均通过；`moon check`/`build` 成功。上游 #1344 |
| **F10** `format-nth` 100% CPU 自旋 | F10 + 7 个 format-nth 变体（多块/CRLF/emoji/长行等） | `moonbit-lsp/format-nth` 的最后一个块无结尾换行 | 无响应，server CPU 99–100%，stderr 无异常；补 `\n` 即恢复 | 3/3 | 纯 LSP 格式化路径；CLI `moon fmt` 正常。上游 #1372 |
| **F11 / F12** LSP 解码异常逃逸，stdio 循环卡死 | F11（`params` 为 JSON 标量）、F12（BOM/顶层非对象/坏头部等 14 个 DESYNC 形状） | 请求帧转换抛异常，逃出 `Lsp__Io.Make.read` | 无响应，CPU ~0%，进程存活、stdout 不 EOF，后续完整请求不被读取；stderr `Internal error: Uncaught exception.` | F11 3/3；F12 3/3 | **同一根因的两个入口**，不是两个独立根因；F11 在 `Packet.t_of_fields`（`invalid structured value`），F12 在 `t_of_yojson`（`invalid packet`）或 `read_header`（`content length absent`）。上游 #1376（合并） |

### P1：formatter 插值复杂度（性能异常，不是正确性缺陷）

| 输入 | 本次 3 次中位数（插值） | regress 同轮对照（纯串） |
|---|---:|---:|
| 1,024 段插值 | 1.51 s | 纯串约 5 ms |
| 2,048 段插值 | 14.58 s | 纯串约 5 ms |

1024→2048 约 9.6x。只声称这两个实测点，不推渐近阶数。上游 #1370。

## 2. 计数口径

- **根因类**：11 个 = F1–F10（10 个）+ F11/F12（合并 1 个）。
- **对外 ID 条目**：16 个 = F1、F1b、F2、F2b、F3、F4、F4b、F5、F6、
  F7、F8、F9、F10、F11、F12、P1。
- **实际 witness**：18 个；F3b（`wild.mbt`）与 F6-min 是同一根因类的附加
  witness，不单列根因。
- **签名类**与根因类不是一回事：按异常文本/栈可以把 F11、F12 拆成两个签名，
  但它们共享同一条逃逸路径；本文不把签名数当根因数。

## 3. 不算缺陷的候选

| 候选 | 结论 | 依据 |
|---|---|---|
| `Int::min / -1`、`min % -1` 的 js/wasm/native 分歧 | **allowed_impl_divergence**，不是编译器缺陷 | MoonBit core int 文档明确这些情况“没有可移植结果，可能 abort 或得到任意值”；三后端 ×10 确定复现，资产在 `regressions/sem3_div_overflow/` |
| 83 个包语义 witness | 用户代码语义差异，不是 `moonc` 缺陷 | `findings/pkg_semantic.md`；没有规范级反例 |
| sem3 / float / async 30 分钟 0 witness | 域内未发现缺陷，**不等于**编译器正确 | 覆盖域窄（见 `handoff_final.md` §3）；Float 只覆盖 Double，async 只覆盖确定性顺序 |
| LSP 未 advertise 方法返回 `-32603` | 正常不支持响应，不是 hang/crash | `findings/lsp_framing.md` |
| framing 的 `STALL`（声明长度过大、只发一半） | 合法等待更多字节，`expected_wait`，不计缺陷 | 同上 |

## 4. 本次复核发现的记录偏差（已修正）

1. `findings/F4_invalid_utf8_ice.md` 写“最小输入 22 字节”，实际 committed
   `doc.mbt.md` 是 **40 B**；上游 issue 与 PoC README 也写 40 B。已改。
2. `findings/handoff_final.md` 把 `regressions_13` 描述成“13 个已知缺陷回归
   （F1–F9 家族）”。实际 `cmd/regress` 的 13 个 case 是 **F1–F6 家族 12 个
   + P1**；F7–F9 由 `f7_boundary`/`reduce_witness` 等专项覆盖，F10–F12 由
   `lsp_regress_6` 覆盖。已改。
3. 主 `README.md` 的“11 个 PoC”是 F1–F6+P1 时期的历史数字；当前有 17 个
   PoC 目录、16 个 ID 条目。已补当前状态，未改写历史复验记录。
4. 主 `README.md` §5.3 标题“三条互不重叠的健壮性缺陷”与正文“F11/F12 是
   同一缺陷的两个入口”矛盾；已改为“三个编号、两条根因”。
5. 主 `README.md` 的“340 个测试通过”已过时；当前 `moon test --target native`
   为 **385/385**。已改。
6. `poc/README.md` 对 F11/F12 的上游状态自相矛盾（先说“无匹配报告”，又说
   “已作为 #1376 提交”，随后又重复“F12 无匹配报告”）；已合并为一段：
   #1376 覆盖两个入口，另列 ocaml-lsp#1330。该文件还写“F10/F11 未经独立
   review”，与 `findings/codex_lsp_review.md` 冲突；已改为 F7–F9 与
   F10–F12 分别有独立 review。
7. 主 `README.md` 把 F7–F9 说成“不计入 F1–F6 的‘已修复’集合”。F1–F6 并未
   修复，这里的本意是“既有集合”；已改为“既有集合”，避免读者误以为已有 fix。

## 5. 复现命令（本次实际执行）

```bash
# F1–F6 家族 + F6 外部包（13 条断言；连续跑 3 轮均 13/13）
./scripts/reproduce_all.sh

# F1–F6 家族 + P1 的 13 个回归 case（本次 13/13）
moonbit/_build/native/debug/build/cmd/regress/regress.exe \
  /data/audit/mbtfuzz /tmp/reg_check.jsonl

# F7
(cd poc/f7_valtype_array_ice && rm -rf _build &&
 moon run repro.mbt --target native)          # rc 1, lower_array_make
# F8
(cd poc/f8_async_raise_ice && rm -rf _build &&
 moon test --target js)                        # rc 1, moonc.ml:125623
# F9
(cd poc/f9_native_v128_stub_ice && rm -rf _build &&
 moon test --target native)                    # rc 1, finish_stub_wrapper_shell

# F10–F12（每个 fresh 进程 3 次）
(cd poc/f10_lsp_format_nth_hang && python3 replay.py hang.json)
(cd poc/f11_lsp_scalar_params_deadlock && python3 replay.py hang_null.json 3)
(cd poc/f12_lsp_frame_wedge && python3 replay.py array)

# P1（每个规模 3 次）
(cd poc/p1_fmt_interp && ./generate.sh 1024 p.mbt && ./generate.sh 2048 p8.mbt &&
 for f in p.mbt p8.mbt; do for i in 1 2 3; do
   /usr/bin/time -f '%e s' moonfmt "$f" -o /tmp/p1_out.mbt; done; done)
```

控制：F7 `--release` rc 0；F9 `--release` 1 passed；F8 `moon check` rc 0；
F10 `ok.json` 立即返回；F11 `ok_object.json`/`ok_omitted.json` 返回 -32602；
F12 `control` 两个 id 都应答。

## 6. 声明边界

- 这些都是**复现的崩溃/挂起/工具缺陷**；没有一条是“编译器算错”的
  miscompile 证据。
- F1 只限显式 `moonc syncheck moon.pkg`；F3 只声称固定内存上限下的资源耗尽；
  F4 只限 `.mbt.md` 非法 UTF-8；F5 只限语法往返；F6 是诊断/链接期缺陷；
  F7/F9 只在 native debug；F8 是链接期断言；F10/F11/F12 是 LSP 层，
  不声称根因已定位。
- 本次未向任何上游仓库发 issue/comment，未改 pin。

## 7. 2026-11-22 新增候选（尚未并入上面的根因计数）

F13（`poc/f13_fmt_nested_minus/`，`findings/fmt_nested_minus.md`）：
`moonfmt` 把 `-(-2147483648)` 打成 `--2147483648`，格式化后的文件因
`E4095 Integer literal 2147483648 is out of range` 无法编译；原程序
rc 0、输出 `-2147483648`。3/3 复现，js/native/wasm-gc 都在 typecheck 阶段失败。
它和 F5（`moonfmt` 一元 `+` → `~+`）是同一组件、不同签名；是否同一根因
尚未证明，因此暂不并入 11 个根因类，也不进 `regressions_13`。未发上游。
