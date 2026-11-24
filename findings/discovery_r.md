# Discovery R：idem 20 与注释 token 60 逐条打开

Date: 2026-11-24. Pin 不变。commit 不 push。

## R1 20 个 idem_bad

全部来自 `i%10==6`：leading `// head` 注释。

3 个实例：

- p6：`// head\nfn main { println(1) }`
- p16 / p26：同形态，不同包名。

字节级 diff（p6）：

```diff
--- idem1.mbt
+++ idem2.mbt
@@ -1,4 +1,5 @@
 // head
+
 ///|
 fn main {
   println(1)
 }
```

3/3 均复现；原始 `moon check` rc0；两次都是 `moonfmt`，不是路径/换行 harness。
按幂等性定义判为**真非幂等**，最小 repro 2 行，立 `candidate_r_idem.md`。

与 F13 不同根因：F13 是 INT_MIN `--` token 合并；本候选是注释与自动 `///|`
之间插入空行。

## R2 60 个 token_bad

| 类别 | 数量 | 证据 |
|---|---:|---|
| 参数列表尾逗号 | 20 | p3：`fn f( // param x:Int)` → `x:Int32,`，注释保留 |
| 数组尾逗号 | 20 | p7：`[1, // one 2,3]` → 多尾逗号，注释保留 |
| 分号删除/语句换行 | 20 | p8：`'A'; println` → `'A'` 换行 `println` |

- 注释消失 0；
- 注释跨语句移动 0；
- 所有 60 条都保留 `// param`、`// one` 等注释；
- 只有尾逗号/可选分号/自动 `///|`，不是注释缺陷；
- 不立候选。

## R3/R4

新候选 1：R-idem；F13 仍是另一条。R-idem 与 F13 不同根因，需分开记录。
