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

见下。
