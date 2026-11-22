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

见下。
