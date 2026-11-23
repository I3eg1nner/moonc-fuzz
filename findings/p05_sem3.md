# P0-5 sem3：真实 backend 注入与五矩阵

Date: 2026-11-23. Pin 不变。

## 入口

`sem3 --backend-cmd target=CMD`（可重复）与环境 `MODE_<TARGET>`；
覆盖时把程序路径作为最后一个参数传给 CMD。默认仍是
`moon run main.mbt --target T`。

`scripts/fake_backend.sh` 支持：ok / trap（rc134）/ compile_error
（`Error: [E9999]`）/ timeout（sleep10）/ truncated（>1MB 无换行）/
ice（`Oops, the compiler`）。

## Obs

逐 backend 记录：`target,class,stage,rc,timed_out,truncated,ice,bytes`。
`target_class` 先看 timed_out/truncated/rc，关键词只辅助。
summary 的 `backend_obs` 打 ok/trap/other/timeout/truncated。

## 五矩阵（真实 sem3 入口）

| case | modes | 结果 |
|---|---|---|
| A | 2 ok + timeout | inconclusive=1, witness=0 |
| B | ok + trap + compile_error | inconclusive=1, witness=0 |
| C | 3 trap (`array_oob`) | witness=1 |
| D | 3 ok 同输出 | witness=0, inconclusive=0（equal） |
| E | 3 ok 不同输出 | witness=1 |

脚本 `scripts/sem3_matrix_test.sh`，accept gate `sem3_observation` 直接跑它。

## 边界

- `target_class` 仍关键词辅助；`ice` 由 class 判定。
- truncated 用 >1MB 输出触发，不是真实 moonc 截断。
- 未改 pin、未发上游。
