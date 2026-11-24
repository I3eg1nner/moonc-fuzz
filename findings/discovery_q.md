# Discovery Q：F13 上下文、字面量族、注释族

Date: 2026-11-24. Pin 不变。

## Q1 F13 上下文

同一条 `-(-2147483648)` 放入 7 个上下文：

- 触发（原始 check/run 0/0，fmt check 1 [4095]）：函数参数、结构体字段、返回值、
  闭包体、const 初始化、数组下标局部变量；
- 不触发：match pattern `-2147483648`（fmt check 0）。

仍是同一条 F13，trigger 表已扩充到 `candidate_f13.md`，不另立候选。

## Q2 字面量族 300

Int/Int64/UInt/Byte/Float 边界、十进制/十六进制/二进制/下划线、负零等：

```json
{"generated":300,"source_bad":0,"fmt_bad":0,
 "check_bad":30,"token_bad":60,"idem_bad":30,
 "stdout_bad":0,"violations":60}
```

- 30 check_bad 全部是 F13 case `-(-2147483648)`；
- token/idem 同族；
- 无第二根因。

## Q3 注释/转义 200

注释在运算符/参数/match arm/文件尾、`//` 行注释、字符串转义：

```json
{"generated":200,"source_bad":0,"fmt_bad":0,
 "check_bad":0,"token_bad":60,"idem_bad":20,
 "stdout_bad":0,"violations":80}
```

- fmt 后全部可解析、stdout 一致；
- token/idem 变化来自 formatter 自动 `///|`/空行/参数尾逗号等已知规范化，
  不是语义缺陷；
- `/* */` 块注释在 pin 上语法不支持（3002），未纳入。

## Q4 结论

- F13 仍是唯一候选，上下文边界清楚；
- 字面量族无第二根因；
- 注释族无 check/stdout 失败，token/idem 属已知 formatter 规范化；
- 下一步：把注释白名单做成 syntax-aware，或停 formatter 面。
