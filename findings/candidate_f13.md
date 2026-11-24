# Candidate F13：十进制 INT_MIN 嵌套一元负号被格式化为 `--`

Date: 2026-11-24. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. **未提交上游**；只读查重。

## 最小 repro

```moonbit
fn main { println(-(-2147483648)) }
```

原始 `moon check` rc0、`moon run` rc0、stdout `-2147483648`；`moonfmt` rc0，
格式化后：

```moonbit
///|
fn main {
  println(--2147483648)
}
```

`moon check` rc1，`Error: [4095]`；3/3 复现。

## 触发边界

| 输入 | 原始 check | 原始 run | fmt 后 check |
|---|---|---|---|
| `-(-2147483648)` | 0 | 0 | **1 [4095]** |
| `-(-(2147483647+1))` | 0 | 0 | 0 |
| `-(-0x80000000)` | 0 | 0 | 0 |
| `-(-9223372036854775808)` | 1 | 1 | 1 |
| `let x = -2147483648; println(-x)` | 0 | 0 | 0 |
| `-(-1)` | 0 | 0 | 0（`--1` 合法等价） |

范围：**十进制字面量 `2147483648` 在嵌套一元负号内**；表达式、十六进制、
变量版本不触发。不是普遍的“删一元括号”。

## 查重

- `issues/curated.json` 无对应条目；
- GitHub 只读 query `repo:moonbitlang/moon formatter unary` /
  `repo:moonbitlang/moonbit-docs formatter unary` 只命中 1369 unary plus；
- 与 1369 同 formatter 子系统，不同症状；本条是十进制 INT_MIN 的 `--` 合并，
  独立条目。
- 未提交上游。
