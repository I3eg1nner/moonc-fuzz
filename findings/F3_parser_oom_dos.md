# F3 — 解析错误恢复不前进导致内存无限增长（OOM DoS）

| 项目 | 值 |
|------|-----|
| 目标 | `moonc v0.10.20+65efd5b93 (2026-11-05)` |
| 输入类型 | `.mbt` 源码 |
| 现象 | 99% CPU、RSS 线性增长（60 s 约 25 GB），最终被 OOM kill |
| 最小输入 | **19 字节**：`fn r(){y(for in ]` + `\n` + `[` |
| 发现方式 | fuzz 第 1 轮 T1（syncheck）超时判据 |
| 严重性 | 高（19 字节 → 打爆内存；`moon check` 必中） |

## 复现

```bash
cd poc/f3_parser_oom
moon check          # 内存一路涨到被 OOM 杀
```

单文件直接压测（建议先限制内存，否则会吃掉整机内存）：

```bash
printf 'fn r(){y(for in ]\n[' > x.mbt
ulimit -v 2000000            # 2 GB
moonc syncheck x.mbt         # → Fatal error: out of memory / Aborted
```

实测（不设限）：

```
$ /usr/bin/time -v timeout 60 moonc syncheck x.mbt
Percent of CPU this job got: 99%
Elapsed: 1:02.16
Maximum resident set size (kbytes): 24997180     # ≈ 24.9 GB，仍在增长
Exit status: 124                                 # timeout 杀掉
```

`moon check` 路径同样中招：

```
$ (ulimit -v 2000000; timeout 40 moon check)
Fatal error: out of memory
Aborted (core dumped)
Error: failed when checking project
```

## 触发条件（已做边界实验）

`cmd/main.mbt` 完整内容（19 字节）：

```moonbit
fn r(){y(for in ]
[
```

| 变体 | 结果 |
|------|------|
| `fn r(){y(for in ]\n[` | **OOM / 不返回** |
| `y(for in ]\n[`（无外层 `{`） | rc 2，正常报错 |
| `fn r(){y(for in ]`（无下一行 `[`） | rc 2 |
| `fn r(){y(for in ]\n` + 2/3/4 个 `[` | 同样 OOM |
| `fn r(){for in ]\n[` | rc 2 |
| `fn r(){@g.::y(for in ]\n[` | OOM（同族，原始 fuzz 样本） |

要点：**函数体 + `标识符(for in ]` + 换行 + 开头 `[`**。少了外层 `{}` 或少了 `[` 都不触发。

## 根因分析（假设）

错误恢复（Menhir 的 `error` 产生式 / 手写 recovery）在遇到 `for in ]` 时进入一个**不消耗输入**的循环：
- 既不前进 token 指针，也不跳出；
- 每一轮都向 diagnostics / segment 缓冲里追加内容 ⇒ 内存单调增长，CPU 100%。

如果是纯死循环不分配，RSS 应该稳定；实测 RSS 线性上涨，说明"循环 + 分配"。这与 F1 一样都指向 `report_failed_to_parse` 附近的错误恢复实现。

## 影响

- 19 字节源码 + `moon check`/`moon build` ⇒ 构建机 OOM（8–16 GB 的开发机几秒内就没了，还会波及同机其它进程）。
- 恶意仓库/PR 里放一行即可让 CI runner 崩掉；对 IDE（后台 `syncheck`）同样致命。
- 与 F1 相比更"安静"：没有崩溃输出，看起来只是卡住，容易被误判为正常编译慢。

## 修复建议

1. **前进性保证**：错误恢复循环里记录 `last_token_index`，若一轮结束未前进则强制 `skip` 一个 token 或退出恢复。
2. 诊断数量上限（如 200 条）与恢复深度上限。
3. 解析器加"输入消费进度"断言（debug build），在 CI 里跑一遍语料，可提前拦住这类回归。
4. 单元测试里加"病态 token 序列"用例（未闭合 `for`/`match` + 换行 `[`）。
