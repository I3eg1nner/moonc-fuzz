# Discovery P：INT_MIN 定案与 token 合并族

Date: 2026-11-24. Pin 不变。

## P1 INT_MIN

`println(--2147483648)` 与 `println(- -2147483648)` 原始 check 均 rc1 [4095]；
`-(-2147483648)` 原始 rc0/run rc0，fmt 后 rc1 [4095]。因此不是单纯字面量越界，
而是 formatter 把括号删成 `--`。

变体表见 `candidate_f13.md`：

- `-(-(2147483647+1))` 原始/fmt 均 rc0；
- `-(-0x80000000)` 原始/fmt 均 rc0；
- `-(-9223372036854775808)` 原始 rc1；
- 变量 `let x = -2147483648; println(-x)` 原始/fmt 均 rc0；
- `-(-1)` 原始/fmt 均 rc0，`--1` 语义等价。

判定：**REAL**，范围收窄为“十进制 INT_MIN 嵌套一元负号”；标题已按实际范围改。

## P2 token 合并 200

`scripts/gen_tokmerge.sh`：`a - -b`、`a + +b`、`! !b`、`a - (-b)`、
`x = - -y` 五类 ×40；每类原始 check/run 前置。

```json
{"generated":200,"source_bad":0,"fmt_bad":0,
 "check_bad":0,"token_bad":0,"idem_bad":0,
 "stdout_bad":0,"violations":0}
```

200/200 原合法；fmt 后可解析、token 一致、idempotent、stdout 一致；无违例。

## P3/P4

- 新候选仅 F13/INT_MIN（同一条，范围收窄）；
- token 合并族 0 违例，无第二根因；
- 下一步：扩大十进制边界/字面量后缀族，或停 formatter 面。
