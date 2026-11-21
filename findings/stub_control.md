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

## CI

`accept` 新增 `stub_ice_triage` 门禁（24 项，core 21），脚本自带 90 s 预算。

## 边界

- stub 只模拟 syncheck 阶段（t1），不证明 T2/包模式的未知晋级；
- 它验证的是判定链与保存/保留，不证明真实编译器存在同类缺陷；
- `--triage` 的 minimize 对 syncheck 不支持，因此 confirmed 不要求归约
  （与包模式规则一致）。
