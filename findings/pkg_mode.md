# 主 campaign 的包模式（capsule 整包）

Date: 2026-11-21. 工具链 pin 未改。

## 实现

新增 fuzz 参数：

```
--pkg-seed DIR      整包目录（含 moon.mod/moon.pkg）
--pkg-file REL      只变异这个文件
--pkg-argv "test --target js --build-only"
```

worker 在包模式下：复制整包到自己的 `pkgwd_<id>`（去掉 `_build`），每轮只
变异 `--pkg-file`、写回、用原 argv 跑 `moon`，然后恢复原文；rc!=0 时把
`in.mbt`、`baseline.mbt`、整包 `pkg/`、`capsule.json`（moon/cmd/file）、
`meta.json` 写到 `findings/build/<kind>/<sig>/`，与 capsule 的保存布局一致。
campaign 结束的 `--triage` 会走 `cmd/triage` 的 capsule 包模式重放。

## 10 分钟结果（f8 夹具，2 workers，seed=1）

| 指标 | 值 |
|---|---:|
| it / T2 尝试 | 12,160 |
| T2 成功 | 356（**2.9%**） |
| T3 | 0（argv 是 `--build-only`，没有运行阶段） |
| coverage_skipped | 0（包模式不用 fuzz 的覆盖持久预算，字段不适用） |
| triage_checked | 3 |
| triage_confirmed / known / flaky / inconclusive | 0 / 0 / 0 / **3** |
| max RSS | 58 MB |

## 失败包确实进了 save→triage

`findings/build/BUILD_FAIL/<sig>/` 下有整包快照与 `capsule.json`；
`triage.jsonl` 有三条记录，`status=inconclusive`。这是**规则正确**：
BUILD_FAIL 不是 crash 类，triage 不应晋级。triage 的包模式用
`baseline.mbt` 做负控、按 `capsule.json` 的原 argv 重放 3 次；能进入这条链
本身就是本轮要证明的（此前 capsule 只是独立 lane）。

## 边界

- 包模式的 T2 成功率 2.9%，与 capsule 独立 lane（2.6–4.2%）一致；
- 没有 T3：argv 只构建。要 T3 需要带 expected 的运行 argv 与 target，
  包模式还没接；
- triage 只跑了 3 条：`triage_tree` 遍历到的唯一签名目录本来就只有 3 个
  （保存按签名去重），不是截断到 3；
- `coverage_skipped=0` 不代表"没有跳过"，而是该 lane 不经过覆盖预算；
- 依赖（async registry）在测试包里可用；换包需要 registry 可解析。
