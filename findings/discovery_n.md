# Discovery N：F13 正式候选与同族边界

Date: 2026-11-24. Pin 不变。

## N1 F13

`findings/candidate_f13.md`：1 行 repro，3/3 `moonfmt rc0` + `moon check
Error [4095]`；curated 无，GitHub 只读 query 只命中 1369 unary plus；F13 是
unary minus 删括号成 `--`，独立条目。未提交上游。

## N2 token 白名单

`scripts/format_token_check.sh`：

```json
{"whitelist_diff":0,"deleted_token_diff":1}
```

白名单包括 `derive(...)` 重定位/`#derive`、`Int`→`Int32`、enum 分号省略；
白名单文件不报红，删 token 报红。10 文件里原 6 条 token 变化均归为这些
formatter 已知规范化；F13 的 `--` 不在白名单。

## N3 同族 300

`scripts/gen_unary.sh`，300 程序（一元 `-`/`!`/`~` × 括号/边界/二元/调用/字段）：

```json
{"generated":300,"source_bad":75,"fmt_rc_bad":0,
 "check_bad":100,"token_bad":100,"stdout_bad":25,"violations":100}
```

- 75 个 `~` 程序原源码就 3001 invalid，不计候选；
- 合法 225 中 100 违例，全部是 F13 同族：
  `-(-1)`、`-(-2147483648)`、`-(-(-1))`、`!(-(-1)==1)`；
- 无第二个根因；`-(fn()...)` 等未违例。

## N4 包扫描

`scripts/format_pkg_scan.sh` 400 files（并行、per-file timeout）：

```json
{"files_attempted":400,"fmt_rc_nonzero":2,
 "idempotence_violations":0,
 "token_violations":11,
 "test_regressions":0}
```

- 11 token 变化样本为 formatter 已知规范化（enum 分号、derive/Int32、
  1369 prefix-plus 样例）；不是新根因；
- 2 个 fmt 非零需人工看，未计候选；
- test 回归未跑（0）。

## N5 结论

F13 是唯一新候选；同族 100 违例均同根因；400 文件无第二根因。
下一步：把 token 白名单收紧到 syntax-aware，再跑包级 check/test。
