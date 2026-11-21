# Formatter 聚类端到端

Date: 2026-11-21. 依据：本轮第 3 项。工具链 pin 未改。

## 问题

REPARSE 分支用的是 `short_hash("fmt|" + detail + "|" + short_hash(src))`：
即使 `detail` 相同，**源哈希**也把每个输入拆成独立目录。formatter 路径因此
"一输入一目录"，不能按缺陷聚合。

## 修复

- REPARSE 签名改为 `cluster.formatter_signature(rr.rc, rr.stderr,
  rr.stdout)`，其中 `rr` 是**重新解析 formatter 输出**的那次运行——签名来自
  失败本身，不含源哈希；
- formatter 自身失败的路径同样改用 `formatter_signature(fr...)`；
- finding 目录名走 `corpus.dir_slug`（见签名转义修复），不再依赖原字符串。

## 端到端验证（`scripts/fmt_cluster_selftest.sh`，门禁 `fmt_cluster`）

三个不同源、同一个 F5 风格前缀 `+`：

```moonbit
fn f() { +1 }  /  fn g() { +2 }  /  fn h() { +3 }
```

跑 60 s campaign（`--fmt-check --seed-dir`）后：

```
reparse_dirs=1
fmt cluster selftest: ok
```

修复前这个计数是 3（每个源一个目录）。

不同错误的分离由 `cluster_wbtest.mbt` 的单测覆盖（`fmt|Parse error...`
vs `fmt|unterminated string` 互异）；没有找到另一种能在端到端 campaign 里
稳定产生的 formatter 错误，这一点如实记录。

## 边界

- 端到端只验证"同错误合并"；"不同错误分离"是签名级测试。
- REPARSE 目录里只保留**最后一个**触发该签名的 `formatted.mbt`；多个 witness
  共享目录，后写覆盖先写（`ensure_dir` + `write`）。
- 签名仍以数字归一化后的文本为键；不同错误若归一化后相同会合并，这是已知
  粗粒度。
