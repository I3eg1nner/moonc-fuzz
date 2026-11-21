# INT_MIN / -1：允许的实现差异（allowed_impl_divergence）

Date: 2026-11-21. 工具链 pin 未改。

## 最小复现

```moonbit
fn main {
  println((-9223372036854775808L / -1L).to_string())
}
```

（Int32 版本：`(-2147483648 / -1)`；mod 版本把 `/` 换成 `%`。）

## 三后端 ×10（确定性）

| case | js | wasm-gc | native |
|---|---|---|---|
| Int32 `min / -1` | 10/10 rc=0，输出 `-2147483648` | 10/10 rc=1（trap） | 10/10 rc=136（trap） |
| Int64 `min / -1` | 10/10 rc=0，`-9223372036854775808` | 10/10 rc=1 | 10/10 rc=136 |
| Int32 `min % -1` | 10/10 rc=0，`0` | 10/10 rc=0，`0` | 10/10 rc=136（trap） |
| Int64 `min % -1` | 10/10 rc=0，`0` | 10/10 rc=0，`0` | 10/10 rc=136 |
| `0 / -1`（Int/Int64） | 10/10 rc=0，`0` | 10/10 rc=0，`0` | 10/10 rc=0，`0` |

结论：不是随机抖动；**只有 min/-1（`/` 与 `%`）分歧**，0/-1 一致。

## 规范依据

`moonbitlang/core` 的 int 文档（固定宽度整数）：

> For every fixed-width integer type (Int32, Int64, UInt32, UInt64, and
> Int16, UInt16 and Byte, which divide through Int32), a zero divisor is a
> program error, and so is dividing the minimum Int32 or Int64 by -1 with
> either operator. These cases have no portable result. Depending on the
> backend and build mode, the program may abort or get an arbitrary value,
> so don't rely on any particular outcome.

链接：
- https://github.com/moonbitlang/core/blob/3b911e46b84aaa0608e244938d50b37560fcbd9e/int/README.mbt.md
- 同页渲染：https://mooncakes.io/docs/moonbitlang/core（int 包 README）

因此规范明确：**min/-1 与零除数没有可移植结果，允许 abort 或任意值**。

## 分类

**allowed_impl_divergence**，不是 `compiler_inconsistency_candidate`：

- js 返回 wrap 值、wasm-gc/native trap，都在规范允许的范围内；
- 不满足"规范要求一致但实现不一致"的第一档，因此**不进入编译器缺陷回归**；
- 资产保留在 `regressions/sem3_div_overflow/`，仅作实现差异的 replay 记录；
- 同样规则适用于零除数：sem3 不生成除零 case；边界族里的 min/-1 已标为
  `excluded_domain`，不再计 witness。

## 可 replay 资产

`regressions/sem3_div_overflow/{391a085da3,b7ef254ec1}/` 保存 source/expected/
actual/argv；`scripts/replay_sem3.sh` 可在三后端重放。
