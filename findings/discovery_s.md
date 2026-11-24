# Discovery S：R-idem 严重度与构造族 300

Date: 2026-11-24. Pin 不变。

## S1 R-idem

`// head\nfn main { println(1) }`：

| 阶段 | lines | bytes |
|---|---:|---:|
| fmt1 | 5 | 38 |
| fmt2 | 6 | 39 |
| fmt3 | 6 | 39 |
| fmt4 | 6 | 39 |
| fmt5 | 6 | 39 |

- 只在第二次加一个空行，之后稳定；不是无界增长；
- 3/3 复现；严重度：低，幂等性违例但纯空白、稳定；
- 变体：普通 `//` 触发；`///` 文档注释、空行、属性不触发；`/** */`
  块注释在 pin 上语法不支持；
- curated 197 是 indented comment 被移入错误 impl body，症状不同，不是同一条。

## S2 构造族 300

struct/enum/可见性/属性/泛型/or-pattern/trait impl/长行/控制流/类型注解/闭包：

```json
{"generated":300,"source_bad":90,"valid":210,
 "fmt_bad":0,"check_bad":0,"token_bad":30,
 "idem_bad":0,"stdout_bad":0,"violations":30}
```

- 90 个生成程序本身不合法，单列，不计；
- 210 合法：fmt 全部可解析、idem 0、stdout 0；
- 30 token 差异为构造器/数组/可选分号等 formatter 规范化，未导致语义差异；
- 无新候选。

## S3/S4

新候选 0；已有 F13、R-idem 各自独立根因。下一步：对 30 token 差异做
syntax-aware 白名单，或停 formatter 面。
