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

## 步骤 c（5 分钟）

见下方更新；coverage_skipped 在 capsule lane 里没有覆盖预算，报告为
`n/a`，不冒充 fuzz 的计数器。

## 边界

- 未接入主 campaign 的 seed 源：主 fuzz 的 `--seed-dir` 只加载单文件，
  接整包需要 cargo/capsule 队列与 stage 调度，本轮未做；
- 只有 1 个包；扩到 3 个需要 3 个 baseline 可构建的多文件包（f8 去掉触发、
  f6_min、另一个待找），未做；
- 变异用的是现有文本变异，不是类型保持变异；
- 未保存 crash witness 路径（crashes=0 时无需），接 triage 前要补。
