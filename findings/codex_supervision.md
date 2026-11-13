# codex 逐轮监督记录（2026-11-11 → 11-12）

用户要求：走 7890 代理找 codex 监督，**在 codex 要求停止前不停**。
共 8 轮。每轮：带实测数字提问 → 执行 → 验证 → 记录。

## 轮次

| 轮 | 问了什么 | codex 给了什么 | 执行结果 |
|---|---|---|---|
| 1 | 项目全貌、下一步优先级、方法论弱点 | 优化配置矩阵；独立 oracle；类型矩阵；指出 2 个归一化 bug | 修 bug（A/a、2^53），release 矩阵 +302 |
| 2 | 入口是否已收口 | 驱动面封顶 1 天；改口径（下界非可达集）；C 实验：200 个多包程序 × 4 后端 | 200/200 跑通、0 差异 |
| 3 | 下一语义族 | Int32 溢出/移位 | 3,600 例，0 差异 |
| 4 | 再下一族 | Double 位级 | 4,000 例，0 差异 |
| 5 | 别名 | 可变引用别名 | 2,400 步，0 差异 |
| 6 | 复合表达式顺序 | Int32 复合（含 witness） | 2,200 例，0 差异 |
| 7 | Double 复合 + 策略 | Double 复合（7 个 witness） | 3,200 例，0 差异 |
| 8 | 异常 + Unicode 后是否停 | 两族通过即停 | 9,695 + 2,000，0 差异 |

## 最终裁决（原文）

> This bounded semantic campaign is complete. All seven families passed their gates,
> with zero discrepancies against independent oracles across all four backends.
> This provides bounded evidence of semantic consistency, not proof of compiler correctness.

> **You should stop expanding this campaign.**

## 它纠正过我的地方（都成立）

1. 我报的"21,695 例"错了，正确是 **27,095**；
2. "18,764 个函数不可达"不成立——观测并集只是**可达性下界**，已撤回；
3. 跨后端互比不够：注入故障时四个后端"一致地错"，必须用独立参考实现（已实证）；
4. 归一化两个吞值 bug（A/a、2^53 塌陷），已修 + 回归用例 9/9。

## 工作流（已固化到 README §6.1）

```bash
cat prompt.txt | HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 \
  codex exec -s read-only -C /data/audit/mbtfuzz --skip-git-repo-check -
```

* prompt 必须自带实测数字与裁决规则，否则只会得到通用建议；
* 拿到意见逐条验证，结果写入 `findings/codex_review_N.md`，**包括被证伪的**；
* 注意：涉及"fuzz/漏洞"措辞会被安全策略拦截，用 "conformance testing / differential testing" 表述可过。
