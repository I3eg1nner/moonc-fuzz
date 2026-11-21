# sem3 深度生成与边界族

Date: 2026-11-21. 工具链 pin 未改。

## 语义探测（三后端一致，先查后写 expected）

| 行为 | 结果 |
|---|---|
| Int 溢出 | wrap（`2147483647+1 = -2147483648`） |
| Int64 溢出 | wrap（min/max 回绕） |
| 除法 | 向零截断（`-7/2=-3`） |
| 取模 | 符号随被除数（`-7%2=-1`, `7%-2=1`） |
| 移位量 | 低 5 位（Int）/低 6 位（Int64）：`1<<32=1`、`1<<-1=min` |
| 除零 | 三后端都非零退出（trap），不是返回值 |
| 字符串 `length()` | **UTF-16 code units**（`"aé🙂"` = 4） |
| `char_length()` | Unicode 标量数（`"aé🙂"` = 3） |

## 生成器

- `expr_i32` / `expr_i64`：深度 2–4 的随机表达式树，运算符
  `+ - * / % & | ^ << >>`，全括号渲染；expected 由同一棵树在进程内求值，
  32 位按 wrap 归一；
- `boundary_i32` / `boundary_i64`：min/max ±1、max*2、min/-1、负数除模、
  移位 31/32/63/64、负移位；
- `array_alias`：两个别名写同一数组；
- `utf8_string`：BMP/emoji 的 `length` 与 `char_length`；
- 原有 `i32`/`i64`/`string_ascii`/`array_inbounds`/`loop_counter`/
  `array_oob` 保留；`float_format` 仍只计 excluded。

## 控制

- 正控（`--inject js`）：旧族与 `expr_*`/`boundary_*`/`alias`/`utf8`
  每族都产生 witness（oob/float 不参与）；
- 负控：`float_format` 全 excluded；
- smoke：13 族 160 cases，0 witness、float 12 excluded（修正 UTF-16
  expected 后）。

## 30 分钟结果

| family | attempts | witness | excluded |
|---|---:|---:|---:|
| i32 | 375 | 0 | 0 |
| i64 | 376 | 0 | 0 |
| string_ascii | 376 | 0 | 0 |
| array_inbounds | 376 | 0 | 0 |
| loop_counter | 376 | 0 | 0 |
| array_oob | 376 | 0 | 0 |
| expr_i32 | 376 | 0 | 0 |
| expr_i64 | 376 | 0 | 0 |
| boundary_i32 | 376 | 0 | 0 |
| boundary_i64 | 376 | 0 | 0 |
| array_alias | 376 | 0 | 0 |
| utf8_string | 376 | 0 | 0 |
| float_format | 375 | 0 | 375 |

- witness = 0，oracle_candidate = 0（没有出现三后端一致但都不同于 expected 的 case）；
- 不是"编译器没问题"的证明：表达式树无变量/分支/函数调用，数组只有 1 元素别名，UTF-8 只测 length/char_length，除零只在探测中确认 trap、未生成；
- 正控（inject js）在旧族与新族都能抓到；负控 float 全 excluded；
- 下一轮优先级：带变量的表达式 + 分支/循环内联、除零/越界 trap 族、数组嵌套/切片、字符串索引与切片、Int64/Int 混合。

## 边界

- expr_i64 用 Int64 wrap，expr_i32 用 32 位 wrap；
- 移位量取低 5/6 位；除零未进入生成器；
- 单 seed、单次 30 分钟；本轮 witness 为 0（replay 脚本已备）。


## 观测修正后的结果（重要：上面的 0 witness 表作废）

旧 sem3 只统计 rc=0 目标数，后端 compile_error/timeout/trap 会被静默跳过，
所以上一轮"0 witness"不可引用。修正后 10 分钟验证（1,602 cases，
unique_programs=832）：

| family | attempts | witness（attempt 级） | inconclusive | oracle_candidate |
|---|---:|---:|---:|---:|
| boundary_i32 | 123 | 8 | 0 | 0 |
| boundary_i64 | 123 | 13 | 0 | 0 |
| 其余 11 族 | ~123 each | 0 | 0 | 0 |
| float_format | 123 | 0 (excluded 123) | 0 | 0 |

**unique_witness = 2**（按源 sha1 去重，21 个 witness 目录只是同一程序重复）：

1. `-2147483648 / -1`：js 返回 `-2147483648`（wrap），wasm-gc/native **trap**
2. `-9223372036854775808L / -1L`：同上

两者在 `regressions/sem3_div_overflow/` 可离线 replay。这是**真实的后端行为
不一致 candidate**（除法溢出时 js wrap、wasm/native trap），不是 oracle
bug；是否属于语言允许的实现差异需要规范确认，暂不冒充编译器 bug。

oracle_candidate = 0（修正 shift 右操作数与 i32 div wrap 后，之前的
expr_i64 全后端一致但 expected 不同的问题消失）。

### 口径

- "未观察到稳定收益" ≠ "已证明无差异"；
- "窄域三后端差分能力已建立" ≠ "几千个完备 case 通过"：cases 有重复
  （unique 832/1,602），域仍窄，且本轮修掉了自己的 render/oracle bug。
