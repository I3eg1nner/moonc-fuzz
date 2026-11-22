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

## 30 分钟结果

见下。
