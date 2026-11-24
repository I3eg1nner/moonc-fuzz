# Candidate F13：formatter 删除 INT_MIN 字面量合法必需的括号

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

## 三对照

| 输入 | check rc | 完整错误 |
|---|---|---|
| `-(-2147483648)` | 0 | — |
| `- -2147483648` | 1 | `Error: [4095] Integer literal 2147483648 is out of range.` |
| `--2147483648` | 1 | `Error: [4095] Integer literal 2147483648 is out of range.` |

结论：括号是让 `2147483648` 在 Int32 范围内合法的必需结构；formatter 去掉括号后
输出 `--2147483648`，不可编译。**不是 token 合并**：`--1` 合法且语义等价，
`- -2147483648` 在原始输入就已经 4095。

## 触发边界

| 输入 | 原始 check | 原始 run | fmt 后 check |
|---|---|---|---|
| `-(-2147483648)` | 0 | 0 | **1 [4095]** |
| `-(-(2147483647+1))` | 0 | 0 | 0 |
| `-(-0x80000000)` | 0 | 0 | 0 |
| `-(-9223372036854775808)` | 1 | 1 | 1 |
| `let x = -2147483648; println(-x)` | 0 | 0 | 0 |
| `-(-1)` | 0 | 0 | 0 |

范围：**十进制字面量 `2147483648` 在嵌套一元负号内**；表达式、十六进制、
变量版本不触发。

## 上下文扩展

| 上下文 | 原始 check/run | fmt 后 check |
|---|---|---|
| 函数参数 `f(-(-214...))` | 0/0 | 1 [4095] |
| 结构体字段 `{v: -(-214...)}` | 0/0 | 1 [4095] |
| 函数返回值 | 0/0 | 1 [4095] |
| 闭包体 | 0/0 | 1 [4095] |
| const 初始化 | 0/0 | 1 [4095] |
| 数组下标局部变量 | 0/0 | 1 [4095] |
| match pattern `-2147483648` | 0/0 | 0 |

仍算同一条，不另立候选。

## 观察（不作为缺陷）

对**不合法**输入 `fn main { println(- -2147483648) }`，`moonfmt` 输出
`println(2147483648)`，把两个负号都丢掉；reparse 仍 4095。这是 invalid-input
的 formatter 行为，不列候选。

## 查重

- `issues/curated.json` 无对应条目；
- GitHub 只读 query `repo:moonbitlang/moon formatter unary` /
  `repo:moonbitlang/moonbit-docs formatter unary` 只命中 1369 unary plus；
- 与 1369 同 formatter 子系统，不同症状；本条是删除 INT_MIN 必需括号，
  独立条目。
- 未提交上游。
