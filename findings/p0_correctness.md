# P0-1：堵住假通过，统一候选可信度

Date: 2026-11-20. 依据：`findings/codex_review_6.md`（独立评审 P0-1）与
`/tmp/opencode/codex_gap_review.md` §3.2/§5。工具链 pin 未改。

## 问题

`semdiff` 用一次 `moon run` 同时做构建与执行，只把"stderr 里没有 build 失败
片段"当作 `built`，`Obs` 里没有 `timed_out`，`compare` 只比较幸存目标的
rc/stdout。于是：

- 两个目标**都超时**（rc=-999、stdout=""）→ 两个空输出相等 → `ALL_EQUAL`；
- 两个目标**同 signal / 同 ICE** → 同样相等；
- 三个目标里一个 build 失败 → 被丢弃，剩下两个相等仍是 `ALL_EQUAL`；
- 全部 case 都 SKIP（`--only` 不匹配、写目录失败）→ `mismatch==0` → 退出 0。

`minimize` 的最终复验失败时只把 workdir 恢复成 original，`--out` 仍写
`reduced`：不看返回码的调用者会拿到不复现的 witness。

`@judge` 有七类 oracle 和注入矩阵，但主 `cmd/fuzz` 仍只调 `@exec.classify`，
保存的 finding 也没有"未确认"这一状态。

## 改动

### 1. 每个目标五态，只有全完成才谈一致

`cmd/semdiff/main.mbt`：

- `Obs.built : Bool` 换成 `status`，取值为
  `COMPLETE | BUILD_FAIL | LINK_FAIL | TIMEOUT | RUN_FAIL`；
- 先 `moon build --target T` 再 `moon run`：构建与执行分开，`timed_out` 不再
  被 `moon run` 的混合输出吞掉；
- `LINK_FAIL` 只认链接期诊断（`failed to link`、`link-core`、
  `Machine_error`、`undefined symbol`、`ld: `），其余编译错误是 `BUILD_FAIL`；
- `compare` 的规则：**每个请求目标都是 COMPLETE** 才进入输出比较；任一目标
  非 COMPLETE → `INCONCLUSIVE`；没有目标 → `NO_CASES`；
- 退出码只在 `cases > 0 && all_equal == cases && mismatch == 0 &&
  inconclusive == 0 && skipped == 0` 时为 0；
- 每个 target 行新增 `status`，summary 新增 `inconclusive`，`ok` 现在表示
  "被证明"，不再表示"没有 mismatch"。

### 2. 反例表进 wbtest 与 accept

`cmd/semdiff/semdiff_wbtest.mbt` 覆盖：两个 TIMEOUT、两个同 signal、两个同
BUILD_FAIL、两个同 LINK_FAIL、缺一个目标、两个相等、三个相等、不同输出、
零 case，以及 `link_failure` 的链接/编译分流。

`semdiff --self-test` 用同一张表跑真实二进制（不需要编译器），accept 新增
门禁 `semdiff_selfcheck` 调用它；`semantic_diff` 门禁现在要求
`ok:true`、`inconclusive:0`、`skipped:0`，而不只是 `mismatch:0`。

### 3. judge 接入主 campaign，candidate 不是 confirmed

`cmd/fuzz`：

- `judged_kind(stage, r)` 走 `@judge.check_all`，缺陷类以 judge 的 `class`
  为准，`OK/ERR/HANG` 仍回落到 `@exec.classify`，阶段逻辑不变；
- T1、T2、`save_crash` 三处分类改用它；
- 保存的 finding 元数据带 `"status":"candidate"`；
- summary 用 `candidate_witnesses` / `confirmed_witnesses:0` 取代原来含糊的
  `unique_witnesses`（旧字段保留，避免破坏既有报告）。

`confirmed` 只能由 `cmd/verify` 在新鲜副本上复验后产生，campaign 没有写权限。

### 4. minimize 只发布复验通过的归约

- 新增 `publish_path(out, verified)`：未复验返回空串；
- 未复验时 `--out` 不写，改写到 `<out>.rejected` 供检查；
- JSON 新增 `published`，`verified` 保留。

## 验证

```text
moon test --target native              346 / 346 pass
semdiff --self-test                    {"ok":true,"checks":9}
semdiff --targets wasm-gc,native       cases=27 all_equal=27 inconclusive=0 skipped=0, rc=0 (20.7s)
semdiff --timeout-ms 1 --only f64-nan-bits
                                       verdict=INCONCLUSIVE, rc=1（修复前会是 ALL_EQUAL, rc=0）
semdiff --only nonexistent             cases=0, ok=false, rc=1（修复前 rc=0）
minimize ... --out /tmp/red_check.mbt   verified=true published=true, 文件 170 B
accept                                见提交前的 19/19 输出
```

## 代价与边界

- `semdiff` 每个 target 多一次 `moon build`（27 case × 2 target：16.1s → 20.7s）。
  这是把"构建成功"从猜测变成观测的代价，接受。
- `INCONCLUSIVE` 与 `MISMATCH` 是两类失败：前者说明实验没做成，后者说明
  后端不一致。两者都非零退出，但报告里分开计数。
- `judge` 接入只改了分类与保存标签，候选的自动复验/归约流水线仍未接线
  （P1-3），`confirmed_witnesses` 目前恒为 0 是诚实值而不是遗漏。
- `--only` 不匹配现在是非零退出；依赖旧行为的脚本需要显式检查 case 数。
