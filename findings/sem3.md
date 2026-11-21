# 三后端语义差分（IR 之外的算子族生成器）

Date: 2026-11-21. 工具链 pin 未改。

## 实现（`cmd/sem3`）

每轮生成一个小程序，**同一份源码**在 js / wasm-gc / native 上各跑一次，把
stdout+rc 与**进程内参考解释器**的 expected 比较；三个后端都与 expected
一致才算 pass。任何不一致（含三个后端一致但都错）都落盘：

```
<out>/witness/<case>/{main.mbt, expected.txt, actual.txt, argv.txt}
```

算子族：`i32`（+ - * & | ^ << >>，移位量 `& 7`）、`i64`（+ - *，打印十进制）、
`string_ascii`（拼接/长度/相等）、`array_inbounds`（字面量、写回、读、
length）、`loop_counter`（while 计数求和）、`array_oob`（越界必须每个
后端都 rc!=0）、`float_format`（**排除**，只计 excluded）。

## 语义域

- 只比较整数精确值、ASCII 字符串、数组边界、控制流；浮点单独成族并排除；
- 越界只要求"每个执行后端都失败"，不比较错误文本；
- 某族所有后端都构建失败 → 该族 unsupported（本机目前没有这种情况）。

## 正负控

- 正控：`--inject js` 把 js 的 expected 改一位，30 s：
  i32/i64/string/array_inbounds/loop_counter 五族 **每族 10–11 witness**，
  `array_oob`/`float_format` 0 witness；
- 负控：`float_format` 21 次尝试全部 **excluded**，0 witness；
- 无注入的 60 s smoke：151 cases，所有可比族 0 witness、float 21 excluded。

## 30 分钟结果（4,562 cases，3 后端）

| family | attempts | witness | excluded |
|---|---:|---:|---:|
| i32 | 651 | 0 | 0 |
| i64 | 652 | 0 | 0 |
| string_ascii | 652 | **2** | 0 |
| array_inbounds | 652 | 0 | 0 |
| loop_counter | 652 | 0 | 0 |
| array_oob | 652 | 0 | 0 |
| float_format | 651 | 0 | **651** |

- 2 个 string witness 都是**生成器的 oracle bug**，不是编译器差异：
  `a`/`b` 都是 `"t"` 时三个后端都正确打印 `true`，而 generator 把相等
  硬编码成 `"false"`。修正 expected 后 10 分钟复跑（1,516 cases）：所有
  可比族 0 witness，float 216 excluded；
- array_oob：每个后端都 rc≠0，符合"确定性 trap"（0 witness）；
- **真编译器不一致：0**；**inconclusive：2（已归类为 oracle bug，修复后消失）**；
  unsupported：0（3 后端都能构建全部族）。

## 诚实结论

- 这轮把触发面从"变异包内窄测试"扩到了六个算子族 × 3 后端、4,562 cases，
  仍然没有抓到真实跨后端不一致；
- 这不是"编译器没问题"的证明：语义域仍窄（无浮点、无 Int64 边界/溢出组合、
  无字符串非 ASCII、无数组别名/引用），且生成器的 expected 本身可能掩盖
  问题（本轮就出现过一次）；
- 下一步应扩生成器深度（随机表达式而不是常量对）与更多边界（min/max、
  除法/取模、负移位、Unicode），而不是继续跑时长。
