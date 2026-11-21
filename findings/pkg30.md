# 3 个包 × 30 分钟（T3 oracle 开）

Date: 2026-11-21. 工具链 pin 未改。

| 包 | it | T2 ok | T3 尝试 | T3 ok | T3 fail | distinct T3 | 唯一 mismatch witness | triage |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| f8（js） | 36,676 | 1,062 | 1,062 | 832 | 230 | 266 | 31 | 4 inconclusive |
| f9（native release） | 34,750 | 1,190 | 1,190 | 1,190 | 0 | 710 | 0 | 3 inconclusive |
| moonldif（wasm-gc） | 29,345 | 718 | 718 | 487 | 231 | 364 | 52 | 5 inconclusive |

## 失败定性

- f8：31 个唯一 witness，全部是 `pick` 的 `select(...)` 参数被改
  （`0`/`-1`/`'\u{10FFFF}'`/`2147483647` 等），测试断言 `None != Some(1)`；
- moonldif：52 个唯一 witness，都是字面量变异（`"complete"`→`'\u{10FFFF}'`、
  `severity: "error"` 改动、`0`→字符等），断言数字/字符串不等；
- baseline 在同一包上通过（replay 脚本先验），变异后确定性失败——**real：
  用户代码语义变化，不是 moonc 缺陷**；
- 没有 brittle（测试依赖未定义行为）样本；triage 对这些非 crash 失败
  一律 inconclusive，符合规则。

## 可重放回归

`regressions/pkg_semantic/{f8_30,ldif_30}/` 保存整包、baseline、每个 witness
的 source/断言；`scripts/replay_pkg_regressions.sh` 复跑：

```
f8_30 baseline: pass
ldif_30 baseline: pass
replayed 83 witnesses: ok
```

（另有一组早先的 10 个 f8 witness 在 `regressions/pkg_semantic/` 旧布局。）

## f9 全过

1,190/1,190 T3 通过、0 失败。**说明该包的测试覆盖太窄**（只覆盖 v128 stub
的很小一部分），不能当作"语义正确"的证明；记录而不硬找失败。

## 边界

- "real" 判定是 baseline 通过 + 变异后断言确定性失败 + 变异可见；没有对
  每个 witness 人工读测试契约，brittle 的边界仍可能有 1–2 个；
- 这些失败都不是编译器 bug，不应进 moonc regression；它们进的是
  `regressions/pkg_semantic` 的包级语义回归；
- 30 分钟单 seed；f8/moonldif 的失败率（T3 fail 230/231）不代表真实代码
  质量，只代表变异强度。
