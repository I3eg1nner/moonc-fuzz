# sem3 类型化结构族（struct/enum/generic/closure）

Date: 2026-11-22. 工具链 pin 未改。

## 新增族

| family | 构造 | expected |
|---|---|---|
| `struct_fields` | `struct P{x,y}` + 构造 + 字段显式打印 + `sum(p)` | 字段值 + 和 |
| `struct_nested` | `Outer{a: Inner, b}` | `a.v`/`b` |
| `enum_match` | `enum E{A;B(Int);C(Int,Int)}` + match 三分支 | 选中分支值 |
| `generic_box` | `enum Box[T]{Val(T)}`，`Box[Int]` + match | payload |
| `closure_capture` | `let f = fn(x){ x + k }` | k+x |

打印全部**逐字段/逐值显式**，不依赖 derive Show，避免格式化差异假阳性。
类型正确性由模板构造保证（每族只有合法构造；enum 分支/模式、泛型实例化固定）。

## i64 参考独立性

`te_eval` 的 64 位 Add/Sub/Mul 改为 `UInt64` 位运算 + `reinterpret_as_int64`
模拟 wrap，不再依赖宿主 Int64 溢出行为；32 位仍 `te_wrap32`。

## 控制

- `--inject js`：struct/nested/enum/box/closure 每族都产 witness（3/3），
  float 仍 excluded；
- `--inject all`：oracle_candidate 分账（47），不产 witness；
- `min/-1` 与除零：excluded_domain（allowed_impl_divergence）。

## async（第三批）

sem3 不混入 async。仓库已有独立的 `cmd/xdiff --family async` harness
（异步测试矩阵、逐测试状态、独立阻塞/超时语义）；本批未把它并入 sem3，
也没有声称 sem3 覆盖 async。最小 await/async fn 的确定性 case 仍是下一步。

## 30 分钟结果

## 30 分钟结果（4,746 cases / unique_programs 2,938）

| family group | attempts each | witness | oracle_candidate | excluded | inconclusive |
|---|---:|---:|---:|---:|---:|
| i32/i64/string/array/loop/oob/expr/var/if/func/nested | 215–216 | 0 | 0 | 0 | 0 |
| struct_fields / struct_nested / enum_match / generic_box / closure_capture | 215–216 | 0 | 0 | 0 | 0 |
| boundary_i32 / boundary_i64 | 216 | 0 | 0 | 20 / 20（min/-1 allowed） | 0 |
| float_format | 215 | 0 | 0 | 215 | 0 |

- `unique_witness=0`，`oracle_candidates=0`，`inconclusive=0`；
- 正控（inject js）对每个新族命中 3/3；`--inject all` 只产 oracle；
- 结论仍只能是"窄域三后端差分能力已建立"：**没有** compiler
  inconsistency candidate；域已扩到 struct/enum/泛型/闭包/嵌套数组/控制流，
  但仍无指针、结构体可变别名、trait、async、真实包语义；i64 参考虽改用
  UInt64，仍与被测编译器同源（共模风险未消除）；
- async 未并入 sem3，仍由独立 `cmd/xdiff --family async` 覆盖。

## 复现

`scripts/replay_sem3.sh WITNESS`；本轮 witness 为 0，无新资产。
