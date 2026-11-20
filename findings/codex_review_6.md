# 独立评审核对：接受、证伪、以及它说错的地方

Date: 2026-11-20. 被评审提交 `cbe91a57`（评审自述），本次核对时 HEAD 为
`cbe91a5`（工作区干净）。评审文件：`/tmp/opencode/codex_gap_review.md`
（328 行，总分 5.5/10）。

核对方式：逐条读实现与文档，对可静态判定的断言给出文件与行为；未重新运行
campaign、PoC 或长跑（本文件之后的工作会跑，见 `findings/p0_closure.md`）。
评审自己声明"只读、未构建、未跑 campaign"，所以下文对"实现确认"与"历史实测"
分开标注。

## 总判定

**接受它的总分与四条主线**：反馈链成本高且易失效、有效语义输入不足、
可信结果链不统一、长期运行与收益证据不足。P0-1/P0-2/P0-3 三条我们全部
接受，并按它给的验收口径实施（见本次三个 commit）。

它也**没有**发现新编译器缺陷，这点与它自己的声明一致；5.5/10 是工程成熟度
评分，不是缺陷数量评分，我们不把它当"工具没有价值"的结论。

## 逐条核对

| # | 评审断言 | 判定 | 依据 |
|---|---|---|---|
| 1 | `semdiff` 两个目标同 timeout 会被判 `ALL_EQUAL` | **成立（P0）** | `Obs` 不含 `timed_out`（`cmd/semdiff/main.mbt:3-10`）；`run_one` 只把"stderr 里没有 build 失败片段"当 `built`（:161-182）；`live_of` 保留 rc=-999、stdout="" 的两个超时观测（:49-57）；`compare` 只比 rc/out（:95-109） |
| 2 | 一个 target build 失败会被丢弃，"剩余两个一致"可成 `ALL_EQUAL` | **成立** | 同上；`live.length() < 2` 只挡"少于两个"，不要求"等于请求的目标数" |
| 3 | 全 SKIP 也退出 0 | **成立** | 退出只看 `mismatches != 0`（:321-323）；`accept` 额外查 `skipped:0`，但没有堵住 #1 |
| 4 | `judge` 没有接入主 `cmd/fuzz` | **成立** | `cmd/fuzz` 只有 `@exec.classify`（:1114、:1944、:2141），无 `@judge` 引用 |
| 5 | `minimize` 复验失败仍把 `reduced` 写进 `--out` | **成立（P0）** | 失败时只把 workdir 的 target 恢复为 original（:112-114），`:115-117` 无条件写 `--out` |
| 6 | `minimize` 与 `save_crash` 用不同的归一签名 | **成立** | minimize 用 `@stager.signature`（:33，digit→`#`），save_crash 用 `stage|kind|ice_detail|rc`（`fuzz:1116-1118`） |
| 7 | `save_crash` 落盘后不把崩溃父本回灌 | **成立** | `fuzz:1967-1980` 保存后直接 `continue`，没有 `feedback_upsert` |
| 8 | 覆盖 witness 与行为样本共享预算，超额后覆盖样本不落盘 | **成立** | `persist_admit` 的 `force=false` 分支（:1179-1204）；`persist_coverage` 注释自认（:1250-1261） |
| 9 | 边集合本身不持久化 | **成立** | 注释明说 "The key set itself is not persisted"（:1259） |
| 10 | `append_line` 是读旧文件再整体重写 | **成立** | `corpus:197-203` |
| 11 | T3 snapshot 名为 `sha1(src).core`，重复提交被拒后会删掉同路径 | **成立（静态风险）** | `fuzz:2186-2207`：写入同一 `core_path`，`!queued` 时删除；同一 src 的第二个 worker 会覆盖/删除第一个任务仍在排队的 snapshot |
| 12 | `--as` 是逐进程地址空间上限，不是进程组总内存 | **成立（注释有误）** | `exec:133-155` 用 `prlimit --as=... -- timeout ...`；`RLIMIT_AS` 由每个子进程各自继承，多个 worker 可合计远超该值。`exec:126-131` 的注释"applies the memory cap to the whole group"是错的 |
| 13 | stdout/stderr 全量收集后才截断 | **成立** | `exec:46-74` 用 `ProcessOutput::Collect`，`cap_text` 在退出后 |
| 14 | QEMU 日志退出后才 stat，256 MiB 不是写盘硬上限 | **成立** | `trace/collect:247-265` |
| 15 | `bytefuzz`/`semdiff` 走不了隔离 runner | **成立** | `bytefuzz:273`、`semdiff:163` 均为 `@exec.run` |
| 16 | `seeds` 目录不在 git 里，`fetch_assets.sh` 浅克隆 core 不 pin | **成立** | `.gitignore` + `scripts/fetch_assets.sh:32-33` |
| 17 | 默认无 seeds 时打印一行后 `return`；缺 QEMU 只把 `cov_on` 置 false | **成立** | `fuzz:2551-2555`、`:2575-2579` |
| 18 | `run.sh hybrid 8 120` 可用，结果目录含 UTC+pid | **成立** | `run.sh` 与历史 `out/` 目录 |
| 19 | `methodology` 的成本模型把 build wall 时间套到 bytefuzz 的 syncheck 次数上 | **成立** | `methodology.md:207-240`；这是把 wall 当 CPU、把 rediscovery 当新根因 |
| 20 | `methodology` 用 640 builds / 8,849 test IDs / 12,096 executions 等不同单位给同一个"上界" | **成立** | 同表 §5；单位不可横向比较，需拆分或删除 |
| 21 | 0/270 与 0/140 是样本事实，不是总体 FPR 估计 | **成立** | 27 个源程序跨配置复用、140 次共享一个 `moon-lsp`；文档已注明相关性，但"上界"表述仍过强 |
| 22 | CI 只由 push/PR 触发，三项 trace 门禁不在公共 CI，seed 不 pin | **成立** | `.github/workflows/ci.yml` 与 `--profile core` |
| 23 | `minimize` 文档说"失败回退原输入"而代码行为不符 | **成立** | 文档 `cmd/minimize` 头部注释 vs :112-117 |
| 24 | 缺陷计数口径（12 个 F 编号 / 16 条目 / 13 个独立）不可直接当根因数 | **部分成立** | 见下节第 2 条：它把"独立类"读成了"新根因" |

## 评审说错或说过头的地方

1. **"默认 CLI 还强制 `--body-only`"——错。** `Config` 的默认值是
   `body_only: false`（`fuzz:2414`），只有显式 `--body-only` 才置 true
   （`:2468`）。它想说的"主循环偏向单文件"另有依据（`with_main` 补
   `fn main { () }`、T2 固定 wasm），但那不是默认开关。

2. **"13 个独立缺陷不能直接采信为根因数"——读错了我们的口径。**
   `README.md` §4 写的是"16 reproduced entries = 13 independent defects + 3
   same-signature witnesses"，并在同段明确 F8/F9/F10 是上游已知、F7 对应
   开放 #1322。我们从未把 13 说成 13 个新根因；"independent" 指签名类不相
   同。这个措辞确实容易被误读，已在 README 里改成"13 个不同签名类（其中
   F8–F10 为上游已知复现）"。

3. **"16 条目/13 独立"与"12 个 F 编号 + P1"并列时暗示我们混淆计数**——
   我们三处用的是同一张表（F1,F1b,…,P1 共 16 行），没有把 12 当 16。评审
   自己在 §4.1 也复述了 16 行，这一条属于表述摩擦，不是事实错误。

4. **"1–2 周修完 / 4–8 工程师周"**——是工程估算，不是可核对的事实；我们
   不引用为承诺，只作为优先级排序的参考。

5. **"CI pinned 只核对文件、不声称访问复验"**——它诚实标注了；实际上运行
   记录在 `findings/toolchain_archive.md`（run 44570253756）。

6. **它把 `scalefuzz` 的 21/36 当"已知 F7 邻域触发率"**——正确，我们文档
   也是这么写的（`findings/scale_sweep.md`）；这不是它的错误，列出以免被
   二次误读成"21 个新缺陷"。

## 由此确定的三条 P0（本次实施）

| P0 | 验收（评审口径 + 我们的补强） |
|---|---|
| P0-1 假通过 / 判定分叉 | `semdiff` 每目标五态（BUILD_FAIL/LINK_FAIL/TIMEOUT/RUN_FAIL/COMPLETE）；只有全部请求目标 COMPLETE 且 rc=0 才 `ALL_EQUAL`；同 timeout/同 signal/同 ICE 一律 INCONCLUSIVE；零 case 或任一 INCONCLUSIVE 非零退出；`@judge` 接入 `cmd/fuzz`，保存的 finding 标 `candidate`；`minimize` 未复验不发布 `--out`；反例进 wbtest 与 accept |
| P0-2 覆盖证据不丢 | 覆盖 witness 独立预算；feature sidecar 与边 key 可恢复；crash 落盘后回灌父本；`--seed-dir` 能重放各 mode；淘汰保护最后 feature owner |
| P0-3 总资源硬边界 | 统一 runner；stdout/stderr 流式 cap；QEMU 日志写盘上限；stats 真 append；T3 snapshot 路径唯一化 |

## 评审漏掉的一个真实缺陷（本次实施中发现）

`cmd/fuzz` 的参数解析里，`--persist-cap` 分支缺少 `i += 2`：传入
`--persist-cap N` 后 `i` 不前进，循环永远停在同一参数上。表现为进程
100% CPU、RSS 个位数 MB、无子进程、无任何输出目录——看起来像"卡死"，
实际是纯自旋。评审给了 `P0-3`（资源边界）和 `--persist-cap` 的讨论，但
没有发现这个分支本身不可用。

已在 P0-3 修复，并顺带用脚本审计了其余所有 `i + 1 < args.length()`
分支（没有第二处）。这类缺陷无法靠"读文档"发现，只能靠实际用每个参数
跑一次——也是 30 分钟 soak 的第一项收益。

## 评审未覆盖、但我们认为同样重要的点

- `harness/all_pkgs.json` 的绝对路径重写是上一轮才修的；评审基于 HEAD 没有
  复验 CI 的 pinned job，所以"可复现性明显进步"这一条它只能看文件。
- `accept --profile core` 的 `skipped` 字段只是披露，不是能力；三项 trace 门禁
  仍需要宿主机工具，这一缺口评审说对了。
- 评审没有检查 `semdiff` 的 `--targets` 与 accept 的 `skipped:0` 之间的
  语义差（"目标没跑"与"跑了但没完成"是两件事），本次 P0-1 一并修。

## 实施状态（2026-11-20 晚）

| 项 | 状态 | 证据 |
|---|---|---|
| P0-1 假通过 / 判定分叉 | 完成 `44c3dab` | `findings/p0_correctness.md`；semdiff 五态、self-test 9 例、judge 接入、minimize 只发布 verified |
| P0-2 覆盖证据不丢 | 完成 `3a049da` | `findings/p0_evidence.md`；独立 `--coverage-cap`、边 key sidecar、crash 回灌、mode 命名、owner 保护 |
| P0-3 资源硬边界 | 部分完成 `ba3a39b` | `findings/p0_resources.md`；磁盘/日志/append/T3 路径已封顶，**内存仍未封顶**（30 分钟 RSS→2.67 GB） |
| P1-2 深层漏斗 | 完成 `0dc9c25` | `findings/deep_funnel.md`；30 分钟 11,451 例 T3 全部与解释器一致 |
| P1-1 反馈 A/B | 完成 `8f3c825` | `findings/p1_feedback.md`；三臂 10 分钟、trace 完成率 22–24%、新函数 0、中位新 feature 0 |
| P1-4 内存硬顶 + 长跑 | 部分完成 | `findings/soak_2h.md`（单进程 9.9 GB）、`findings/rss_diagnosis.md`（组件二分 + epoch 方案，1 h 峰值 386 MB） |
| P1-3 triage 流水线 | 未做 | 本轮只做了 `cmd/verify` 与 minimize 的人工串联 |
| P1-5 真实包 capsule / P1-6 反馈进 CI | 未做 | 保持原状 |

本轮还修了一个评审没发现的缺陷：`--persist-cap` 分支缺 `i += 2`，参数
解析会 100% CPU 自旋（`ba3a39b`）。
