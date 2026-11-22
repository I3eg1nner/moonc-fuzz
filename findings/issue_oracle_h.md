# issue→oracle H：must-reject 补全 + 诊断精度 + attribute 家族

Date: 2026-11-22. Pin 不变。未发上游。候选不叫 confirmed。

## H1 十类 must-reject 变换（300 例）

`regressions/must_reject_v2/positive/`：10 个 family，每族 30 个变体。

| family | 最小形态 | 期望码 | 规则依据 |
|---|---|---:|---|
| arity | `f(1)` where `f(a,b)` | 4080 | 函数应用参数个数必须匹配；E4080 |
| import | `@pkg.bar()` without import | 4037 | 未导入的包不能使用；E4037 |
| dupfield | `struct S { x; x }` | 4055 | 字段名在 struct 中唯一；E4055 |
| duptrait | 同一 `impl T for S` 两次 | 4056 | 同一 trait/type 只能有一个 impl；E4056 |
| traitbound | `g(S)` where `S` 未实现 `T` | 4018 | trait bound 必须满足；E4018 |
| breaklabel | `break missing` | 4110 | `break` 的 label 必须在作用域内；E4110 |
| letassign | `let x; x =` | 4087 | `let` 不可变，不能赋值；E4087 |
| match | enum `A;B` 只匹配 `A` | 0011 | match 必须穷尽；E0011 |
| derive | `#derive(Unknown)` | 4023 | derive 名称必须是已知 trait；E4023 |
| visibility | 跨包调用 `priv fn` | 3005 | 私有名字不可跨包访问；E3005 |

每族 30 个变体只改标识符/数值/包名，保持同类错误。`wrong_arity` 只做了
调用少参数，没做“多参数”独立 family；这是 H 的剩余缺口。

## H2 诊断精度

runner 读取每例 `expected_codes`，只取 `Error: [xxxx]` 的第一码：

| family | 用例 | expected | wrong_diagnostic | accepted |
|---|---:|---:|---:|---:|
| arity | 30 | 30 | 0 | 0 |
| import | 30 | 30 | 0 | 0 |
| dupfield | 30 | 30 | 0 | 0 |
| duptrait | 30 | 30 | 0 | 0 |
| traitbound | 30 | 30 | 0 | 0 |
| breaklabel | 30 | 30 | 0 | 0 |
| letassign | 30 | 30 | 0 | 0 |
| match | 30 | 30 | 0 | 0 |
| derive | 30 | 30 | 0 | 0 |
| visibility | 30 | 30 | 0 | 0 |
| **合计** | **300** | **300** | **0** | **0** |

负控 37：0 wrong_diagnostic；control 551：rc1。

## H3 attribute/诊断家族（100 例）

`regressions/attributes/`，5 族 ×20：

| family | 期望 | 结果 |
|---|---|---|
| `unknown_plain` | 必须 warn 0042 | 20/20 expected |
| `unknown_dotted` | 必须 warn 0042 | **20/20 missing_warning** |
| `deprecated` | 必须 warn 0020 | 20/20 expected |
| `two_unknown` | 必须 warn 0042 | 20/20 expected |
| `skip_current` | 同包不应 warn | 20/20 expected |

`missing_warning=20` 全是 836 的 dotted unknown attribute 形态，已与 curated 的
836 去重；没有新的 accepted 候选。`attribute_sensitivity` 门禁只断言 100 个
用例存在，不把已知 836 漏报当新发现。

## H4 包形态 seed

`regressions/package_seeds/`：

- `single/`：单包 `moon info` rc0（mbti）；
- `double/`：双包 import；`moon check` rc1，缺 trait import 被拒；
- `blackbox/`：包自身 blackbox test；`moon test` rc0，stderr 仍出现
  `Warning (deprecated)`（1294 形态）。

3 个 seed 覆盖单包、双包依赖、blackbox test；没有把它们并进单文件
must-reject 的计数。

## Gate

`must_reject_sensitivity`：

```
positives=300 transforms=10 accepted=0 wrong_diagnostic=0 negative_bad=0 control_rc=1
```

`attribute_sensitivity`：

```
cases=100 missing_warning=20 rc=0
```

accept 29/29；`moon_test` 385/385。

## 结论

- 10 类 ×30 =300 全部 expected，0 accepted，0 wrong_diagnostic；
- 100 attribute 用例，80 expected、20 missing（全是已知 836）；
- 无新候选；饱和范围是这 10 类变换 + 5 族 attribute；
- 未覆盖：arity 多参数单独 family、package/多文件 must-reject 变换、更多
  attribute 组合（cfg/alias/重复嵌套）；不能写成“编译器没有误接受”。

报告 `findings/issue_oracle_h.md`；脚本 `scripts/must_reject.sh`、
`scripts/attribute_check.sh`；数据 `regressions/must_reject_v2/`、
`regressions/attributes/`、`regressions/package_seeds/`。
