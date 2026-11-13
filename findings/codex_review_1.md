# 外部 review #1（codex-cli 0.166.0，经 127.0.0.1:7890 代理）

日期 2026-11-11。调用方式（以后同类情况照这个来）：

```bash
cat prompt.txt | HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 \
  codex exec -s read-only -C /data/audit/mbtfuzz --skip-git-repo-check -
```

喂给它的上下文：入口并集 26.67%、语料饱和（贪心 232）、变异净增 0、诊断类 29 个
（12 语法/3 改名/9 类型）、四 target 极差 0.9%、差分 trap ≈2/万、REAL_DIFF 0。

## 它的结论

1. 优化等级矩阵（最便宜的覆盖假设）；
2. 更丰富的可观测计算 + 独立 oracle（针对误编译）；
3. 手工类型实例化矩阵（20–50 个），验证后再上 `.mbti` 生成器。

外加五条方法论问题。

## 我验证的部分

### 两条代码指控，都成立，已修

| 它的指控 | 实际代码 | 后果 | 修复 |
|---|---|---|---|
| 归一化把 `A` 和 `a` 当成一样 | `normalize()` 对整个输出 `.lower()` | 只有大小写差异的真实差异被判 FORMAT_DIFF | 不再整体小写，nan 按 token 归一 |
| 2^53 以上整数塌成一个值 | 所有数字过 `float()` | `9007199254740992` vs `…93` 判成相同 | 整数走 `int`，精确保留 |

回归用例：`harness/test_oracle.py`，9/9 通过（含空格差异**不**归一的反例）。
分类器也改了：wasm/js 失败、wasm-gc 成功不再降级成 `WASM_RUN`，改为逐对
`SAME/FORMAT/REAL/TRAP/BUILD_DIFF:<pair>`。

### 它的 #1（优化等级）实测通过

用 `moon build --release --dry-run -v` 取 130 条命令、重放：

| 配置 | `Moonc.*` | 对并集新增 |
|---|---:|---:|
| debug `-g -O0`（原口径） | 5,476 | — |
| **release（无 -O0/-g）** | **5,787** | **+302** |
| release 的 test build（429 条） | 6,231 | +315（对 debug 四入口） |

release 与 debug 几乎互为超集（`release − debug = 315`，`debug − release = 4`），
说明差异不是随机噪声，是**优化路径本身**。成本：约 20 分钟（dry-run + 重放）。

## 没做的（按它的排序，留作下一步）

* #2 独立 oracle 的语义族（可变别名闭包、跨调用异常、位运算宽度）——2–4 天；
* #3 手写类型实例化矩阵——1–2 天；
* 方法论剩余项：`replay.py` 记录返回码/超时、`nochain` 的完整 trace、
  去重键拆成 `(kind, 归一化输出, 触发阶段)`。

## 我对它的保留意见

它把"优化等级"排在第一位是对的，但它假设存在多档优化；实际 moonc 只有
`-O0` 开关（外加 LLVM 后端的 `-llvm-opt`），所以"矩阵"只有 debug/release 一维。
真正的多档在 `link-core` 的 dedup/优化上，这条还没测。
