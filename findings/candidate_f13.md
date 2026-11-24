# Candidate F13：降级（-(-1) 不成立；INT_MIN 为未定案衍生样本）

Date: 2026-11-24. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. **未提交上游**。

## 主 repro：`-(-1)` 不成立

```moonbit
fn main { println(-(-1)) }
```

- 原始 `moon check` rc0；
- `moonfmt` rc0，输出 `println(--1)`；
- 格式化后 `moon check` **rc0**；
- 原始/格式化 `moon run` stdout 都是 `1`。

`--1` 被解析为两次取负，语义等价。因此按 `-(-1)` 的 F13 候选**降级/REFUTED**，
不再作为 formatter 缺陷候选。

## 衍生样本：INT_MIN

```moonbit
fn main { println(-(-2147483648)) }
```

- 原始 `moon check` rc0、`moon run` rc0、输出 `-2147483648`；
- `moonfmt` rc0，输出 `println(--2147483648)`；
- 格式化后 `moon check` rc1，`Error: [4095]`；
- 3/3 复现。

这是合法输入→格式化后不可解析，但与 `-(-1)` 的“合法等价”不同；目前只记为
**未定案衍生样本**，不写 candidate，除非单独确认其根因和上游/curated 状态。

## 查重

- `issues/curated.json` 无 unary minus formatter 条目；
- GitHub 只读 query `repo:moonbitlang/moon formatter unary` /
  `repo:moonbitlang/moonbit-docs formatter unary` 只命中 1369 unary plus；
- 未提交上游。
