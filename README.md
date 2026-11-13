# MoonBit 工具链升级 & 闭源条件下的编译器 fuzz 调研

日期：2026-11-11　环境：Linux x86-64 / 128 核 / 1TB RAM
工作目录：`/data/audit/mbtfuzz`

GitHub：<https://github.com/I3eg1nner/moonc-fuzz>

快速开始：

```bash
git clone https://github.com/I3eg1nner/moonc-fuzz.git
cd moonc-fuzz
./scripts/fetch_assets.sh          # F6 第三方包；可选 seed 语料
cd moonbit && moon test && moon run cmd/accept -- /path/to/moonc-fuzz
# 只复现缺陷：
cd .. && ./scripts/reproduce_all.sh
```

本仓库只提交源码/文档/小 PoC。`out/`、`seeds/`、`assets/`、`moonbit/_build/`
等生成物或大包不提交；F6 的 12 MB 包由脚本下载，F6 另有 12 行最小复现。

---

## 0. TL;DR

1. **工具链已升级**：`moon 0.1.20261028` → `0.1.20261104`，`moonc v0.10.18` → `v0.10.20`（与官方 `version.json` 一致）。
2. **"编译器闭源"基本属实，但情况比想象的好一点**：官方 `moonbitlang/moonbit-compiler` 仓库里确实有 20 万行 OCaml 源码，但那是 **2025-03-12 的快照**（最后真实提交 2025-09-29），2026 年的 release tag 全部指向这棵旧树，只用来挂二进制资产。许可证是自制的 *MoonBit Public Source License v1*，不是 OSI 开源许可证。当前发货的 `moonc v0.10.20` 无法从公开源码构建 ⇒ **对当前版本而言是闭源**。
3. **但闭源不等于黑盒**：发货的 `moonc` 是 **未 strip 的 OCaml 二进制**（符号丰富：`nm` 文本符号 30,465 个，Menhir 产生式名可见；但 `.debug_line` 不可用，行级归因受限），`OCAMLRUNPARAM=b` 还能拿到带文件/行号的 backtrace。这对定向 fuzz 极其有利。
4. **在闭源二进制上搭了一套可跑的 fuzz 系统**，用"分层流水线 + 语义 oracle + 结构感知变异 + 诊断签名覆盖代理"，跑到 **~1.5k exec/s**，两轮共 **~300 万次执行**。
5. **挖到 6 类可复现问题（F1–F6）+ 1 个性能异常（P1）**，全部有最小化 PoC；其中 F1b/F2b/F4b 是同一根因的额外 witness，F6 已缩到 12 行：

| # | 问题 | 最小输入 | 后果 | 影响面 |
|---|------|---------|------|--------|
| F1 | `moon.pkg` 解析错误路径 SIGSEGV（根因待定） | 101 B `moon.pkg` | 编译器段错误 | 已确认：显式 `moonc syncheck moon.pkg` |
| F2 | 字符串转义 `\`+非 Latin-1 字符 → ICE（`Char.chr`） | 9 B 源码 | 误报“编译器 bug”，构建失败 | `moon check` / `moon build` |
| F3 | 解析错误恢复 OOM | 19 B 源码 | 6 GiB cap 下 5.2–5.7 GiB 后 abort；uncapped 8.2 GiB/20 s | `moonc syncheck` |
| F4 | `.mbt.md` 非法 UTF-8 → ICE（`Basic_utf8_decode.MalFormed`） | 22 B | 误报编译器 bug | `moonc syncheck` |
| F5 | 前缀 `+` 变内部不可词法化 `~+` | 2 行源码 | fmt 后无法重新解析 | `moonfmt` + `syncheck` |
| F6 | native 导出类型可达闭包 → link ICE | 12 行单包 | 应在链接前给干净诊断，却 ICE | `moon build/test --target native` |
| P1 | formatter 插值复杂度超线性 | 2,048 段 | 约 10×/倍增 | `moonfmt` |

> F1b/F2b/F4b 是同一根因的额外 witness；F1/F6 的修正见 `findings/F1_moon_pkg_parse_segv.md` 与 `findings/f6_moonbit_fixture.md`。MoonBit 主路径、12 例回归与验收门禁见 §9。

> 详细报告见 `findings/`，PoC 见 `poc/`，原始崩溃样本见 `out/`。

---

## 1. 工具链升级

### 1.1 升级前后

```
升级前: moon 0.1.20261028 (e1e1f15 2026-10-28)
        moonc v0.10.18+6c83a7f62 (2026-10-28)
        moonrun 0.1.20261028

升级后: moon 0.1.20261104 (940aa18 2026-11-04)
        moonc v0.10.20+65efd5b93 (2026-11-05)
        moonrun 0.1.20261104 (940aa18 2026-11-04)
```

与 `https://cli.moonbitlang.com/version.json` 的 latest 完全一致，冒烟测试通过（`moon new` / `moon run cmd/main` / `moonc syncheck` / `moon test`）。

### 1.2 升级踩坑（记录一下，别人也会遇到）

`moon upgrade` 强制要求 TTY，直接跑报 `Error: IO error: not a terminal`。非交互环境下的做法：

```bash
# 需要一个伪终端 + 应答 [Y/n] 提示
(printf 'y\n'; sleep 60) | script -qec "moon upgrade --force" /tmp/up.log
```

注意 `yes '' | script ...` 会挂住（`script` 等 pty EOF），`(printf 'y\n'; sleep N)` 这种写法可以正常结束。
另外 `moon upgrade --force` 会整包替换 `~/.moon`（本次下载约 500 MB，含 core 的四个 target bundle）。

---

## 2. 编译器开源状态调研

### 2.1 结论

| 维度 | 结论 |
|------|------|
| 是否有公开源码 | **有，但是停更快照** |
| 许可证 | **MoonBit Public Source License v1**（自制，非 OSI 认证，source-available ≠ open source） |
| 快照覆盖范围 | lexer / Menhir parser / typer / monomorphization / core IR / wasm+wasm-gc 后端 / 优化 pass |
| 快照缺失范围 | JS、native、LLVM 后端，`moonfmt`、`moondoc`、runtime、测试/覆盖率工具 |
| 当前版本可否从源码构建 | **否**（2026 的 release tag 仍指向 2025-03-12 的树） |
| 当前二进制可分析性 | **很高**：未 strip、DWARF 完整、OCaml 符号 + Menhir 产生式名 |

### 2.2 证据链

**(a) 仓库内容真的是编译器，但停留在 2025 年 3 月**

```
$ tar tzf moonbit-compiler-main.tar.gz | wc -l      # 276 个文件
$ find src -name '*.ml*' | xargs wc -l | tail -1    # 202232 行
$ cat src/git_commit.ml
let date = "20250312"
let short_version = "a7a1e9804"
```

`src/` 下有 `lex_*.ml`（词法）、`parsing_parser.ml`（3.1 MB，Menhir 生成的 LR 表）、`typer.ml` / `monofy*.ml`（类型检查/单态化）、`wasmir_*.ml` / `wasm_of_clam_gc.ml` / `dwarfsm_*.ml`（wasm 后端与 DWARF 生成）、`pass_*.ml`（优化）。

**(b) release tag 是"假的"，只挂二进制**

- `commits/main.atom`：最后更新 `2025-09-29`
- 但 `releases.atom` 最新是 **2026-11-02**，`v0.10.19+97801ee1b`
- 下载该 tag 的源码树，`src/git_commit.ml` 仍然是 `date = "20250312"`
- 资产名是 `MoonBit WASM Compiler v0.10.19+...`，即 **wasm 版的编译器二进制**（`moonc.js` + `moonfmt.js`）

⇒ 发布流程是"私有树构建二进制 → 在旧 commit 上打 tag → 上传资产"。源码与二进制不同步。

**(c) 许可证不是开源许可证**

`LICENSE.TXT` = *MoonBit Public Source License, Version 1, 11 December 2024*，正文明确写了 SSPL-like 的取舍（"we chose the relaxed SSPL instead of a fully permissive..."），并单独规定"编译器产出物可由用户以任意条款授权"。可以读、可以改、可以自用，但不是 Apache/MIT 那种可自由再分发的开源许可。

**(d) 二进制本身信息量极大（fuzz 的关键）**

```
$ file ~/.moon/bin/moonc
ELF 64-bit LSB executable, x86-64, ... with debug_info, not stripped
$ readelf -S moonc | grep debug
.debug_info / .debug_line / .debug_str / .debug_loc / .symtab   (全都在)
$ nm moonc | wc -l                      # 74399
$ nm moonc | grep -c ' T '              # 30411 个函数符号
$ strings moonc | grep opam-switch      # /root/.opam/idea-dev/... ocaml-variants.4.14.1+idea
```

由符号可还原出内部结构：`Moonc__desugar*`、`Moonc__monofy*`、`Moonc__Core_link.link`、`Moonc__Lex_literal.Interpret.*`、`Moonc__ice_catcher`，以及 **379 个 `menhir_goto_*` 产生式名**（`arrow_fn_prefix`、`lexscan_case`、`trailing_info_record_defn`……），等于把语法结构白送给你。

**(e) 崩溃时的可观测性**

`moonc` 内置 ICE catcher（旧源码 `src/ice_catcher.ml`）：捕获未处理异常 → 打印 ASCII 横幅 + 上报链接 + `Printexc` backtrace + 命令行 → **退出码 199**。设置 `OCAMLRUNPARAM=b` 后 backtrace 带函数名与 `file:line`（本次 F2 就是这样定位到 `Lex_literal.sub_string_of_codepoints` 的）。

⇒ 对 fuzz 来说：判据清晰（`rc=199`、`rc<0`、stderr 横幅、超时），且崩溃可归并、可读。

### 2.3 所以"闭源该怎么做 fuzz"——可行路径排序

1. **黑盒 + 高吞吐进程级并行**（本次主力）：`moonc` 单次 10–30 ms，进程级并行 80–100 路轻松 1.5k exec/s，一天能跑 1 亿次。闭源不构成障碍。
2. **二进制插桩覆盖率**：AFL++ 的 **QEMU 模式**（`afl-qemu-trace`）可对未插桩 ELF 做 edge coverage，已在本环境编译好（`make` in `qemu_mode/`）。配合 `-Q` 即可做覆盖率引导。缺点是 QEMU 会把 10 ms 放大到几十 ms，吞吐降一个量级，但方向性更强。
3. **"代理覆盖率"**：用 2025-03 的公开源码自己 build 一个带 `bisect_ppx` 的编译器，用它的覆盖率指导语料演化，再把语料喂给发货二进制。（源码旧，语法有漂移，但大部分前端结构没变。）
4. **差分测试**：`moonc` 有 `-target {wasm|wasm-gc|js|native|llvm|...}`，四个 stdlib bundle 在 `~/.moon/lib/core/_build/<target>/release/bundle` 下齐全，同源代码跨后端比较"接受性 / stdout / 退出码"。
5. **元测试（metamorphic）**：`moon fmt` 幂等性、`moonc info` 生成 `.mbti` 与 `check -check-mi` 的一致性、`syncheck` 与 `check` 的接受性一致性。
6. **配置/文档解析器**：`moon.pkg`、`moon.mod`、`.mbtx`、`.mbt.md`、`.mbti` —— 2026 年新加的格式，历史上最容易出问题（本次 F1/F4 就来自这里）。

---

## 3. 本次 fuzz 系统设计

```
/usr/bin/moonc
   │
   ├─ T1  syncheck            lexer + Menhir parser + 轻量语法检查   ~10 ms
   │       └─ 输入类型: .mbt / .mbtx / .mbt.md / moon.pkg / moon.mod / .mbti
   │
   ├─ T2  build-package       typer → monomorphize → core IR → wasm  ~30 ms
   │
   └─ T3  link-core + moonrun 链接 + 执行，并与 -target js 差分        ~100 ms
```

**oracle（判据）**

| 判据 | 说明 |
|------|------|
| `rc == 199` / stderr 含 `Oops, the compiler has encountered` | ICE，附带 backtrace，可归并 |
| `rc < 0` | 信号（本次抓到 SIGSEGV） |
| `Fatal error: exception ...` | OCaml 未捕获异常（含 `Stack_overflow`） |
| 超时 | 挂死 / 复杂度爆炸（本次抓到 F3，进一步测到 RSS 25 GB/min） |
| wasm vs js 的 stdout / rc 不一致 | 潜在误编译 |
| **诊断签名新颖性**：`ACC|ERR` + stderr 里所有 `[E####]/[W####]` 的集合 + `syncheck` 的 `toplevel` JSON | **oracle 分区多样性**（行为签名），用于语料去重；注意它**不是覆盖率**，见 §3.3 |

**变异器（`harness/mutate.py`，16 种，按权重随机组合）**

- 括号配平感知：块复制、块删除、包裹成 `if/match/try/loop`
- token 级替换：关键字、内建类型、运算符、标识符重命名
- 字面量边界：`0 / -1 / 2^31-1 / -2^63 / 2^64-1 / 1e308 / nan / \u{10FFFF} / \u{110000}`
- Unicode 注入（combining mark、ZWJ、U+202E、emoji）
- `#[derive]`/`#[inline]`/`#[test]` 属性注入、泛型签名改造、async/raise 改造
- 文件截断（EOF 鲁棒性）、分隔符删除、4 字节随机翻转

**并发与 IO**：每 worker 独立 `/dev/shm` 工作目录；诊断签名用原子 `mkdir` 去重（无锁）；统计通过 per-worker JSON 汇总。

### 3.1 怎么跑

```bash
# 主流程（.mbt，三层流水线）
python3 harness/mbtfuzz.py --workers 96 --duration 3600 --p-deep 0.5 --p-run 0.5 --diff

# 只打配置解析器（2026 新格式，性价比最高）
python3 harness/mbtfuzz.py --mode pkg   --workers 48 --duration 3600
python3 harness/mbtfuzz.py --mode mod   --workers 48 --duration 3600
python3 harness/mbtfuzz.py --mode mbtmd  --workers 32 --duration 3600
python3 harness/mbtfuzz.py --mode mbti  --workers 32 --duration 3600

# 单文件复现
python3 harness/mbtfuzz.py --replay poc/f2_lex_escape_ice/cmd/main.mbt
```

结果落在 `out/`：`findings/`（按 stage/kind/签名去重的崩溃样本 + stderr + meta）、`sigs/`（行为签名）、`corpus/`（新语料）、`stats/`。

### 3.2 覆盖率引导（工具已备好，但**别用在 T1**）

> 实测观察（限定于该语料/该轮）：在 200 个真实种子后，AFL 对该 T1 语料再跑 3,885 次执行没有新边。这不能推出“T1 全局饱和/剩余边不可达”，只能说明这批种子下的边际收益已经很低；引导预算应优先投向 T2/T3（见 §3.3 与 `findings/coverage.md`）。

```bash
# 本环境已在 /tmp/AFLplusplus 编译好（afl-fuzz + afl-qemu-trace，QEMU 模式）
# 若目录不存在，重新构建：
#   git clone --depth 1 https://github.com/AFLplusplus/AFLplusplus
#   cd AFLplusplus && make -j64 afl-fuzz && (cd qemu_mode && ./build_qemu_support.sh)
# 注意：必须直接以 moonc 为目标；用 bash 包装会让 QEMU 只插桩 bash（覆盖率掉 8 倍）
AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
  AFL_QEMU_MAP_SIZE=262144 AFL_MAP_SIZE=262144 \
  /tmp/AFLplusplus/afl-fuzz -Q -i seeds -o afl-out -m none -t 5000 \
  -- ~/.moon/bin/moonc syncheck -error-format json @@
```

`harness/afl_syncheck.sh` 里 `AFL_CRASH_EXITCODE=199`，这样 ICE 也会被当成 crash 收集。

harness 里把 `moonc syncheck` 的退出码统一成 0，只让真实信号/超时算 crash；AFL 的 queue 可以直接回灌成 `mbtfuzz` 的语料。

### 3.3 覆盖率：到底怎么定义（详见 `findings/coverage.md`）

之前的"诊断签名"只是行为分区代理，不是覆盖率。真正的定义是：

```
一次执行 T(P) = b0, b1, ..., bn
边集合   E(P) = { (b_i, b_{i+1}) | 0 ≤ i < n }
语料     E(C) = ⋃_{P∈C} E(P)
覆盖率   Cov(C) = |E(C) ∩ E*| / |E*|      # E* = 二进制所有可行执行的边集
```

`E*` 不可精确判定，所以百分比必须声明分母。落地成两种粒度：

| 粒度 | 工具 | 用途 | 代价 |
|------|------|------|------|
| 边（bitmap 槽） | `afl-showmap -Q` + `AFL_QEMU_OLD_COVERAGE=1` | 离线语料并集、最小化 | 0.22 s/次 |
| 函数 | `afl-qemu-trace -d exec` + `nm` 符号化 | 可解释度量、跨语料比较 | ~1 s/次 |

**必须先分清两种 QEMU 口径**（这是本轮修正的关键）：

| | 默认 | `AFL_QEMU_OLD_COVERAGE=1` |
|---|---|---|
| id 来源 | 首次见到的边 `next_id++`（5,6,7…） | `hash(pc) ^ prev>>1` |
| 跨进程可比 | **否**（每次 showmap 重新分配） | **是** |
| 碰撞 | 基本无（直到 map 回绕） | 有（16 位哈希） |
| 用途 | AFL 自身在线引导 | **离线语料比较** |

第一版用默认口径算跨进程并集，数字是虚的（见下）。**2026-11-11 修订**：默认口径的
id 是 `next_id % (map_size−5) + 5`，按翻译顺序递增，跨进程并集实测就是连续区间
`{5..N}`，所以「边覆盖率」这个百分比**没有意义，全部作废**。跨语料只报函数覆盖：

| 语料 / 阶段 | n | 函数 | `Moonc.*`（/26,611） |
|---|---:|---:|---:|
| seeds · T1 | 100 | 2,456 | 1,969（7.4%） |
| 随机变异 · T1 | 1000 | 1,854 | 1,369（5.1%） |
| seeds40 · T2 | 40 | 4,626 | 4,023（15.1%） |
| 本项目 T2 语料 · T2 | 293 | — | 4,783（18.0%） |
| core 真程序 · T2（本轮） | 1,368 | 6,387 | 5,734（21.5%） |
| 两批语料并集（同调用） | 1,232 | — | 5,925（22.3%） |
| 四入口并集 check∪build∪test∪link | 1,157 条命令 | — | 7,097（26.7%） |
| + release 配置（build+test） | +559 条命令 | — | 7,412（27.9%） |
| + native / llvm / -enable-coverage | +393 条命令 | — | 7,591（28.5%） |
| + `link_rel`（全部 11 个 replay 产物） | +69 | — | 7,660（28.8%） |
| + 自建语料 real ∪ mix（历史头条） | — | — | 7,847（29.5%） |
| **+ 自建语料 + `link_rel`（推荐头条，最大文档化并集）** | +69 | — | **7,916（29.75%）** |

口径说明（2026-11-12 审计，详见 `findings/cov_audit.md`）：7,591 / 7,660 / 7,847 / 7,916
是**四个不同集合**——7,591 = 四入口 + release + native/llvm/cov_flag；7,660 = 7,591 ∪ `link_rel`
（+69）；7,847 = 7,591 ∪ real ∪ mix；7,916 = 7,660 ∪ real ∪ mix。论文/报告必须冻结一个
（推荐 7,916 = 29.75%，最大文档化并集）并把其余作为消融，不能混用。符号化审计：51.2M PC 中
仅 0.003% 落在函数区间外，全部是 CRT 符号（`_init`/`_fini` 等），`camlMoonc` 归因 0 差异；
`replay.py` 现已保留 rc/stderr（check 299/299、build 130/130 rc=0；test 的 16 个 rc=199 是
并行回放缺少 `.core` 的顺序假象，单跑 rc=0）。

结论：

1. **T2 比 T1 深一倍多**：`Moonc.*` 从 7.4% 到 18.0%。
2. **随机变异在 T1 只是打平**，不是更差——第一版"随机导致覆盖下降"撤回（同样是 id 不稳定造成的假象）。
3. **T2 上"结构保持变异 + 行为签名语料"最深**（18.0%）。
4. **真程序的净效应只有 +2.5pp**（同调用对照：旧语料 5,080 → 真程序 5,734）。
   两批语料互补，**并集 5,925 = 22.3%** 才是当前最优（此前报 21.5% 是说低了）。
5. **"加输入没用"的证据是并集饱和，不是边际中位数**：贪心序 **232 个输入**就覆盖
   全部 5,734（随机序 1,000 个到 5,693）。旧口径"后 868 个只多 251"是**文件大小
   升序排序造成的假象**，撤回。详见 `findings/real_corpus.md` §3.2。
6. **配置轴（release）也有效**：release build 比 debug 多 315 个函数，
   对四入口并集 +302；release 换的是源文件集合（`assert_release.mbt`），不是噪声。
7. **后端面比预期薄 20 倍**：`-target native` 对并集只 +82、`llvm` +78（且 llvm ⊂ native），
   `-stacktrace` +0。18,764 个未覆盖函数只是**未观测**，不是不可达（撤回"80% 不可达"）。
8. **入口才是这一轮真正的增量**：`check` 19.2%、`build` 20.6%、`test` 22.2%、
   `link-core` 单独只有 6.3%，但四者**不是超集**——link 给并集 +1,154（+16%），
   总覆盖 **26.7%**。这条路之前一次都没走过（详见 `findings/entrances.md`）。
6. **单输入的边数仍然精确可用**：真程序平均 26,471 条 TB 边/次（中位 26,230）。

### 3.4 工程坑（实测）

| 坑 | 现象 | 解法 |
|----|------|------|
| **跨进程边 id 不可比** | 语料并集虚高/虚低，最小化退化到 1 个文件 | 离线并集必须 `AFL_QEMU_OLD_COVERAGE=1` |
| QEMU 模式 map 固定 65536 | `AFL_MAP_SIZE` 无效 | 用 `AFL_QEMU_MAP_SIZE`（+ afl-fuzz 侧 `AFL_MAP_SIZE`） |
| bash 包装毁覆盖率 | `-- bash harness.sh @@` 只覆盖到 bash（3,254 槽 vs 直连 25,143） | 直接以 `moonc` 为目标 |
| 符号化假阳性 | 0x4000_0000_0000+ 区间的 PC 减基址后"恰好"落进 moonc .text | 只接受 `< 0x2000000` 的 PC |
| `/dev/shm` 只有 64 MB | worker 目录写满 → showmap 静默失败 → 覆盖率全 0 | 工作目录放 `/tmp` |
| `core_pattern`=apport | afl-fuzz 启动即 abort | `AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1`、`-m none` |
| OCaml 无 `.debug_line` | `addr2line` 对 `camlMoonc__*` 全 `??:?` | 函数级是下限，行级不可得 |

### 3.5 与论文的对应关系

| 文献 | 我们对应做了什么 |
|------|------------------|
| AFL 白皮书 / AFL++ | 边覆盖 + 命中计数分桶的口径；`afl-showmap` 离线重放 |
| CollAFL (S&P'18) | 解释了为什么 T2 的 69.7% 利用率必须扩容，否则碰撞污染"新边"判定 |
| CSmith (PLDI'11) | 结构感知变异器；后续应做"永远合法"的生成器 |
| EMI (PLDI'14) | 用覆盖挑"没跑到的地方"再做蜕变变异——比"用覆盖选语料"更贴合编译器 |
| ClassFuzz (PLDI'16) | 覆盖引导的选择准则 + 多实现差分，对应我们的 wasm/js 差分 |
| Survey (CSUR'20) | 覆盖与 oracle 正交，必须分开报告 |
| Marcozzi (OOPSLA'19) | 下一步要给每个 finding 做可利用性/triage 评估 |
| wasm-smith | `moonrun`/`link-core` 的结构化生成 + 多引擎差分 |

---

## 4. 跑量与结果

| 轮次 | 模式 | worker | 时长 | 执行数 | 其中 T2 | T3 | 去重后问题 |
|------|------|--------|------|--------|---------|----|-----------|
| 1 | `.mbt` 全流水线 | 80 | 900 s | 1,421,387 | 234,025 | 22,601 | 4 类（HANG / UTF8-ICE / SIGSEGV / Char.chr-ICE×2 路径） |
| 2 | `moon.pkg` | 40 | 900 s | 1,545,871 | — | — | 1 类（SIGSEGV） |
| 3 | `.mbt.md` | 6 | 30 s | 14,612 | — | — | 1 类（UTF8-ICE） |

吞吐稳定在 **1.5k–1.7k exec/s**（每 worker ~20 ms/次，含 Python 调度开销）。

### 4.1 发现清单

| ID | stage | 现象 | 最小输入 | 复现命令 |
|----|-------|------|----------|----------|
| F1 | t1/pkg | SIGSEGV | 101 B | `cd poc/f1_moon_pkg_segv && moonc syncheck moon.pkg` → 139 |
| F2 | t2 | ICE `Invalid_argument("Char.chr")` | 9 B | `cd poc/f2_lex_escape_ice && moon check` → 199 |
| F3 | t1 | 内存无限增长 → OOM | 19 B | `cd poc/f3_parser_oom && moon check` → 多 GB RSS |
| F4 | t1/mbtmd | ICE `Basic_utf8_decode.MalFormed` | 22 B | `cd poc/f4_invalid_utf8 && moonc syncheck doc.mbt.md` → 199 |
| F5 | t2/fmt | 前缀 `+` 脱糖成不可词法的内部名 `~+`：诊断泄漏内部名，`moonfmt` 输出无法再解析 | 27 B | `printf 'fn f(y : Int) -> Int { +y }\n' > u.mbt && moonfmt u.mbt -o u1.mbt && moonc syncheck u1.mbt` → E3001 |
| F6 | t3/native | `foreign_library` 导出函数的签名可达闭包类型时，native link ICE：`Machine_error(... reject_export_type_containing_unsupported_callback ...)`；模块级 `moon build --target native` 也失败 | 第三方包 + 12 行最小复现 | `poc/f6_native_export_closure/`；`poc/f6_native_export_closure_min/`；5/5 + 3/3 |

详细的复现步骤、backtrace、根因假设和修复建议见：

- `findings/F1_moon_pkg_parse_segv.md`
- `findings/F2_lex_escape_ice.md`
- `findings/F3_parser_oom_dos.md`
- `findings/F4_invalid_utf8_ice.md`
- `findings/syntax_boundary.md`（F5 + P1，见 §6.1.2）
- `poc/f6_native_export_closure/`（F6 第三方外部有效性）+ `poc/f6_native_export_closure_min/`（12 行最小复现，见 §6.1.6）

---

### 4.2 T2 定向 campaign（本轮新增）

按上轮结论把预算压到 `build-package`，并给变异器加了 **body-only** 模式（85% 的变异只改函数体，保住顶层声明，让输入能穿过后端）。

```
python3 harness/mbtfuzz.py --workers 96 --duration 300 --p-deep 1.0 --p-run 0.35 --diff --body-only
```

| 指标 | 数值 |
|---|---|
| 总执行 | 608,257 次（≈2,030 exec/s，96 worker） |
| 进入 T2 | 187,160 次（30.8%） |
| 进入 T3 | 9,149 次 |
| 新增行为签名 | 679 |
| 新增 crash 类别 | 0（命中的都是已记录的 F2/F4 签名） |

对照：8 个 AFL++ QEMU 实例跑 300 s，共 13,320 次执行（13.3 exec/s/核），队列从 120 涨到 248，边并集比种子多 760（+1.8%）。

覆盖率对比（T2，各取 100 个输入，`Moonc.*` 分母 26,611）：

| 语料 | 函数 | `Moonc.*` | 占比 |
|---|---:|---:|---:|
| core 种子 | 4,100 | 3,503 | 13.2% |
| AFL 队列 | 3,807 | 3,207 | 12.1% |
| **本项目 T2 语料** | **5,089** | **4,474** | **16.8%** |

⇒ 在这个阶段，**"结构保持变异 + 行为签名语料"在本项目里更划算**：它的原始变异吞吐远高于 AFL QEMU 边引导（后者约 13 exec/s/核）。但这不是同 worker 数、同语料、同计费口径的受控对比，不能表述为“150 倍成本效益”；只能说在本环境下前者更适合当前目标。AFL 的边引导在 T2 确实有信号（+760 边）。

---

### 4.3 差分流水线：先补前置条件（本轮重点）

上轮的教训是 `--diff` 早就接通但 0 发现——问题不在 oracle，在**输入到不了 oracle 面前**。本轮按"先补前置条件"推进。

**第一步：5 个手写探针（30 分钟）**

| 探针 | 语义面 | 结论 |
|------|--------|------|
| Int 溢出/除法/移位 | p1_int | SAME |
| Double NaN/-0.0/0.1+0.2 | p2_float | SAME |
| Unicode 字符串 | p3_string | SAME |
| struct + derive | p4_struct | SAME |
| enum match | p5_match | SAME |

答案：**不是没跑起来，是跑了且一致**。但把边界值加进去立刻咬到第一个分歧（D1）。

**第二步：模板 + 函数体变异 + 可运行门槛**

- `templates/`：**25 个**确定性程序，固定 `fn main { println(compute()) }`，只变异 `compute` 函数体；
- 变异分两档：gentle（85%，字面量边界/同类运算符互换/小块复制）与 aggressive（15%）；
- 分类：`SAME` / `FORMAT_DIFF`（数值归一后相同）/ `REAL_DIFF`（真误编译候选）/ `TRAP_DIFF`（一端 trap）/ 各阶段失败。

| 阶段 | 执行数 | 可运行率 | REAL | FORMAT | TRAP |
|------|-------:|---------:|-----:|-------:|-----:|
| 旧 fuzz 语料抽样 100 | 100 | **0.0%** | 0 | 0 | 0 |
| 模板 + aggressive | 115,674 | 25.6% | 0 | 0 | 0 |
| 模板 + gentle | 32,160 | **71.8%** | 0 | 0 | 10 |
| 三后端（+wasm-gc） | 18,321 | 71.8% | 0 | 0 | 5 |

- **可运行率 0% → 71.8%**（目标 50%+ 达成）；
- **差分候选 3.11 / 万次执行**（全是 TRAP 类），真误编译 0；
- 语义去重后（按输出对归并）6 个变体归为 3 类。

**产出 D1：`Int::min / -1` 跨后端分歧**

```moonbit
let a = -2147483648
println((a / -1).to_string())   // wasm: trap "divide result unrepresentable"
                                 // js:   -2147483648（回绕）
```

wasm-gc 与 wasm 一致（trap）。待确认是规范陷阱还是后端实现差异。

**两个未知已确认**：native 后端可用（`moon run --target native` 正常），wasm-gc 由 `moonrun` 执行；25 个模板三后端全一致。

**顺带完成**：覆盖率回归工具（`cov.py diff a.json b.json`，比较两次快照的函数集合），固定 pilot 语料即可做升级前后对比。

---

## 5. 对这轮结果的判断

- **F1 / F3 属于质量问题**：输入极小、代价极低（一个 `moon.pkg` / 一个 `.mbt` 文件），却能让 `moonc` 子命令（`syncheck` / `build-package` 等）段错误或 OOM；`moon` 驱动自身用安全配置解析器不崩，F1 的已确认影响面只是**显式对 `moon.pkg` 跑 `moonc syncheck`**；同目录下对合法源文件跑 `build-package`/`check` 不崩。IDE/LSP 调用路径未验证，不能作为结论。根因也仍是假设（栈顶一致但未证明越界读）。
- **F2 是低级的错误路径缺陷**：用户写错一个字面量（`"\中"` 这种很常见的错误），编译器应该说"invalid escape"，结果打 ICE 横幅并让用户去提 bug report，属于可诊断性问题 + 体验灾难。
- **本轮采样没有发现误编译**（wasm/js 差分未抓到），但这只是有限模板/语料上的负结果，不能推出 codegen 成熟；问题集中在 **2026 年新写的配置/字面量/错误恢复代码**，这与“新格式优先 fuzz”的策略一致，但仍需独立语义参考才能排除共同模式错误。
- 这批问题的共同特征：都发生在**错误处理路径**。对成熟编译器，正向路径已经很难打穿，错误恢复/诊断渲染才是薄弱面。
- **覆盖率的结论修正了投入方向**：`syncheck` 阶段的可达边集在 200 个真实种子后基本饱和（AFL 跑 3,885 次执行 0 新边；随机变异只打平种子），同样 40 个输入换到 `build-package`，边覆盖 +47%、`Moonc.*` 函数覆盖 +121%（6.8% → 15.1%）。继续在 parser 上堆执行次数是低效的，预算应该转向 T2/T3 和配置解析器。
- 同时也要承认：本轮 300 万次执行里，绝大多数打在已经饱和的 T1 上；F3（OOM）和 F1（SEGV）都是这样"撞"出来的边缘案例，说明**饱和不等于没有 bug**，但再往上提发现率需要换目标而不是加量。

## 6. 后续可做（按数据排的优先级，2026-11-11 更新）

0. **补齐入口（已完成）**：`check` / `build` / `test` / `link-core` 四入口并集
   7,097 = 26.7%；`test ⊃ build`，`link` 纯增量 +1,154。用
   `moon <cmd> --dry-run -v` + `harness/replay.py` 重放，别再手拼 `-i`。
1. **类型多样性（首要假设，未证伪）**：按函数数 `check` 占 `build` 的 85%；两个命令负载的
   TB 总数是 68.4M vs 71.5M（95.6%），但这不是严格阶段分解（TB 指令成本不同、chaining 会影响
   计数），只能说明 build 相对 check 的增量不大。换 target（wasm vs wasm-gc，+0.9%）和换编译模型
   （整包 vs 单文件，5,753 vs 5,734）都不改变结论；真语料净效应只有 +2.5pp，
   并集 22.3% 并已饱和（贪心 232 个输入打满）。所以下一步是 **`.mbti` 类型 oracle +
   泛型/trait 实例化矩阵**——但它仍是假设，得靠新类型组合的输入来验。
2. ~~接受型变异自举接进主循环~~ —— **实测是空操作，不做**：gen0 − seeds = 0、
   gen1 − seeds = 0 个新函数，且并集 4,636 → 3,904、每输入均值 1,217 → 1,134 → 1,041
   逐代收窄。71.7% 的可运行率买不到任何覆盖。
3. **变异要换作用面，不是加变异子**：现在的 16 个变异子全在文本层（token/块/字面量/
   词典），没有泛型实参、trait impl、数值宽度、`.mbti` 签名。诊断类实验也佐证：
   29 个新类里 12 个是纯语法、3 个是改名未绑定，只有 9 个碰到类型轴，且都是错误路径。
   接受判据必须从"能编译"换成"**新函数**或**类型轴新诊断**"。
4. **词典：证据只支持"替换"，但不支持它加深覆盖**。插入式把 parse 从 36.2% 压到
   30.5%（负收益）；替换式 85.8%，可 T2 编译率反降到 18.7%。它买的是命名多样性，
   **没有任何"新函数"证据**，降为低优先级。
5. **差分 oracle 扩后端**：wasm / wasm-gc / js / native + `moonrun` 比对（误编译仍为 0），
   优先补 wasm-gc 特有语义、native 的 Int/Float、try/raise 跨后端。
6. **配置解析器继续加码**：`moon.pkg` 90 秒出 SIGSEGV，单位时间收益最高。
7. **覆盖率回归**：固定 pilot 语料，每次工具链升级 diff 函数集合（只做函数级，边级不可比）。

### 6.1 语义一致性 campaign（2026-11-12，codex 监督下完成）

七个语义族、四个后端、**27,095 例/事件**、独立参考实现、每族注入故障验证 oracle：

| 族 | 例数 | 差异 |
|---|---:|---:|
| Int32 溢出/移位 | 3,600 | 0 |
| Double 位级 | 4,000 | 0 |
| 可变引用别名 | 2,400 | 0 |
| Int32 复合表达式 | 2,200 | 0 |
| Double 复合表达式 | 3,200 | 0 |
| 异常语义 | 9,695 | 0 |
| Unicode | 2,000 | 0 |

codex 裁决：**"This bounded semantic campaign is complete… You should stop expanding this campaign."**
（有界证据，不是编译器正确性证明）。详见 `findings/semantics.md`、`findings/codex_supervision.md`。

### 6.1.1 类型导向生成的负结果（2026-11-12）

按 codex 建议做了 6 个形状 × 240 个程序：应通过 160/160（100%）、应报错 80/80（100%），
但对既有 7,916 个函数的并集**新增 0**。按其放弃线（<50 新函数且无新诊断类）**停止扩展**。
详见 `findings/typegen.md`。

### 6.1.2 语法边界 campaign（codex option 2，2026-11-12）

按 codex 的三选一方案做了 option ②：**语法边界重建 + 边界变异 + 资源缩放 + formatter 往返**。
harness `harness/syntax_boundary.py`，详见 `findings/syntax_boundary.md`。

- **A 边界变异**：12 个合法基座（优先级、换行/分号、插值、模式、嵌套分隔符、转义、泛型、
  循环、lambda、pipe、标签参数、嵌套 match），19,935 个单/多 token 变异，`syncheck` 5 s 超时 +
  4 GiB 地址空间上限 + 每子进程 `wait4` 峰值 RSS：
  **0 ICE / 0 crash / 0 timeout / 0 静默失败**；最大 126 ms、42,488 KiB（41.5 MiB）；2.34% 仍可解析，
  且可解析集中的系统性项都能解释（前缀 `+`、`..` range、字符串里的 `\`）。
- **B 资源缩放**：9 个边界维度，8 个测到 k=4096（match arms 到 512），`syncheck` 在测试区间
  无可观测超线性（8–19 ms、17.4 MB，另用 `/usr/bin/time -v` 交叉验证）；`moonfmt` 在
  **字符串插值**上每翻倍 k 约 **10–12×**（k=512 129 ms → 1024 1.59 s → 2048 15.2 s →
  4096 >25 s 超时），固定宽度段同样爆炸（排除位数因素）、输出体积线性、CPU-bound，
  普通长串 6 ms、拼接 7–18 ms。
  端到端 `moon fmt`：6 KB 源 1.56 s、13 KB 源 15.13 s（P1）。
- **C formatter 往返**：467 个可解析变异体，fmt 全部退出 0 且幂等，424 个输出可再解析；
  43 个失败**全部**是同一签名 `E3001 unrecognized character "~"`，根因是解析器把前缀 `+`
  脱糖成内部标识符 `~+`，formatter 忠实打印后无法词法回读（F5）。真实语料
  `seeds_real` **662/662** 全部 fmt→reparse 成功；12 个基座 `moon fmt` 前后 `moon run`
  输出 **12/12 一致**。

结论：parser 在测试区间内既没有新崩溃类，也没有超线性；新发现是 1 个低危工具/诊断缺陷（F5）
和 1 个 formatter 复杂度异常（P1），都不是 miscompile。**原始停止线未严格满足**（不足 20,000 例、
出现 1 个新缺陷类与 1 个缩放异常，且未测"<20 新函数"；最后一个新诊断模板在第 19,521 例）。
按 codex 复审意见，本轮记为 **"bounded campaign completed; two findings triaged"**，并采纳
按"缺陷签名"计的族级停止规则。随后按 gate 跑了 option ③（负结果，见 §6.1.3），再按复审
给出的 oracle 跑了接口一致性 pilot（负结果，见 §6.1.4）；campaign 到此关闭，不自动滚到
`gen-test-info` 元数据测试。

### 6.1.3 老编译器差分 pilot（codex option 3）——负结果

按 codex 的 gate 装 OCaml 4.14.1 / findlib 1.9.6 / dune 3.24（系统 apt 只有 4.13.1 和
dune 2.9，旧编译器需要 `In_channel`），`dune build -p moonbit-lang` 干净通过（~6 min，
无源码修补），二进制 `v0.1.20250312+a7a1e9804`。Calibration 68 条共享语言控制
（47 accept / 21 reject）**68/68** 双端符合预期；差分 3,500 条记录（1,159 个不同源文本，
2,000 + 1,500 扩宽版）**零分歧**（1,587 同接受 / 1,913 同拒绝 / 0 NEW_ACCEPT /
0 NEW_REJECT / 0 NEW_CRASH）。唯一观察到的差异都是漂移：旧版一元 `-`/`!` 需显式
`core/int`/`core/bool`、泛型语法 `fn id[T]` vs `fn[T] id`、optional 参数语义、
`priv fn` 不是共享形式、`abort`/`Int?` 需 prelude。该 tag 没有可用的旧 core `.mi`
bundle（**未找到**），共享子集只能是 builtin-only，因此按 codex 的放弃线提前关闭
（结构性限制，不是 4 小时时钟）。详见 `findings/oldcompiler_pilot.md`。

### 6.1.4 接口一致性 pilot（codex fallback）——负结果 + 一个工具方言观察

Oracle：`build-package` 生成 P.mi → `mooninfo -format text` 导出文本接口 →
`build-interface` 重建 P2.mi → 同一批 client 分别对两个 `.mi` 做 `moon check`，
要求接受/拒绝一致；并用“改签名 arity”故障对照证明 oracle 不是盲的。

- Setup + 故障对照：**PASS**（15 min，远低于 30 min gate）。
- 150 个包（30 个 opaque-type 包）、2,278 个 client 检查：**880 同接受 / 1,398 同拒绝 /
  0 mismatch / 0 crash / 0 接口文本差异**。
- 观察（未定性为缺陷）：`mooninfo` 对 opaque 公共类型输出
  `pub struct S { // private fields }`，`build-interface` 直接拒绝（E4032 + E4157）；
  手工归一化成顶层 `type S` 后 rc=0 且 client 行为一致（30/30 包都需要）。
  这是两个工具的文本方言不一致，是否算 bug 取决于未文档化的预期工作流，故只记为观察。
- 按 codex 的 2 小时放弃线关闭，未自动滚到 `gen-test-info`。详见
  `findings/interface_pilot.md`。

### 6.1.5 补充探针（2026-11-12）：三个负结果

按 codex review 4 的排序，先做了三个最便宜的探针，全部为有界负结果，**未新增缺陷**
（详见 `findings/probes_2026-11-12.md`）：

- **Printer 全构造往返**：43 个最小构造（async/await、try/catch、defer、impl with、
  trait impl、type alias、extern、is/guard、数组/范围/or-pattern、属性、doc/test 等），
  `fmt` 全部 rc=0、输出全部可再解析、幂等、无内部 `~+` 泄漏、无括号丢失。只观察到
  `defer {e}`→`defer e`、`try {e} catch`→`e catch`、`y? : T = 1`→`y~ : T = 1` 这类
  可再解析的规范化；optional 改写后用 `moon run` 验证 `f(x=1)` 行为不变。
- **20 维缩放**：19 个新维度 × k=4…512 + 插值对照；`syncheck` 翻倍比 1.2–1.8×，
  `moonfmt` 1.3–2.1×，只有插值 **10.5×**（复现 P1）；无失败/超时。nested match/try
  的 fmt 时间随输出体积（缩进）增长，属输出驱动，不算算法异常。
- **配置/文档解析器**：`moon.pkg`（直接作为输入）/`.mbt.md`/`.mbti` 共 **14,000** 个
  变异，0 ICE / 0 crash / 0 timeout / 0 静默失败；诊断停留在 `E4192`/`E3002`/`E3001`/
  `E3100`。种子是合法配置的变异，因此不声称复现 F1/F4 的特定崩溃形状。

结论：printer、20 维缩放、配置变异三条假设已关闭，不要在没有新假设时重复；剩余
概率质量在 codex 排序的 baseline 对比、第三方 mooncakes 包（外部有效性/miscompile）
和缺陷/oracle 验证上。

### 6.1.6 论文级证据包（2026-11-12）

汇总入口：`findings/evidence_package.md`。核心结果：

- **Coverage headline（冻结）**：7,916 / 26,611 `camlMoonc*` = **29.75%**；并集来源
  （7,097/7,412/7,591/7,660/7,847/7,916）逐一定义；符号化审计 51.2M PC 仅 0.003% gap
  且全是 CRT，`camlMoonc` 归因 0 差异；check 299/299、build 130/130 rc=0。
- **缺陷 5× 验证**（`findings/validation.md`）：F1 5/5 SIGSEGV；F2 5/5 ICE；F3 5/5
  达 5.2–5.7 GiB（6 GiB cap）；F4 5/5 rc=199；F5 5/5（parse 0 / check 2 / fmt+reparse 2）；
  F6 5/5 native export/link ICE（模块级 build 同样失败；另缩到 12 行单包复现）；P1 5-run 中位 1,576 ms（k=1024）、15,072 ms（k=2048），
  纯串对照 7.5/6.2 ms。
- **第三方外部有效性**（`findings/thirdparty.md`）：12 个 mooncakes 包 × 5 target =
  **60/60 rc=0**；跨后端测试 **3,503/3,503 pass（wasm/wasm-gc/js）**；native
  发现 **F6**（导出含闭包类型时 ICE，5/5；后缩到 12 行单包）+ 若干包/环境问题（已逐个 triage）。
  build-package 覆盖并集 4,455（16.74%），对冻结基线仅 **+42**
  （7,958 = 29.90%，trace 128 MiB 截断，故为下界）；旧包测试受 core API 漂移阻塞。
- **Baseline（回顾性，非受控）**：结构/包 campaign 608,257 exec/300 s/96 worker（T2 30.8%、
  T3 1.5%）vs AFL 13,320 exec/300 s/8 实例（+760 边，+1.8%）；100 输入抽样覆盖 16.8% vs
  12.1%。**不声称对 AFL 的一般优势**；受控 4 臂 × 2 层 × 20×6 h 对比列为 future work。
- **Bounded negatives**：语义 27,095/0 差异；边界 19,935/0 异常；类型生成 +0；旧编译器
  3,500/0 分歧；接口 2,278/0 mismatch；printer 43/0；20 维缩放仅 P1；配置 14,000/0。
- **Threats to validity** 单列：分母（含 8,038 匿名闭包 + 4,200 Menhir 动作）、归因仅 17%、
  replay 截断/丢失、阶段归因、有限语料饱和、快照漂移、单位混用、根因独立性。

结论口径：**validated black-box robustness + bounded semantic testing**，不声称编译器
正确性、codegen 成熟度、或“剩余函数大多不可达”。

### 6.2 外部 review 流程（约定）

遇到"方向拿不准 / 数字要被人挑错"的节点，走一次外部 review：

```bash
cat prompt.txt | HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 \
  codex exec -s read-only -C /data/audit/mbtfuzz --skip-git-repo-check -
```

prompt 里**必须自带实测数字和裁决规则**（否则它会给通用建议）；拿到意见后
**逐条验证**，验证结果写进 `findings/codex_review_N.md`——包括被证伪的条目。
第 1 次：`findings/codex_review_1.md`（两条代码指控成立并已修，优化等级假设
实测 +302 通过）。第 2 次：`findings/codex_review_2.md`（18 条修正意见逐条复核：
17 条成立、1 条部分成立；F5/P1 定级与停止线按复审改写）。第 3 次：
`findings/codex_review_3.md`（旧编译器 pilot 放弃 + 接口 pilot 的 oracle/停止线；
9 条数字与措辞修正全部复核，含 calib 47/21、1,159 个不同源文本、88 条重复绑定样本）。
第 4 次：`findings/codex_review_4.md`（覆盖口径与论文级证据路线；12 条事实指控逐条复核，
7,660/7,847/7,916 并集来源已精确对齐，符号化误差 0.003% 且不影响 `camlMoonc` 归因）。

## 7. 目录结构

```
mbtfuzz/
├── README.md                 # 本文
├── harness/
│   ├── mbtfuzz.py            # fuzz 引擎（6 种输入模式 + 三层流水线 + oracle）
│   ├── mutate.py             # 16 种结构感知变异子
│   ├── cov.py                # 覆盖率测量（edges: AFL++ QEMU / funcs: qemu trace+nm）
│   ├── symbolize.py          # PC → moonc 函数（nm 符号表，non-PIE）
│   ├── gen_random.py         # 随机变异语料生成（消融实验用）
│   ├── difftpl.py            # 差分流水线：模板 + body 变异 + 可运行门槛 + 分类
│   ├── realcorpus.py         # 真程序语料：core 全量编译 / 整包 / 体变异自举
│   ├── diag.py               # 诊断类聚类（D 层，新类率当 fitness）
│   ├── order.py              # 增长曲线：路径/大小/随机/包轮转/贪心序
│   ├── replay.py             # 重放 moon --dry-run 的真实命令（多入口覆盖）
│   ├── syntax_boundary.py    # 语法边界变异 + 时间/RSS 缩放 + formatter 往返
│   ├── olddiff.py            # 2025-03 旧 moonc vs 当前 moonc 前端差分
│   ├── iface.py              # build-interface 往返 + client 接受性差分
│   ├── mkdict.py             # 从 .mbti 抽 1,177 个 token
│   ├── moonbit.dict          # AFL 词典（替换式使用）
│   ├── afl_syncheck.sh       # AFL 参考命令（注意：不要用它包装，会毁覆盖率，见 3.4）
│   ├── all_pkgs.json         # moonc 需要的包索引（moon 生成）
│   ├── moon.pkg              # 模板包配置
│   └── tpl/                  # 生成 all_pkgs.json 的模板工程
├── templates/                # 25 个确定性差分模板（int/float/string/trait/trap…）
├── seeds/                    # 1540 个 .mbt + 82 .mbt.md + 140 .mbti（来自 moonbitlang/core）
├── harness/cov_audit.py      # 覆盖测量审计（符号区间/复现性）
├── harness/replay_outcomes.py# 回放 rc/stderr 审计
├── moonbit/                  # MoonBit 主路径：trace/cov/mutate/exec/corpus/oracle + cmd/*（§9）；含 accept 门禁与 F6 矩阵
├── poc/                      # F1-F6 + F1b/F2b/F4b/F6-min 最小复现
├── findings/
│   ├── F1_moon_pkg_parse_segv.md
│   ├── F2_lex_escape_ice.md
│   ├── F3_parser_oom_dos.md
│   ├── F4_invalid_utf8_ice.md
│   ├── coverage.md           # 覆盖率的定义、测量、实验（重点，§8 是口径修订）
│   ├── real_corpus.md        # 真程序语料：可运行率 44.9%、21.5%、墙在 typer
│   ├── diagnostics.md        # 诊断类覆盖（D 层）
│   ├── entrances.md          # 四入口并集 26.7%：check/build/test/link-core
│   ├── snapshot.md           # 版本与语料指纹（换版本必须重测）
│   ├── codex_review_1.md     # 外部 review #1 与逐条验证
│   ├── codex_review_2.md     # option ② 复审：F5/P1、停止线、18 条修正
│   ├── codex_review_3.md     # 旧编译器/接口 pilot 复审与 9 条修正
│   ├── codex_review_4.md     # 覆盖口径/论文级结果路线与逐条验证
│   ├── codex_review_5.md     # MoonBit 迁移架构/新缺陷面 review 与修正
│   ├── migration_moonbit.md  # Python->MoonBit 迁移证据与验收
│   ├── f6_moonbit_fixture.md # F6 第三方复验 + 12 行最小复现 + 边界矩阵
│   ├── cov_audit.md          # 符号化/回放/并集口径审计
│   ├── probes_2026-11-12.md  # printer/20 维缩放/配置变异：三个负结果
│   ├── evidence_package.md   # 论文级证据包（口径/验证/威胁/声明边界）
│   ├── validation.md         # F1–F5/P1 5× 复现表
│   ├── thirdparty.md         # 12 包 × 5 后端 + 3,503 测试 + F6 外部有效性
│   ├── syntax_boundary.md    # F5 + P1：19,935 变异、缩放、formatter 往返
│   ├── oldcompiler_pilot.md  # option ③ 负结果（3,500 记录零分歧）
│   ├── interface_pilot.md    # 接口往返负结果（2,278 client 零 mismatch）
│   ├── semantics.md          # 7 族语义差分（27,095 例，0 差异）
│   ├── typegen.md            # 类型导向生成负结果
│   ├── diff_pipeline.md      # 差分流水线：0% → 71.8% 可运行率、D1
│   └── diffs/D1_int_min_div.md
│   └── evidence_compiler_repo.md
├── logs/                     # 长跑日志
└── out/
    ├── findings/             # 原始崩溃样本 + stderr + meta
    ├── cov_*.json            # 覆盖率原始数据（edges/funcs）
    └── sigs/ corpus/ stats/  # 行为签名、语料、统计
```

## 9. MoonBit 主语言迁移（2026-11-13）

### 9.1 状态

默认执行路径已切到 MoonBit 模块 `moonbit/`：覆盖率函数集、集合代数、变异器、
T1/T2 战役、wasm/js 与 wasm/native 差分、字节级变异、12 例缺陷回归，均由
MoonBit 二进制完成，不再 import Python。Python 只保留三类职责：

1. 独立参考实现（`trace2funcs` / 集合代数的对拍、`symbolize.py` 金标准）；
2. 已归档的分析 pilot（`syntax_boundary`、`olddiff`、`iface`、`typegen`）；
3. 统计/绘图/历史实验（非默认路径）。

验证入口：

```bash
cd moonbit
moon test --target native          # 50 tests
moon run cmd/accept --target native -- /data/audit/mbtfuzz
```

`cmd/accept` 的 10 个硬门：工具链 pin、`moon build`、`moon test`、`moon check`、12 例缺陷回归、
合成 trace 精确 JSON、真实 F4 trace 的 599 函数集对 Python 金标准、覆盖并集、
25 个可运行模板在 wasm/js 都到 `run` 且输出一致。任一门失败即非零退出。

### 9.2 对拍数字

| 项 | Python | MoonBit | 结果 |
|---|---:|---:|---|
| 101 MB check trace -> 函数集 | 1,864 / 1.80 s | 1,864 / 0.48 s | 集合完全相等，~4x |
| build trace | 1,354 / 1.67 s | 1,354 / 0.44 s | 集合完全相等 |
| invalid-UTF8 trace | 599 / 0.44 s | 599 / 0.15 s | 集合完全相等 |
| 覆盖并集（两份快照） | 6,547 | 6,547 | 相等 |
| 25 个模板 wasm vs js | — | 25/25 `same=true` | 都到 `run` |
| 缺陷回归 | 5x/项 | 12/12 | 全部可复现 |

### 9.3 新发现（均暂归入既有根因，不声称新类）

- **F1b**：第二个畸形 `moon.pkg` SIGSEGV 触发，672 B，栈顶与 F1 相同
  （`next_segment_head` / `report_failed_to_parse`）。`poc/f1b_pkg_map_segv/`。
- **F2b**：`\` + U+200B 被 `syncheck` 接受，`build-package` ICE
  `Invalid_argument("Char.chr")`。`poc/f2b_zwsp_escape_t2_ice/`。
- **F4b**：字节级 fuzz 得到的第二个 invalid-UTF8 `.mbt.md`
  （`Basic_utf8_decode.MalFormed`）。`poc/f4b_invalid_utf8_2/`。
- **F6-min**：F6 从 12 MB 第三方包缩到 **12 行单包**
  （`foreign_library` + `#export_name` 函数 + 闭包字段），
  `moon build --target native` 即复现；这确认了触发条件，也把 F6 从
  “第三方外部有效性”提升为可独立回归的最小例。`poc/f6_native_export_closure_min/`。

### 9.4 战役计数与边界

MoonBit 驱动跑过：mbt 126,497 iter / 20,958 T2 / 0 crash；`moon.pkg` 223,043
iter / 799 个重复 SIG（1 个唯一 witness）；`.mbt.md` 83,317 / 0；`.mbti`
111,707 / 0；`moon.mod` 139,934 / 0；模板差分 77,638 iter / 17,084 T2，只有
F2b 一个唯一 ICE；formatter 往返/幂等 27 万+ T1-OK，0 新。字节 fuzz 找到 F4b。

这些是**重复次数**，不是 27 万个不同语义测试。当前仍不能声称：新的根因类、
编译器正确性、代码生成成熟度、行/分支覆盖、或“剩余函数不可达”。覆盖口径仍是
`camlMoonc*` 符号级 7,916 / 26,611 = 29.75%，不是可行代码覆盖。

### 9.5 迁移完成度

“主语言”按**默认路径**而不是 LOC 百分比定义：默认的覆盖测量、变异、T1/T2
战役、回归、差分都由 MoonBit 入口执行，且 `cmd/accept` 能在无 Python 的情况下
判定通过。尚未迁移的是归档 pilot 与绘图；它们不影响默认结论，保留 Python 作为
独立参考反而能降低 MoonBit 生成器/ oracle 的共同模式错误风险。

完整模块说明见 `moonbit/README.mbt.md`。
