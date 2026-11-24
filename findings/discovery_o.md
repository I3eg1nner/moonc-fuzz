# Discovery O：F13 降级、fmt 非零结论、优先级 400

Date: 2026-11-24. Pin 不变。

## O1 F13 主 repro 改用 `-(-1)`

```moonbit
fn main { println(-(-1)) }
```

- 原始 `moon check` rc0；
- `moonfmt` rc0，输出 `println(--1)`；
- 格式化后 `moon check` **rc0**；
- 原始/格式化 `moon run` stdout 都是 `1`。

`--1` 是两次取负，语义等价。因此 F13 按 `-(-1)` **降级/REFUTED**，不再作为
formatter 候选。

INT_MIN 版本：

```moonbit
fn main { println(-(-2147483648)) }
```

- 原始 `moon check` rc0、`moon run` rc0、输出 `-2147483648`；
- 格式化后 `moon check` rc1 `[4095]`，3/3；
- 只记为**未定案衍生样本**，不写 candidate；与 `-(-1)` 的合法等价不同。

## O2 两个 fmt 非零

`poc/f3_parser_oom/wild.mbt`、`poc/f3_parser_oom/cmd/main.mbt`：
原始 `moon check` timeout 124（parser OOM），输入本身不可判定/不可编译；
排除，不是 formatter 在合法输入上崩。

## O3 优先级/括号 400

`scripts/gen_precedence.sh`，固定 10 种表达式 × 40：

```json
{"generated":400,"source_bad":0,"fmt_bad":0,
 "check_bad":0,"token_bad":0,"idem_bad":0,"stdout_bad":0,
 "violations":[]}
```

- 400/400 原始合法；
- fmt 后可解析、token 一致、idempotent、stdout 一致；
- 无新根因。

## O4 结论

- F13 主 repro 降级；INT_MIN 只是未定案衍生样本；
- 2 个 fmt 非零均来自 parser OOM 输入，排除；
- 优先级 400 无违例；
- 新 candidate 0，第二根因 0；下一步可扩大优先级族或换 formatter 子面。
