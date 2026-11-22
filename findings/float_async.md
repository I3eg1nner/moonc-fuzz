# 浮点位型与 async 确定性域

Date: 2026-11-22. 工具链 pin 未改。

## 浮点（`float_bits` / `float_cmp`）

- MoonBit：`Double.reinterpret_as_uint64()` 打印**位型十进制**；
- node：`DataView.setFloat64` + `getBigUint64()` 取同一 bit pattern；
- 算子：`+ - * /`、`sqrt`、`floor/ceil/round/trunc`、`min/max`、比较；
- 语义域：IEEE-754 默认 round-to-nearest；**NaN payload / signaling NaN
  排除**（本生成器不产生 NaN：sqrt 输入为正、除数非零）；
- 不比较格式化文本，只比较位型/布尔。

控制：`--inject-node` 可把 node expected 改一位 → 每族 witness；NaN/格式化
不进入比较。

## async（`cmd/asem`，固定 10+1 case）

- 每个 case 是 async test：`async fn` + await、顺序 A/B/D、异常传播；
- node 参考用 `async/await` Promise 计算**完成顺序与输出**；
- 只比较以 `ASEM:` 开头的确定性行，不比较调度时序；
- 异常文本归一化为 `ASEM:E=` 前缀（`Failure(boom)` vs `boom` 属 Display
  差异，不计 witness）；
- 目标若 `Total tests: 0`（如 wasm-gc 对 async test）记为 unsupported，
  不参与比较；
- 控制：`--inject-node` 24/24 witness。

## 能力表

| 域 | 比较对象 | expected 来源 | 经过 moonc? |
|---|---|---|---|
| Float/Double | 位型、布尔 | node DataView | 否 |
| async | 确定性完成顺序/输出（不含时序、异常 Display） | node Promise | 否 |
| trait/可变别名/指针 | 未覆盖 | — | — |

## 30 分钟结果

## 浮点 30 分钟（seed 7）

```
cases=4,417  unique_programs=3,016  witness=0  oracle_candidate=0
float_bits: attempts=170, witness=0, excluded=0, inconclusive=0
float_cmp : attempts=169, witness=0, excluded=0, inconclusive=0
float_format: attempts=169, excluded=169（策略排除）
```

在本轮覆盖的算子里（+ - * /、sqrt、floor/ceil/round/trunc、min/max、比较，
IEEE-754 默认 round-to-nearest，非 NaN），三后端位型与 node DataView 一致，
未发现分歧。NaN payload/signaling NaN 未生成（排除域，不能据此说 NaN 行为
一致）。Float（f32）没有可用的 `to_bits`/reinterpret API，本批只覆盖
Double，能力表如实标注。

## async

固定 10 个顺序 case + 1 个异常传播 case；`--inject-node` 24/24 witness。
node 参考为 Promise/await；`wasm-gc` 对 async test 报 `Total tests: 0`，
按 unsupported 跳过，不参与比较。异常文本按 `ASEM:E=` 前缀归一化，不比较
`Failure(boom)` vs `boom` 的 Display。


## async 30 分钟

```
attempts=2,122  cases=11  witness=0  oracle_candidate=0
excluded=0  inconclusive=0
```

- 每个 attempt 跑 js/native（wasm-gc 对 async test 报 `Total tests: 0`，
  按 unsupported 跳过），只比较 `ASEM:` 行；
- 固定 10 个顺序 case + 1 个异常传播 case，30 分钟内重复执行 2,122 次；
- 无 witness、无 oracle、无 inconclusive。**随机 3–4 层 async 组合未做**，
  能力表按固定 case 标注。

## 结论

- 浮点（Double、本轮算子集、非 NaN）位型与 node DataView 一致；
- async 固定场景的确定性完成顺序/输出与 node Promise 一致；
- 域外：Float(f32) 无 bits API、NaN payload/signaling NaN、trait、可变别名、
  指针、随机深 async 组合均未覆盖，不能由本轮结果外推。
