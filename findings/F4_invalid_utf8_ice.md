# F4 — `.mbt.md` 非法 UTF-8 导致 ICE（`Basic_utf8_decode.MalFormed`）

| 项目 | 值 |
|------|-----|
| 目标 | `moonc v0.10.20+65efd5b93 (2026-11-05)` |
| 输入类型 | `.mbt.md`（带 MoonBit 代码块的 Markdown，用于 doctest） |
| 现象 | ICE，`Error: Moonc.Basic_utf8_decode.MalFormed`，退出码 199 |
| 最小输入 | 22 字节 |
| 严重性 | 低（错误路径未兜住，属于偶发 ICE；不应影响正常构建） |

## 复现

```bash
cd poc/f4_invalid_utf8
moonc syncheck doc.mbt.md
# → 横幅 + Error: Moonc.Basic_utf8_decode.MalFormed
# exit 199
```

`doc.mbt.md` 内容（含两个非法字节 `0xff 0xfe`）：

```python
open("doc.mbt.md","wb").write(b'# t\n\n```mbt\nfn f() { let s = "\xff\xfe" }\n```\n')
```

## 崩溃点

```
Error: Moonc.Basic_utf8_decode.MalFormed

Backtrace:
Raised by primitive operation at Stdlib__In_channel.input_all in file "in_channel.ml", line 151
Compiler args: /home/user/.moon/bin/moonc syncheck -error-format json in.mbt.md
```

## 对比：`.mbt` 与 `.mbtx` 是正常的

| 文件 | 行为 |
|------|------|
| `x.mbt` 含 `0xff` | rc 2，正常诊断 `[E3001] Could not read the file because it contains invalid UTF-8 streams.` |
| `x.mbtx` 含 `0xff` | rc 2 |
| **`x.mbt.md` 含 `0xff`** | **ICE 199** |

⇒ `.mbt.md` 走的是另一条读取路径（Markdown 解析前用 `In_channel.input_all` 整体读入），没有沿用普通源文件的 UTF-8 检查逻辑，`MalFormed` 异常直接冒泡到 ICE catcher。

## 影响

- 仓库里带一个二进制/编码损坏的 `README.mbt.md`（比如 GBK 保存、编辑器写坏），`moonc syncheck` / doctest 流程直接 ICE。
- 发生概率不高（需要非法 UTF-8），但报错信息完全没有指向"哪个文件、哪一行编码坏了"，排查体验差。

## 修复建议

1. 复用普通源文件的读取逻辑：先做 UTF-8 校验，失败则产出 `E3001` 诊断（而不是让异常冒泡）。
2. 或在 ICE catcher 前捕获 `MalFormed`，转成"文件编码非法"的普通错误。
3. 给 Markdown 读取加文件名与字节偏移，便于定位。
