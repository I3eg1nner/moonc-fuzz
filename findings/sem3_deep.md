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

见下。
