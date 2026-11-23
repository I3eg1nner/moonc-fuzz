# 移交给下一任维护者（一页式）

最后更新：2026-11-22。工具链 pin：`moon 0.1.20261104 (940aa18)` /
`moonc v0.10.20+65efd5b93`。**禁止改 pin、禁止向 moonbit 上游发 issue/评论**。

## 1. 当前定位

- **综合 6.8 / 10**：五轮独立复核对“证据质量 + 工程实现”的评分；
- **成熟度 6.0 / 10**：距离成熟差分 fuzzer 的差距——覆盖域、oracle 独立性、
  自动化闭环、资源/回归资产。
- 两者都不是“缺陷发现数”评分。当前**没有已确认的编译器不一致**；最接近的
  `min/-1` 经规范核对是 `allowed_impl_divergence`。

## 2. 已验证能力（证据路径）

| 能力 | findings | 原始证据/资产 | 门禁 |
|---|---|---|---|
| 工具链 pin 与归档 | `toolchain_archive.md` | `scripts/archive_toolchain.sh`, release asset | `toolchain_pinned` |
| 13 个回归 case（F1–F6 家族 12 个 + P1；F7–F12 另有专项门禁） | `p0_evidence.md`, `f8f9_trigger_surface.md`, `defect_inventory.md` | `poc/`, `cmd/regress` | `regressions_13`, `f7_boundary`, `reduce_witness`, `lsp_regress_6` |
| 38 条 issue 派生 oracle（A–I） | `issue_oracle_a_b.md`, `issue_oracle_c.md`, `issue_oracle_d.md`, `issue_oracle_e.md`, `issue_oracle_f.md`, `issue_oracle_g.md`, `issue_oracle_h.md`, `issue_oracle_final.md`, `j1_state_recovery.md`, `j2_original_config.md`, `j3_aggregate_cancel.md` | `issues/raw/`, `oracle_cases/`, `scripts/issuecheck.sh` | `issue_regress`, `formatter_sensitivity`, `package_sensitivity`, `must_reject_sensitivity`, `attribute_sensitivity`, `state_recovery`, `original_config_replay`, `original_config_e2e`, `aggregate_cancel`, `sem3_observation`, `fmt_f13` |
| semdiff 五态 + 截断/摘要 | `p0_correctness.md` | `cmd/semdiff`, `/tmp/sem_*.jsonl` | `semantic_diff`, `semdiff_selfcheck` |
| triage 规则 + 单实现 | `triage_pipeline.md` | `scripts/triage_selftest.sh`, `triage_campaign_selftest.sh` | `triage_controls`, `triage_campaign` |
| formatter 聚类 | `fmt_cluster.md` | `cmd/clusterprobe`, `/tmp/fmt_gate3` | `fmt_cluster` |
| stub 未知 witness 晋级（t1） | `stub_control.md` | `scripts/stub_ice_triage.sh`, `/tmp/stub_final2` | `stub_ice_triage` |
| 包模式（整包/单文件变异/原 argv） | `pkg_mode.md`, `pkg_t3.md` | `/tmp/pkg30`, `cmd/capsule` | （无门禁） |
| 包语义回归（83 witness） | `pkg_semantic.md` | `regressions/pkg_semantic`, `scripts/replay_pkg_regressions.sh` | （无门禁） |
| 三后端语义差分（node 独立参考） | `sem3_node.md`, `sem3_typed.md`, `sem3_final.md` | `/tmp/semnode30`, `/tmp/semtyped30`, `cmd/sem3` | （无门禁） |
| 浮点位型 / async 确定性 | `float_async.md` | `/tmp/semfloat30`, `/tmp/asem30`, `cmd/asem` | （无门禁） |
| backpressure + drain | `backpressure.md`, `cost_curve.md` | `/tmp/bp5`, `/tmp/bp6`, `/tmp/bp_dead2` | （无门禁） |
| edge 身份/碰撞/饱和 | `edge_identity.md`, `edge_saturation.md` | `/tmp/edge_exp*` | （无门禁） |

## 3. 未证明 / 负结果（不要当成功）

- **edge 奖励无稳定收益**：30 min ×3 seeds，`adds/CPU-s` 1.938 vs 1.950、
  t90 421 vs 488 s，差异在 seed 方差内（`feedback_ab2.md`）。
- **83 个包 witness 全是用户代码语义变化**，不是 moonc 缺陷
  （`pkg_semantic.md`, `pkg30.md`）。
- **sem3 全域 0 witness**：域内（整数/字符串/数组/控制流/struct/enum/泛型/
  闭包/typed 组合、Double 位型、async 固定顺序）三后端与 node 一致；
  但域边界：30 分钟浮点批只覆盖 Double/非 NaN；2026-11-22 的
  `float32_nan_pilot.md` 已覆盖 Float32 位型/qNaN/±0/±inf/subnormal
  （0 candidate；JS sNaN quieting 是 allowed host divergence），但尚未接入
  常规 campaign；async 只比确定性顺序；trait/可变别名/指针未覆盖。
- `min/-1`、除零是 **allowed_impl_divergence**（core int 文档 "no portable
  result"），非缺陷（`int_min_divergence.md`）。

## 4. 已作废结论（每条都有“为什么”）

| 作废结论 | 为什么 |
|---|---|
| “1,960 是可达函数天花板” | 旧跑法 worker 结束即关队列，只完成 ~57 条 trace；drain+预算修正后 adds 2,851–2,985、edges 32.6k（`edge_plateau.md` 顶部横幅） |
| “75% 可达函数是真实上限” | 同上，是 trace 完成数假象 |
| “edge 奖励无收益/edge 已死” | 当时 9/9 `edge_saturated=true`、cap=50000，测到的是容量截断（`edge_saturation.md`） |
| “sem3 0 witness = 完备通过” | 旧 sem3 静默跳过失败后端；观测修正后曾出现 26/25/34 inconclusive 与 18 oracle（`sem3_node.md`） |
| “TEST_FAIL 按 build 命令重放” | 旧 `capsule.json` 存 pkg_argv；现改成存 `cmd/build_cmd/run_cmd`（`review5_fixes.md`） |
| “24 秒饱和” | 实际第 7 个采样点（约 12–14 s，旧 stats 无 elapsed_ms）已饱和（`edge_saturation.md`） |
| “可执行 trace 100% 能抬平台” | 100% 采样把 trace 完成数打到 63/49，平台反降（`trace100.md`） |

## 5. 剩余缺口（P0/P1 + 验收标准）

**P0**
1. **corpus owner 事务/checkpoint 恢复**：跨 epoch 只恢复 by_key/边，父本
   owner 与 checkpoint 未版本化。验收：epoch2 的 `coverage_adds` ≤ epoch1 的
   10% 且只能来自真正新输入；state 有 schema/checksum/原子替换；owner 计数
   可重放。
2. **原配置 replay（包模式）**：TEST_FAIL 已存 run_cmd，但 triage 仍只按
   签名判，未断言“replay 输出/断言与保存一致”。验收：保存的 test case
   3/3 重放失败且断言文本匹配；门禁覆盖。
3. **cgroup 取消与聚合资源**：`scripts/cgroup_run.sh` 有 SIGTERM/kill，但
   本机 cgroup 只读，未实测；聚合上限仍只是逐进程 prlimit。验收：在可写
   cgroup 主机跑 1 h，记录 memory.peak/pids/disk，kill 后无孤儿进程。

**P0 状态（2026-11-23）**
- corpus owner 事务/checkpoint：J1 已实现 header schema/checksum/sync/rename/quarantine/周期 checkpoint；`state_recovery` gate 通过（epoch1 200/536、epoch2 796/536；最新 197/803）。P0-2 已补 `--recover`、schema/checksum/hash 五种 injection、以及 mid_payload/after_tmp/after_rename 三个 kill 点；仅保留 per-fd fsync 的边界。
- original-config replay：J2/P0-1 修复后 `original/source=mutant`、`pkg=wd`、嵌套 moon.pkg、argv/expected 结构化；fixture 和真实 package e2e 均 3/3，baseline 负控 mismatch。P0-1 已闭环。
- 聚合资源/取消：J3 安全子集 supervisor 实现 exit rc、deadline、max-procs、agg RSS；`aggregate_cancel` 仍绿但明确 **setsid 逃逸不支持**，没有 `process_tree` gate；组 kill/孤儿仅直接 pgid。cgroup2 只读，未跑 peak。
- P0-5 sem3：`observations_complete` 要求 3 后端且只能 ok/trap；timeout/compile_error/truncated/ice/runtime_error → inconclusive；单元测试 2/2。真实 backend wrapper/五矩阵已做：A 2ok+timeout、B ok+trap+compile → inconclusive；C 3trap → witness；D 3ok 同输出 → equal；E 3ok 不同 → witness。`target_class` 仍关键词辅助。
- F13：`fmt_f13` gate 固定 `-(-2147483648)`、i64 min、triple nested；moonfmt 输出 `moon check` 均 `[4095]`，healthy `-(-1)` 通过；分类 `compiler_inconsistency_candidate`。

**P1**
4. 把 Float32/qNaN pilot（`float32_nan_pilot.md`）接入常规 campaign，补
   sNaN 的正负控，并在 JS 上排除/归一化 sNaN quieting；
5. async 随机 3–4 层组合与异常顺序；
6. trait/可变别名/指针域；
7. 用 headroom 指标（distinct T2/T3、time-to-threshold）重做 edge 实验，
   并强制 trace 完成率 ≥80% 才计收益（benchstat 已支持 invalid）。

**D 未覆盖（E 继续）**

- formatter：doc comment 内的 fenced code、极深泛型嵌套、trait impl 注释；
- package：`moon.mod` 正例、F8/F9 保留 package 形状的变异；
- L2 已更新为 **5/15 = 33.3%**（F/I 新增 1294/836/1347/415 均为 0；1294/836/415 是 **no_predicate**：warning/诊断/invalid-module 不是 judge defect）
  （1369 由 D1 `--stage format` 覆盖；1364 是 saturated，不算搜索能力）。
- E1 召回审计：第一轮 40 条 6 条缺陷（4 pin-validated）；第二轮 60 条 8 条
  labeled、4 pin-validated；两轮严格 8/100（95% CI 4.1–15.0%），推算漏 16–58 条，
  召回 30.8–61.9%。E2 36 条 0 rebuilt、30 blocked、6 unclear；核心风险是
  无最小模块/依赖，不是“无缺陷”。

## 6. 运行手册

```bash
# pin 检查
moon version --all            # 期望包含 0.1.20261104 / 0.10.20+65efd5b93

cd moonbit
moon test --target native     # 期望 Total tests: 385, passed: 385, failed: 0

# 完整验收（35 门）
./_build/native/debug/build/cmd/accept/accept.exe /data/audit/mbtfuzz
# 期望 {"ok":true,"checks":[...35...]}

# 短 campaign（示例）
./_build/native/debug/build/cmd/fuzz/fuzz.exe --root /data/audit/mbtfuzz \
  --out /tmp/short --workers 2 --duration 120 --mode mbt --body-only \
  --trace-t1 20 --trace-t2 20 --trace-workers 2 --trace-cpu 25

# sem3（node 独立参考；正控 --inject-node / --inject-moon / --inject all）
./_build/native/debug/build/cmd/sem3/sem3.exe --out /tmp/sem3 --duration 60 --seed 3
# 期望 {"cases":...,"unique_programs":...,"unique_witness":0,"oracle_candidates":0,...}

# async 固定 case（wasm-gc 零测试按 unsupported）
./_build/native/debug/build/cmd/asem/asem.exe --out /tmp/asem --duration 60

# 包模式 + triage
./_build/native/debug/build/cmd/fuzz/fuzz.exe --root /data/audit/mbtfuzz \
  --out /tmp/pkg --workers 2 --duration 300 --mode mbt \
  --pkg-seed /tmp/cap_base --pkg-file repro/repro.mbt \
  --pkg-argv "test --target js --build-only" --pkg-run-argv "test --target js" --triage

# triage 单命令 / 控制
./_build/native/debug/build/cmd/triage/triage.exe --case DIR --stage build --minimize BIN
scripts/triage_selftest.sh; scripts/triage_campaign_selftest.sh

# benchstat（无效/饱和会输出 valid:false + invalid_reasons）
./_build/native/debug/build/cmd/benchstat/benchstat.exe /tmp/ab_dir
```

## 7. 不要声称什么

- 不要声称“发现/确认了编译器 bug”；`min/-1` 是 allowed divergence。
- 不要声称“零 witness = 编译器无 bug”或“完备覆盖”。
- 不要引用 1,960 / 75% 平台、旧 edge “无收益”、旧 sem3 0-witness 表。
- 不要声称 Float32/NaN 已全面覆盖：2026-11-22 pilot 只覆盖 f32 位型/qNaN/
  ±0/±inf/subnormal，JS sNaN 是 allowed divergence；trait/指针仍未覆盖。
- 不要声称 async 时序、异常 Display 已比较。
- 不要声称 cgroup 聚合资源已实测。
- 不要发上游 issue/评论；不要改 pin。
- 不要声称主分支完全没有 `.py`：有 20 个已跟踪例外（15 vendored、3 PoC replay、2 scratch probe），MoonBit/accept 路径没有；见 `python_inventory.md`。

## 8. 最终检查


最终检查结果（2026-11-22 12:17 UTC）：

```
moon test   385 / 385（Total tests: 385, passed: 385, failed: 0）
accept      35 / 35（ok=true, checks=35, 无失败）
git         已提交并推送，worktree clean
pin         未改动
```

HEAD 与推送结果见本次提交（`docs: final handoff`）。

缺陷复核（同日）：见 `findings/defect_inventory.md`。F1–F12 全部仍在当前 pin
上复现（11 个根因类 + P1；F11/F12 合并），`cmd/regress` 13/13；未发现新缺陷，
也没有任何一条可称为 miscompile。

