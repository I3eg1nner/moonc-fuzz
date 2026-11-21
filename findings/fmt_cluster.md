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

## 验证（`scripts/fmt_cluster_selftest.sh`，门禁 `fmt_cluster`）

确定性版本不再依赖 campaign 的随机采样：`cmd/clusterprobe reparse` 对每个
文件执行真实的 `moonfmt`，再对 formatter 输出执行真实的 `moonc syncheck`，
打印 `cluster.formatter_signature(reparse rc/stderr/stdout)` —— 与 campaign
的 REPARSE 路径同一个函数。

F5 形状 `fn f(y : Int) -> Int { +y }` 的三个不同源：

```
{"file":".../a.mbt","sig":"fmt|rc=2"}
{"file":".../b.mbt","sig":"fmt|rc=2"}
{"file":".../c.mbt","sig":"fmt|rc=2"}
{"file":".../ok.mbt","sig":"fmt|rc=0"}
fmt cluster selftest: ok
```

三个同错误合并、一个正常源分离。此前用 150 s campaign 的版本也能得到
`reparse_dirs=1`，但在负载下会 0 次 fmt 事件，不适合做门禁；campaign 路径的
一次性证据保留在提交历史里。
## 边界

- 端到端只验证"同错误合并"；"不同错误分离"是签名级测试。
- REPARSE 目录里只保留**最后一个**触发该签名的 `formatted.mbt`；多个 witness
  共享目录，后写覆盖先写（`ensure_dir` + `write`）。
- 签名仍以数字归一化后的文本为键；不同错误若归一化后相同会合并，这是已知
  粗粒度。
