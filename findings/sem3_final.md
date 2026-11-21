# sem3 结构化差分引擎：最终状态

Date: 2026-11-21. 工具链 pin 未改。

## 能力

- 变量 `let x = expr` + 多次引用（`x + x`）；
- `if/else` 分支；
- `while` 计数循环；
- 同文件函数定义/调用（`fn add(a,b) { a+b }`）；
- 嵌套数组、数组别名、越界 trap；
- Int32/Int64 表达式树（深度 2–4）+ 位运算/移位/边界；
- ASCII 与 UTF-8 字符串 `length`（UTF-16 单元）/`char_length`。

参考求值器是进程内实现（表达式树求值、generator 端已知的变量/分支选择），
**不是**调用被测后端运行时。i64 参考值仍用宿主 Int64（wrap），存在共模风险，
这是已知未完成项。

## 控制

- `--inject js`：每个可比族（含 var_use/if_else/func_call/array_nested）
  都产生 witness；
- `--inject all`：产生 oracle_candidate（47），不产生 witness；
- `float_format`：全 excluded；
- `boundary_*` 的 `min/-1`：allowed_impl_divergence，excluded；
- oracle_candidate 与 witness 分账。

## 30 分钟（**修复前**，4,831 cases / unique 2,744）

witness=0，oracle_candidate=18，inconclusive=1（expr_i32）。18 个 oracle
全部是生成器 bug：移位右操作数允许负数/巨大值、`var_use` 的 expected 未做
32 位 wrap。修正（移位计数限制 0–7、expected wrap32）后：

## 修复后 10 分钟（1,618 cases / unique 1,008）

witness=0，oracle_candidate=0，inconclusive=0；
boundary_i32/i64 excluded 13/4（allowed min/-1），float excluded 95。

## 结论

- 窄域三后端差分能力已建立并可控（正控/负控/oracle 分账均工作）；
- 仍未发现 `compiler_inconsistency_candidate`；
- 不能写“编译器无 bug”：域窄（无指针/结构体/async/真实包语义、无浮点），
  且 i64 参考与宿主共模；
- 旧“0 witness 完备”说法作废（曾静默跳过失败后端）；min/-1 为
  allowed_impl_divergence，不是缺陷。

## 资产

- witness 可 replay：`scripts/replay_sem3.sh`（本轮 witness 为 0）；
- allowed divergence 资产：`regressions/sem3_div_overflow/`；
- 本轮 oracle 候选已被生成器修复，不作为缺陷保留。
