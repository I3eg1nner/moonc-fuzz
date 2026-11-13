# F2 — 字符串转义 `\` + 非 Latin-1 字符触发 ICE（`Char.chr`）

| 项目 | 值 |
|------|-----|
| 目标 | `moonc v0.10.20+65efd5b93 (2026-11-05)` |
| 输入类型 | `.mbt` 源码 |
| 现象 | ICE，`Error: Invalid_argument("Char.chr")`，退出码 199 |
| 最小输入 | **9 字节**：`let s="\<U+4E2D>` |
| 发现方式 | fuzz 第 1 轮 T2（build-package）捕获，随机变异自 core 库的测试文件 |
| 严重性 | 中（用户级输入直接变成"编译器内部错误"，构建/IDE 直接失败，且误导用户去提 bug） |

## 复现

```bash
cd poc/f2_lex_escape_ice
moon check        # 或 moon build
# → Oops, the compiler has encountered an unexpected situation.
#   Error: Invalid_argument("Char.chr")
#   moonc version: v0.10.20+65efd5b93
#   exit code 199
```

`cmd/main.mbt`（38 字节，核心就 9 字节）：

```
let s = "\中"
fn main { println(s) }
```

最小形式（`moonc build-package`）：

```
let s="\
```

（反斜杠后直接跟 U+4E2D，字符串甚至不闭合也能触发。）

## 触发条件（穷举过）

| 输入 | 结果 |
|------|------|
| `let s="\<U+4E2D>"` | **ICE 199** |
| `let s="\<U+00E9>"`（é, 233） | rc 2（正常报错） |
| `let s="\<U+00FF>"`（255） | rc 2 |
| `let s="\<U+0100>"`（256） | **ICE 199** |
| `let s="\<U+1F600>"`（emoji） | **ICE 199** |
| `let s="\<U+E000>"`（私用区） | **ICE 199** |
| `let b=b"\<U+4E2D>"`（字节串） | **ICE 199** |
| `let c='\<U+4E2D>'`（字符字面量） | rc 2 |
| `let s="中"`（无反斜杠） | rc 2 |
| `let s="\n"` | rc 2 |

⇒ **字符串/字节串字面量中，`\` 后跟码点 > 0xFF 的字符** 必触发。字符字面量不受影响。

## 崩溃点

```
Oops, the compiler has encountered an unexpected situation.
Error: Invalid_argument("Char.chr")

Backtrace:
Raised at Stdlib.invalid_arg in file "stdlib.ml", line 30
Called from Moonc.Lex_literal.sub_string_of_codepoints in file "moonc.ml"
Called from Moonc.Lex_literal.Interpret.report_invalid_escape in file "moonc.ml"
Called from Moonc.Lex_literal.Interpret.lex_for_string in file "moonc.ml"
```

同一个 bug 的字节串版本落在 `lex_for_bytes`（fuzz 里两个签名，`out/findings/t2/ICE/8462…` 与 `1264…`）。

## 根因

`\中` 不是合法转义，词法器本应报 `invalid escape` 诊断。`report_invalid_escape` 需要把"被转义的码点序列"重新拼成字符串用于报错，实现里用 `sub_string_of_codepoints` → `List.map Char.chr codepoints`。而 `Char.chr` 只接受 `0..255`，遇到 U+4E2D 直接 `Invalid_argument`。

即：**用户输入错误 → 拼错误消息 → 抛异常 → 被 ICE catcher 当成编译器 bug**。属于典型的"错误处理路径没测"。

## 影响

- `moon check` / `moon build` / `moon test` 全部失败，且输出的是"请给编译器提 bug"的横幅，对用户完全误导。
- 只要源码里出现 `"\中文"` 这类手误（中文输入法下非常容易发生：`\` + 中文），构建即中断。
- 退出码 199 是 ICE 专用码，CI 上会被识别为"编译器内部错误"，排查成本高。

## 修复建议

1. `sub_string_of_codepoints` 不要用 `Char.chr`：按 UTF-8 编码（`Buffer.add_utf_8_uchar`）或用 `Uchar`。
2. 在 `Interpret` 层对 `\` 后的码点先做范围检查，直接产出 `invalid escape sequence` 诊断（字符串里 `\u{...}` 已有类似处理，可复用）。
3. 兜底：`Printexc` 里 `Invalid_argument` 不应进入 ICE 通道——至少把"输入导致的异常"映射回诊断。
