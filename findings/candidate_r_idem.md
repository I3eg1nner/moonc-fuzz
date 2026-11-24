# Candidate R-idem：leading comment + 自动 `///|` 导致 fmt 非幂等

Date: 2026-11-24. Pin 不变。**未提交上游**。

## 最小 repro（2 行）

```moonbit
// head
fn main { println(1) }
```

命令：

```bash
printf '// head\nfn main { println(1) }\n' > /tmp/idem.mbt
moonfmt /tmp/idem.mbt -o /tmp/idem1.mbt
moonfmt /tmp/idem1.mbt -o /tmp/idem2.mbt
```

## 3/3

`idem1.mbt` 与 `idem2.mbt` 3 次均不同；字节级 diff：

```diff
--- idem1
+++ idem2
@@ -1,4 +1,5 @@
 // head
+
 ///|
 fn main {
   println(1)
 }
```

- 原始 `moon check` rc0；
- `fmt(fmt(x)) != fmt(x)`；
- 仅多一个空行，但按幂等性定义是 formatter 违例；不是 harness：两次都直接跑
  `moonfmt`，路径不同但内容比较。

p16 / p26 字节 diff 同形：

```diff
@@ -1,4 +1,5 @@
 // head
+
 ///|
 fn main {
   println(1)
 }
```

```diff
@@ -1,4 +1,5 @@
 // head
+
 ///|
 fn main {
   println(1)
 }
```

## 查重

- curated 无 leading-comment/blank-line idempotence 条目；
- GitHub 只读 query `repo:moonbitlang/moon fmt idempotent comment` /
  `repo:moonbitlang/moonbit-docs fmt idempotent comment` 未命中本轮所查
  leading comment 空行问题；
- 与 F13 不同根因：F13 是 INT_MIN 的 `--` token 合并；本条是注释块与自动
  `///|` 的空行插入。
- 未提交上游。

## 严重度

fmt1 5 行/38B → fmt2 6 行/39B → fmt3–5 稳定 6/39；只多一个空行，
不是无界增长。普通 `//` 触发；`///` 文档注释、空行、属性不触发。curated 197
是 indented comment 被移入错误 impl body，症状不同。
