# Capsule → save → triage（真实包）

Date: 2026-11-21. 依据：本轮 (1)。工具链 pin 未改。

## 链路

1. `cmd/capsule` 对每个失败变异（rc!=0，含 ICE）调用
   `save_witness`：写 `in.mbt`、`baseline.mbt`、整包快照 `pkg/`、
   `capsule.json`（moon 路径、完整 cmd、被变异文件、target、stage、signature）
   与 `meta.json`（stage/kind/status=candidate/signature），目录名用
   `corpus.dir_slug`；
2. `--triage` 调用 `fuzz --triage-only <out>/findings`，即 `cmd/triage`；
3. `cmd/triage` 检测到 `capsule.json` 时进入**包模式**：复制 `pkg/`、把
   `in.mbt` 写回记录的文件、跑记录的 argv（不是重造单文件包）；负控用
   `baseline.mbt` 跑同一 argv 并要求 rc=0；签名仍用
   `cluster.crash_signature`，与保存端一致。

## 正控（f8 已知触发点）

f8 包基线用"去掉 raise? 的可构建版本"，`--known` 注入原始触发文件：

```json
{"attempts":1,"ok":0,"failed":1,"crashes":0,
 "triage":{"triaged":2,"confirmed":0,"known":1,"flaky":0,"inconclusive":1}}
```

- triage 把注入的 F8 触发判为 **known**（签名
  `crash|ICE|File "moonc.ml", line ..., Assertion failed|known=F8`），
  3/3 复现；
- 另一个 BUILD_FAIL 变异判 inconclusive（非 crash 类，不升级）；
- witness 目录保留 `pkg/`、`in.mbt`、`baseline.mbt`、`capsule.json`。

## witness 可 replay（独立于 triage）

把保留的 `pkg/` 复制出来、覆盖 `repro/repro.mbt` 为 `in.mbt`、跑同一 argv：

```
replay_rc=1；日志中 "Assertion failed" 出现 1 次
```

即 witness 在 triage 之外也能复现。

## 边界

- 包模式不做归约（minimize 只支持单文件），triage 因此把
  `minimise_required=false`，不会因为缺少 `published` 把候选判 flaky；
  正控落在 known，不受影响；
- capsule 仍不接主 campaign 的 seed 队列（独立 lane）；本轮接的是
  save→triage 链，不是 fuzz 调度；
- `--known` 是测试入口，不会在正常变异循环里伪造 witness；
- triage 的包模式按 `capsule.json` 的 cmd 重放，cmd 里若含绝对路径（本包
  没有）会依赖原环境。
