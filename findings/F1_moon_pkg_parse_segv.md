# F1 — `moon.pkg` 解析错误路径 SIGSEGV（根因待定）

| 项目 | 值 |
|------|-----|
| 目标 | `moonc v0.10.20+65efd5b93 (2026-11-05)` |
| 输入类型 | `moon.pkg`（包配置文件） |
| 现象 | SIGSEGV（rc 139），无任何输出 |
| 最小输入 | **101 字节**，纯 ASCII |
| 发现方式 | `while :; do moonc syncheck moon.pkg; done` 的定向变异（本轮 fuzz 第 2 轮） |
| 严重性 | 中（显式 `moonc syncheck moon.pkg` 可被 101 B 文件打断；影响面见下） |

## 复现

```bash
cd poc/f1_moon_pkg_segv
moonc syncheck moon.pkg
echo $?     # 139
```

`moon.pkg` 内容（101 字节，**末尾没有换行**）：

```
s(1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
```

生成脚本：

```python
open("moon.pkg","w").write("s(" + "1,"*49 + "1")
```

## 触发条件（已做边界实验）

| 变体 | 结果 |
|------|------|
| 48 个 `1` | rc 2，正常报错 |
| **50 个 `1`（101 B）** | **SIGSEGV** |
| 50 个 `1` + 末尾换行 | rc 2，正常报错 |
| 50 个 `1` + 末尾空格 | SIGSEGV |
| `(` + 50 个 `1`（去掉 `s`） | rc 2 |
| `s(` + 50 个**标识符** `a` | rc 2（错误恢复走另一条分支，只报 3 条错就停） |
| `s(` + 50 个**字符串** `"a"` | SIGSEGV（同族） |

边界复核：Codex 独立复验了数字 token 的 48/49/50 三档（48、49 为 rc 2，
50 为 SIGSEGV）；其余变体来自早期实验，未在本次复核中逐一重跑。

要点：
- 必须是 `值(` 形式的"包语句"，且 **EOF 处没有换行**；
- 触发与 token 数相关（≥50），与字面量长度无关（`1` / `111111` / 30 位数字都行）；
- 数字和字符串会"一个 token 报一条错"，标识符只报 3 条就停止恢复 —— 崩溃就发生在持续报错的过程中。

## 崩溃点

```
$ gdb -q -batch -ex run -ex "bt" --args moonc syncheck moon.pkg
Program received signal SIGSEGV
#0 camlMoonc__next_segment_head_71310 ()
#1 camlMoonc__report_failed_to_parse_71498 ()
#2 camlMoonc__loop_71725 ()
#3 camlMoonc__fun_428987 ()
#4 camlMoonc__surround_71668 ()
#5 camlMoonc__fun_429097 ()
#6 camlMoonc__parse_apply_72880 ()
#7 camlMoonc__parse_statement_72979 ()
#8 camlMoonc__loop_71725 ()
#9 camlMoonc__parse_statements_72989 ()
#10 camlMoonc__moon_pkg_of_tokens_72993 ()
#11 camlMoonc__parse_from_string_inner_429709 ()
```

## 根因分析（假设，基于 2025-03 源码快照）

2025-03 的 `src/parsing_segment.ml`：

```ocaml
let next_segment_head t =
  let rec go i =
    match Basic_arr.get_opt t.tokens i with   (* <- 安全访问 *)
    | None -> None
    | Some (tok, _, _) as triple -> ...
  in
  go (t.start + t.len)
```

而 `parsing_core.ml` 在 `EOF` 分支里会调用它来"猜用户是不是忘了缩进"：

```ocaml
| EOF -> (
    match Segment.next_segment_head state.segment with
    | Some (tok, _, _) -> ...
```

只有 EOF 且 `s(...)` 未闭合、错误恢复反复重入时才会走到这里。当前二进制里该函数的行为表现为**直接段错误**而不是 `None`，最可能的改动是：为了性能把 `Basic_arr.get_opt` 换成了 `Array.unsafe_get`/`get_unsafe`，而 `t.start + t.len` 在错误恢复后指向了 token 数组之外。

> 说明：2026 的源码不可得，上面是基于旧源码 + 符号/栈的推断；但触发条件（EOF 无换行、≥50 token、发生在 `next_segment_head`）与"越界索引"高度吻合。可用 `valgrind`/ASAN 版本进一步确认，OCaml 侧可加断言。

## 影响（已实测的边界）

- 确认：`moonc syncheck moon.pkg` 直接崩溃（rc 139）。
- 未复现：在同一目录下对**合法源文件**执行
  `moonc build-package main.mbt ...` 与 `moonc check main.mbt ...` 均不崩溃
  （rc 0 / rc 2）。这两个子命令不会因为 cwd 里有恶意 `moon.pkg` 而自动加载它。
- `moon check/build` 使用 `moon` 自己的配置解析器；F1 的 canonical 命令是
  `moonc syncheck moon.pkg`，不是 `moon build`。
- “IDE/LSP 保存时调用 `moonc syncheck` 因而可被利用”是**未验证的推断**，
  本报告不作为结论。需要抓取 IDE 实际 argv 才能确认。

因此当前证据支持的是：**显式对 `moon.pkg` 跑 `moonc syncheck` 时的内存安全
崩溃**，而不是“任意子命令/IDE 都会被单个文件打断”。

## 修复建议

1. `next_segment_head` 恢复边界检查（`get_opt` 或 `if i < Array.length`）。
2. 错误恢复循环强制"必须前进"（记录上一次 token 位置，未前进则跳出）。
3. 对单文件诊断数量设上限（例如 100 条后停止恢复），避免"一个 token 一条错"的放大。
