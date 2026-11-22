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
## 30 分钟（第一次全 node 运行，4,467 cases / unique 2,838）

witness 0、oracle_candidate 0；但 expr_i32/var_use/if_else 有
26/25/34 个 inconclusive：JS 表达式 `377 - -341` 被发射成 `377--341`
（node 解析成自减），node 参考失败。已给所有二元运算符加空格修复。

## 修复后 10 分钟（1,469 cases / unique 1,070，含 typed_deep）

witness 0、oracle_candidate 0、inconclusive 0、reference_disagree 0；
boundary excluded 与 float excluded 正常。23 个同步族全部通过。

## 深度

`typed_deep`：`Root{h: Holder}` → `Holder.Has(Box[Bucket])` →
`Bucket{xs: Array[Leaf], k}` → `Leaf{v}`，match 两层 + 数组下标 + 字段，
共 4 层结构组合（不是 3–5 层随机全组合，如实记录）；JS 镜像由 node 给
expected。

## 能力表终版

| 族 | expected 来源 | 经过 moonc? |
|---|---|---|
| i32/i64/expr_*/string/array/loop/var/if/func/alias/nested/utf8 | node JS | 否 |
| struct*/enum/generic/closure/typed_nested/typed_deep | node JS | 否 |
| boundary_i32/i64 | MoonBit 参考（min/-1 allowed） | 是 |
| float | excluded | — |

## 结论

在本轮域（整数/字符串/数组/控制流/struct/enum/泛型/闭包，23 族 ×3 后端 ×
node 独立 expected）内，**没有 witness、没有 oracle_candidate、
没有 reference_disagree**。这支持“该域内三后端与 node 参考一致”，但不能
外推到 async/trait/浮点/真实包语义。
