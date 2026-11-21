# 真实包 capsule（最小版）

Date: 2026-11-21. 依据：本轮 (2)。工具链 pin 未改。

## 目标与最小范围

把"真实多文件包"作为输入单位，而不是把源文件摊平成单文件：复制整包、
只变异其中一个 `.mbt`、用**原 argv** 重放，检查包上下文是否仍成立。

## 实现（`cmd/capsule`）

`capsule --pkg DIR --file REL [--target js] [--stage test] [--duration S]`

1. 复制整包到 `<out>/work`（去掉 `_build`）；
2. 记录 `capsule.json`：包路径、被变异文件、target/stage、**完整 argv**
   （`moon` 绝对路径 + 参数）、`moon.mod`/`moon.pkg` 的 sha1、baseline rc；
3. 先跑一次 baseline，rc 必须为 0，否则拒绝继续；
4. 每轮用 `@mutate` 变异 `--file`，写回原位置，用同一 argv 跑
   `moon test --target js --build-only`（或 build/check），记录 rc/崩溃；
5. 每轮结束恢复原文；最后再跑一次 argv 做 **replay 一致性**检查。

## 步骤 a/b 结果（多文件包）

夹具：`poc/f8_async_raise_ice` 的整包（`moon.mod` + `repro/{moon.pkg,
repro.mbt,repro_test.mbt}`，依赖 `moonbitlang/async@0.22.9`），把触发 F8 的
`raise?` 去掉使 baseline 可构建——包结构与依赖保持真实。

```json
{"attempts":3,"ok":1,"failed":2,"crashes":0,"distinct_crash_lines":0,
 "baseline_rc":0,"replay_rc":0,"replay_matches":true,"ms":937,
 "coverage_skipped":"n/a (capsule lane has no coverage budget)"}
```

- baseline rc=0、replay rc=0 且 `replay_matches=true`：复制+恢复+原 argv
  的上下文是自洽的；
- 变异 3 次，1 次仍可构建、2 次被编译器拒绝，说明变异确实进到了包上下文，
  而不是被摊平的语法错误。

`capsule.json` 已记录 argv 与两个 sha1；同一包的 replay 可直接复查。

## 步骤 c（5 分钟，f8 包）

```json
{"attempts":192,"ok":8,"failed":184,"crashes":0,"distinct_crash_lines":0,
 "baseline_rc":0,"replay_rc":0,"replay_matches":true,"ms":17562,
 "coverage_skipped":"n/a (capsule lane has no coverage budget)"}
```

- **T2 成功率 8/192 = 4.2%**：变异后的包绝大多数被编译器拒绝（4.2% 仍可构建），
  说明变异确实落在包上下文里；
- **crashes=0**：没有触发 ICE，因此本轮没有可 triage 的 witness；triage 未运行，
  不伪造计数；
- `coverage_skipped` 为 `n/a`：capsule lane 没有接 fuzz 的覆盖预算，不能与
  campaign 的 `coverage_skipped` 混用；
- replay 仍与 baseline 一致（restore 后 rc=0）。

## 步骤 d（扩到 3 个包）：阻塞

| 候选 | baseline | 结论 |
|---|---|---|
| f8 整包（去掉触发） | rc=0 | 可用 |
| f9（`--release`，2 文件 + stub） | rc=0 | 可用 |
| f6_min（foreign_library） | link 失败（缺 stub） | 不可用 |
| moonldif（多文件 + bridge） | link 失败（bridge C 依赖） | 不可用 |

本仓库只有 `poc/` 下这几个多文件包；`seeds/*` 是 core 模块内的包，没有自己的
`moon.mod`，整包复制后无法独立解析模块。**3 个可构建包做不到，没有拿单文件
包凑数**。f9 的 5 分钟数字：

```json
{"attempts":195,"ok":5,"failed":190,"crashes":0,"distinct_crash_lines":0,
 "baseline_rc":0,"replay_rc":0,"replay_matches":true,"ms":18124}
```

**T2 成功率 5/195 = 2.6%**，同样 0 崩溃、无 triage witness；两个包的 replay
都一致。30 分钟扩测没有跑：只有 2 个可用包，且本轮上下文不足。

## 边界

- 未接入主 campaign 的 seed 源：主 fuzz 的 `--seed-dir` 只加载单文件，
  接整包需要 cargo/capsule 队列与 stage 调度，本轮未做；
- 只有 2 个可用包（f8 夹具、f9 release）；第 3 个候选 f6_min/moonldif
  baseline 链接失败，已记录原因，没有拿单文件包凑数；
- 变异用的是现有文本变异，不是类型保持变异；
- 未保存 crash witness 路径（crashes=0 时无需），接 triage 前要补。
