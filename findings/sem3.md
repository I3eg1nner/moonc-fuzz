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

## 30 分钟结果

见下。
