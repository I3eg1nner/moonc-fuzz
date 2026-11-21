# P1-3 候选 triage 流水线

Date: 2026-11-21. 依据：独立评审 P1-3（candidate 没有自动复验/归约）。
工具链 pin 未改。

## 问题

campaign 保存的 finding 只有 `status=candidate`；`cmd/verify` 与
`cmd/minimize` 存在但靠人手工串联，正式仓库里没有"什么条件下可以标
confirmed"的规则。

## 规则（`cmd/triage`）

输入一个 candidate 目录（`in.mbt` + 可选 `meta.json`）：

1. **fresh copy ×3**：每次重新生成 `moon.mod`/`moon.pkg`，同一 stage 跑
   三次，缺陷签名必须三次一致；
2. **放宽 timeout**：用 campaign 预算的 3 倍，机器抖动不能被当成挂起；
3. **负控**：同一个 stage 下跑一个良性包，必须无缺陷；
4. **已知 witness 匹配**：命中已知类（F2/F3/F4/F7/F8/F9）记 `known`，
   不记 `confirmed`——已知缺陷的复现不是新发现；
5. **可选 minimize**：传 `--minimize PATH` 时，归约器必须
   `published:true` 才算通过。

判定是纯函数（`triage_status`），状态只有
`confirmed | known | flaky | inconclusive | timeout-only`。

## 正负控（`scripts/triage_selftest.sh`）

```
pos-known    F2 ICE witness        -> status=known, reproduced="3/3"
neg-valid    fn main { println }   -> status=inconclusive（不是 confirmed）
neg-timeout  无限循环 + 1ms 预算    -> status=inconclusive（不是 confirmed）
triage selftest: ok
```

`pos-known` 的实际输出：

```json
{"case":".../pos-known","status":"known","reproduced":"3/3",
 "signature":"crash|ICE|Invalid_argument(\"Char.chr\")","known":"F2",
 "control_clean":true}
```

`flaky`（1–2/3）分支无法用确定性输入稳定注入，改用纯函数单元测试覆盖：
`triage_status(true,false,2,true,false,false,false) == "flaky"`，以及
"minimize 要求但未发布" → `flaky`。

## 边界

- 判定基于 `@stager.signature`（与 campaign 同一套），但 triage 的包是
  最小包，不是原始 PoC 的完整包；对依赖多文件/依赖的候选，结论可能不同。
- `timeout-only` 永远不升级：生成程序自己死循环与编译器挂起在 build 阶段
  无法区分，必须在 run/trace 路径另做判定。
- 已知库是子串匹配，只有 6 类；命中 `known` 不会被当成新缺陷，也不会被
  当成"非缺陷"。
- 自动 triage 还没有接进 campaign 结束流程，只提供命令与脚本；接线的
  入口是 `status=candidate` 的 findings 目录。

## Campaign 集成（--triage / --triage-only）

- `--triage`：campaign 结束时遍历 `<run>/findings/<stage>/<kind>/<sig>/`，
  用与 `cmd/triage` 相同的规则逐个判定，写 `triage.jsonl` 与
  `regression.txt`（只含 confirmed），summary 增加
  `triage_checked/confirmed/known/flaky/inconclusive`；
- `--triage-only DIR`：对既有 findings 树执行同一函数并退出，供复检与验收；
- confirmed 时自动调用 `cmd/minimize`，要求 `published:true`；minimize 不存在
  或未发布则退回 `flaky`，不会标 confirmed。

端到端验收（`scripts/triage_campaign_selftest.sh`，门禁 `triage_campaign`）：

```
tree: known(F2) + benign(valid) + timeout(while true)
out:  {"triaged":3,"confirmed":0,"known":1,"flaky":0,"inconclusive":2}
```

走的是 campaign 的 `--triage-only` 路径，不是纯函数分类器。
