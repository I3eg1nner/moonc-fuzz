# Stub 编译器：未知 witness 端到端 confirmed

Date: 2026-11-21. 工具链 pin 未改。

## 目的

真实 ICE 都落在 known 表里，无法验收"未知缺陷晋级"。用假 `moonc` 造一条
表外 ICE，驱动真实的 `save_crash → triage` 链。

## 方法（`scripts/stub_ice_triage.sh`）

- 临时 `MOON_HOME/bin/moonc`：参数里任一文件含 `STUB_UNKNOWN_ICE` 时输出
  `Oops, the compiler has encountered an exception` +
  `Error: Machine_error(kind=unsupported; who="Stub_machine.unknown_op")`，
  exit 199；否则 `exec` 真实 moonc；
- 只给 1 个 marker seed，fuzz 跑 90 s、`--triage`；`moon`/`moonfmt`
  软链到真实工具；
- 断言 summary `triage_confirmed≥1`、`triage_known=0`，且
  `findings/t1/ICE/.../confirmed/in.mbt` 存在。

## 结果

```json
{"it":4253,"triage_checked":1,"triage_confirmed":1,"triage_known":0,
 "triage_flaky":0,"triage_inconclusive":0}
```

witness 保留在 `confirmed/in.mbt`；签名
`crash|ICE|Machine_error(kind=unsupported; who="Stub_machine.unknown_op"...)`
不含 known 标签，3/3 + 负控通过后判 confirmed。

## t2 / 包模式：尝试过，被工具链路径挡住

脚本里也构造了 t2（`// STUB_T2_ICE` 顶部注释 + 40 个 helper，body-only 变异
保留注释）与包模式（capsule `--known` 带 marker）。t2 能真实产生
`stage=t2` 的 ICE finding（`triage_checked=1`），但 triage 复跑阶段是
`moon build`，而 **`moon` 会解析它自己的 moonc**：把 stub 放在
`MOON_HOME/bin` 且 `PATH` 最前，直接执行 `moon build` 仍是 rc=0、没有
`Machine_error`（实测 `/tmp/t2pkg`）。因此 t2 重放签名是 `ok`，判
inconclusive；包模式同理（还受 registry 解析影响）。

结论：t1/syncheck 的未知晋级已端到端；**t2/build 与包模式的 stub 控制
当前被 `moon` 的编译器解析路径阻塞**，需要包一层 `moon` wrapper（或在
triage 里直接调 moonc build-package）才能覆盖。脚本保留 t2 报告但不作为
门禁断言，避免把未验证的链路写成通过。

## CI

`accept` 新增 `stub_ice_triage` 门禁（24 项，core 21），断言 t1 的
confirmed=1 与 witness 保留；t2 只打印状态。

## 边界

- stub 只证明了 syncheck 阶段（t1）的未知晋级；
- 它验证的是判定链与保存/保留，不证明真实编译器存在同类缺陷；
- `--triage` 的 minimize 对 syncheck 不支持，因此 confirmed 不要求归约
  （与包模式规则一致）。
