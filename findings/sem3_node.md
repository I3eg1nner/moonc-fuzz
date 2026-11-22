# Node 独立参考与嵌套组合

Date: 2026-11-22. 工具链 pin 未改。

## 参考独立性

- typed 族（struct/struct_nested/enum/box/closure/typed_nested）与 `i64` 基础族
  额外生成一份 **JS 程序**，由 `node -e` 执行得到 expected；
  - i32 用 `|0`，i64 用 `BigInt.asIntN(64, ...)` 模拟 wrap；
  - 该 expected **不经过 moonc**，因此共享前端/中端/native 的 bug 不会污染它；
- MoonBit 参考仍保留；两者不一致时写 `reference_disagree/<case>/`
  （source/moon_ref/node_ref/node.js），记 `oracle_candidate`，人工判；
- 其余族（i32/string/array/control 等）仍用 MoonBit 参考（共模风险未消除），
  能力表里如实标注。

## 嵌套组合

`typed_nested`：`struct Outer { e : E; k }`，`enum E { A; B(Box[Inner]) }`，
`enum Box[T] { Val(T) }`，`struct Inner { v }`；match 嵌套后显式打印
`i.v + o.k`。JS 镜像用对象/tag 构造，expected 由 node 给出。

## 控制

- `--inject-node`（把 node expected 改一位）：typed 每族 2/2 witness，共 12；
- `--inject-moon`（把 MoonBit expected 改一位）：产生 63 oracle_candidate、
  18 个 `reference_disagree` 证据目录；
- `--inject-all`：oracle_candidate，不产 witness；
- float 与 min/-1 仍 excluded。

## 全同步族 node 参考（第二批）

- `i32`、`string_ascii`、`array_inbounds`、`array_oob`（node 显式 throw 模拟
  trap，rc≠0 视为 trap 参考）、`loop_counter`、`expr_i32`（`|0` + d32/m32）、
  `expr_i64`（BigInt.asIntN）、`var_use`、`if_else`、`func_call`、
  `array_alias`、`array_nested`、`utf8_string`（`s.length` + `[...s].length`）
  全部改为 node expected；
- `boundary_i32/i64` 仍用 MoonBit 参考（min/-1 属 allowed_divergence，不参与
  node 对比）；
- 能力表（终版）：

| 族 | expected 来源 | 经过 moonc? |
|---|---|---|
| i32/i64/expr_*/string/array/loop/var/if/func/alias/nested/utf8 | node (`-e` JS) | 否 |
| struct/enum/generic Box/closure/typed_nested | node | 否 |
| boundary_i32/i64 | MoonBit 参考（allowed 域） | 是 |
| float | excluded | — |

## 30 分钟结果

## 全同步族 node 参考（第二批）

- `i32`、`string_ascii`、`array_inbounds`、`array_oob`（node 显式 throw 模拟
  trap，rc≠0 视为 trap 参考）、`loop_counter`、`expr_i32`（`|0` + d32/m32）、
  `expr_i64`（BigInt.asIntN）、`var_use`、`if_else`、`func_call`、
  `array_alias`、`array_nested`、`utf8_string`（`s.length` + `[...s].length`）
  全部改为 node expected；
- `boundary_i32/i64` 仍用 MoonBit 参考（min/-1 属 allowed_divergence，不参与
  node 对比）；
- 能力表（终版）：

| 族 | expected 来源 | 经过 moonc? |
|---|---|---|
| i32/i64/expr_*/string/array/loop/var/if/func/alias/nested/utf8 | node (`-e` JS) | 否 |
| struct/enum/generic Box/closure/typed_nested | node | 否 |
| boundary_i32/i64 | MoonBit 参考（allowed 域） | 是 |
| float | excluded | — |

## 30 分钟结果（4,593 cases / unique_programs 2,903，seed 3）

| 组 | attempts each | witness | oracle_candidate | excluded | inconclusive |
|---|---:|---:|---:|---:|---:|
| 22 个同步族（含 typed_nested、i64） | 199–200 | 0 | 0 | 0 | 0 |
| boundary_i32 / boundary_i64 | 200 | 0 | 0 | 18 / 18（min/-1 allowed） | 0 |
| float_format | 199 | 0 | 0 | 199 | 0 |

`unique_witness=0`，`reference_disagree` 目录 0，`oracle_candidates=0`。

## 能力表（参考实现是否经过 moonc）

| 族 | expected 来源 | 经过 moonc? |
|---|---|---|
| struct_fields / struct_nested / enum_match / generic_box / closure_capture / typed_nested | node 执行 JS；MoonBit 参考做交叉检查 | **否** |
| i64（常量对） | node BigInt.asIntN(64) + MoonBit 交叉检查 | **否** |
| i32/string/array/control/loop/expr_* 等其余同步族 | MoonBit 参考求值器 | 是（共模风险仍在） |
| float | excluded | — |
| min/-1、除零 | excluded_domain（allowed） | — |

## 结论

- 独立参考已落地到 typed 族与 i64 基础族：三后端 + node 三方比较，
  node 与 MoonBit 参考不一致会单独进 `reference_disagree` 并计
  oracle_candidate；本轮为 0；
- 30 分钟仍 **0 compiler inconsistency witness**；
- 域已扩到 struct/enum/泛型 Box/闭包/嵌套组合，但仍是模板级组合
  （0–2 层），不是完整 typed AST + 泛型单态化；其余同步族仍用 MoonBit
  参考，共模风险未完全消除；async 仍由独立 xdiff harness 覆盖。
