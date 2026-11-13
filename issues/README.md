# 上游 issue 草稿

这里的 7 份草稿对应 `poc/` 中已复现的缺陷。11 个 PoC 不拆成 11 条 issue：
F1b、F2b、F4b 与各自的主缺陷共用栈顶或异常签名，作为同一条 issue 里的第二个
witness。

## 提交位置

`moonbitlang/moonbit-compiler` 的 Issues 已关闭（`has_issues=false`），不能直接
在那里提交。ICE banner 指向的是 `moonbitlang/moonbit-docs` 的 ICE 模板：

```
https://github.com/moonbitlang/moonbit-docs/issues/new?template=ice.md
```

- label：`bug`、`ICE`（模板自带）
- 标题前缀：`ICE: `
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
