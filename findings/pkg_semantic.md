# f8 包内 10 个 TEST_FAIL 的定性

Date: 2026-11-21. 工具链 pin 未改。

来源：`/tmp/pkgt3b` 的 `pkg_mismatch/`（f8 夹具，30 分钟包 T3）。每个 witness 的 baseline
在同一包上通过；变异只改 `pick` 的 `select(...)` 调用/加 `raise`，因果是直接的。

| witness | 变异 | 失败断言 | 判定 | 说明 |
|---|---|---|---|---|
| `0c346fd441048c1f` | `select('\u{10FFFF}')` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `1f72ed1e4cc4464a` | `select(-1)` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `3aa7f58f30520dd0` | `raise Failure("x"); select(1)` | `[example/ice-repro] test repro/repro_test.mbt:1 ("repro") failed: x` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `40b9a1df4f44b5e8` | `select('a')` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `85b22a592559d556` | `select('\u{0}')` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `9025529acdf43046` | `select(-2147483648)` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `b2e535d260fed245` | `select('a')` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `ba1fcb7e0d97206c` | `select('\u{10FFFF}')` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `bfb08b9479646e22` | `select(0)` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |
| `cfd1a702a23f2499` | `select(-2147483648)` | `None != Some(1)` | **real** | 用户代码语义变化，不是 moonc 缺陷 |

## 判读口径

- **real**：变异直接改变了 `pick` 的可观察结果（`select(-1/0/'a'/...)` 让测试期望的
  `Some(1)` 变成 `None`，或 `raise` 让测试异常）。baseline 通过、变异失败，因果可复述；
- **brittle**：测试依赖未定义行为/实现细节。这 10 个都不属于：测试断言的是 `pick`
  的返回值，而变异恰好改变了它；
- **inconclusive**：无法归因。本批没有；
- **它们都不是 moonc 的 bug**：变异发生在测试夹具自己的函数里，编译器只是如实执行了
  新代码。不要把这些写成编译器缺陷。

## 可重放回归

`regressions/pkg_semantic/` 保存整包（`pkg/`）、baseline、每个 witness 的 source/argv/断言；
`scripts/replay_pkg_regressions.sh` 逐个复制整包、写入变异、跑原 argv，要求 baseline rc=0 且
每个变异 rc!=0 并出现记录的断言。
