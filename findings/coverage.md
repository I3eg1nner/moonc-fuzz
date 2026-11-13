# 覆盖率：定义、测量与实验（修订版）

> 回答一个问题：**对闭源的 `moonc`，"覆盖率"到底怎么定义、怎么量、量出来说明了什么。**
>
> 本版修正了一个关键方法论错误：AFL++ QEMU 新版默认的边 id 是**进程内递增序号**，跨进程不可比；第一版用它算语料并集，数字是虚的。下面把两种口径分开，并给出修正后的数据。

---

## 1. 形式定义

一次执行（`moonc` 处理一个输入的一个进程）产生基本块轨迹

```
T(P) = b0, b1, ..., bn
E(P) = { (b_i, b_{i+1}) | 0 ≤ i < n }
E(C) = ⋃_{P∈C} E(P)                    # 语料 C 的边并集
Cov(C) = |E(C) ∩ E*| / |E*|            # E* = 该二进制所有可行执行的边集
```

`E*` 不可精确判定（间接调用、异常、OCaml 闭包/尾调用让静态 CFG 不完整），所以**任何百分比都必须声明分母**。

插桩把边映射到 bitmap：

```
h : E → {0, …, 2^k − 1}      M[h(e)] += 1
```

`h` 是哈希/编号 ⇒ 要么有碰撞，要么跨运行不稳定。这是下面所有口径问题的根源。

什么**不是**覆盖率：我们第一版用的 `sig(P) = (stage, exit_class, 诊断码集合, toplevel JSON)` 是 **oracle 分区多样性**（行为签名），用于语料去重，与"执行了哪些代码"没有函数关系。

---

## 2. 两种 QEMU 插桩口径（必须先分清）

读 `qemu_mode/qemuafl/accel/tcg/translate-all.c` 可以确认存在两条路径：

| | 默认（AFL++ ≥4 新版） | `AFL_QEMU_OLD_COVERAGE=1` |
|---|---|---|
| 代码路径 | `afl_maybe_log_cf` + 哈希表 `(src_pc,dst_pc)→id` | `afl_maybe_log`：`idx = hash(pc) ^ (prev>>1)` |
| id 来源 | 首次见到该边时 `next_id++`（5,6,7…，实测连续无空洞） | 对 PC 做固定哈希后取低 16 位 |
| **跨进程可比** | **否**：同一跨函数边在不同进程可能拿到不同 id | **是**：同一 (src,dst) 恒定 |
| 碰撞 | 基本无（id 上限 `map_size−5`，超出才回绕） | 有（16 位哈希，密度高时严重） |
| 适用 | **单次 campaign 内的在线引导**（AFL 自己用） | **离线语料/跨运行的并集比较** |

**规则**：
- 用 `afl-fuzz` 跑引导 → 默认口径，AFL 内部统计（`edges_found`）有效；
- 用 `afl-showmap` 批量测语料 → **必须加 `AFL_QEMU_OLD_COVERAGE=1`**，否则每次 showmap 都是新进程、id 重新按翻译顺序分配，并集没有意义；
- 两种口径的数字**不能混在一张表里比较**（AFL 报 71,902 ≠ 我们离线量的 44,064，不是"少了"，是两把尺子）。

`cov.py` 用 `--old-cov` 切换。

---

## 3. 实现

### 3.1 边覆盖（离线、稳定口径）

```bash
python3 harness/cov.py edges <corpus_dir> --limit 300 --workers 64 --old-cov --out out/cov_X.json
# 内部：afl-showmap -Q -q -o map.txt -- moonc syncheck -error-format json in.mbt
#       env: AFL_QEMU_OLD_COVERAGE=1, 每输入独立进程（不要用 -i 批量，-Q 下会串）
```

输出：`union_slots`、`per_input_new`、`cumulative`、`density`。

### 3.2 函数覆盖（稳定、无碰撞）

```bash
python3 harness/cov.py funcs <corpus_dir> --limit 100 --workers 48 --stage build --append-main --out out/cov_funcs_X.json
# 内部：afl-qemu-trace -d exec -D log -- moonc build-package in.mbt ...
#      解析 guest PC → nm 符号表 → 函数
```

- `moonc` 是 `ET_EXEC`（非 PIE），运行时地址 == 符号地址；
- **只接受 `0x400000..0x12170a0` 的 PC**：trace 里还有 `0x4000_0000_0000+` 的动态库区，机械减基址会"恰好"落进 `.text` 查到假符号；
- 分母：`nm` 里 `T/t` 符号 30,576 个，其中 `camlMoonc*` 26,611 个；
- OCaml 生成代码无 `.debug_line`，**函数级就是下限**，行级不可得。

函数覆盖是最好的跨语料指标：精确、稳定、无碰撞，代价是 ~1 s/输入（只能抽样）。

### 3.3 语料最小化

```bash
python3 harness/cov.py edges out/corpus --limit 300 --old-cov --minimize /tmp/min
```
贪心集覆盖，输出"覆盖同样并集的最小子集"。

---

## 4. 实测数据（全部为稳定口径，map=65536）

### 4.1 边覆盖

> ⚠️ 本节及 §4.3 的边数字用默认 QEMU 口径测的，**已作废**，保留仅为记录过程；
> 权威口径见 §8（函数覆盖）。

| 语料 / 阶段 | 输入数 | 边槽（并集） | 利用率 |
|---|---:|---:|---:|
| seeds（core 库）· T1 | 200 | 32,255 | 49.2% |
| 随机变异 1000 个 · T1 | 1000 | 31,728 | 48.4% |
| fuzz 语料 · T1 | 300 | 35,281 | 53.8% |
| seeds40 · T1 | 40 | 30,251 | 46.2% |
| **seeds40 · T2** | 40 | **44,599** | **68.1%** |
| seeds120 · T2 | 120 | 43,304 | 66.1% |
| **AFL 队列（248）· T2** | 248 | **44,064** | 67.2% |

### 4.2 函数覆盖（`Moonc.*` / 26,611）

| 语料 / 阶段 | 输入数 | 函数 | `Moonc.*` | 占比 |
|---|---:|---:|---:|---:|
| seeds · T1 | 100 | 2,456 | 1,969 | 7.4% |
| 随机变异 · T1 | 1000 | 1,854 | 1,369 | 5.1% |
| **seeds · T2** | 100 | 4,100 | 3,503 | **13.2%** |
| **AFL 队列 · T2** | 100 | 3,807 | 3,207 | 12.1% |
| **本项目 T2 语料 · T2** | 100 | **5,089** | **4,474** | **16.8%** |

读法：
1. **T2 比 T1 深一倍**：边 +47%，函数 +78%（3,503 vs 1,969）。
2. **随机变异在 T1 只是"打平"**（31,728 vs 32,255），不是更差——第一版说"随机导致覆盖下降"是 id 不稳定造成的假象，撤回。
3. **T2 上我们的语料最深**：同样取 100 个输入，`Moonc.*` 4,474 vs 种子 3,503 vs AFL 队列 3,207。原因是"只改函数体"的变异保住了顶层结构，能穿过后端。

### 4.3 语料最小化

| 语料 | 输入数 | 最小等价集 | 压缩比 |
|---|---:|---:|---:|
| fuzz 语料 300 | 300 | **165** | 1.8× |

第一版说"300 → 1"是错的（同样是 id 不稳定造成的：大文件的 id 恰好覆盖了别人的 id）。修正后：**T1 的边覆盖能区分输入，但区分度有限**——300 个里有 165 个对并集有独立贡献。

---

## 5. 消融实验

同一批 200 个种子、同一命令、同一机器：

| 组 | 执行数 | 边并集（稳定口径） | 函数（T1） |
|---|---:|---:|---:|
| 仅种子 | 200 | 32,255 | 1,969（100 个） |
| 随机变异（全保留） | 1000 | 31,728 | 1,369（1000 个） |
| AFL++ 覆盖引导（T1） | 801–3,885 | **0 条新边**（`edges_found` 卡在 21,704） | — |
| AFL++ 覆盖引导（T2，8 实例 ×300 s） | 13,320 | 队列比种子 +760 边（+1.8%） | 3,207 vs 3,503（种子） |

结论：
- **T1 上引导无收益**：种子多样性已经把 parser 边集铺满，AFL 3,885 次执行没找到新边。这不是工具坏了，是目标饱和了。
- **T2 上引导开始有收益**（+1.8% 边），但**单位执行成本高**（13.3 exec/s/核 vs 原生 55/s/核），300 秒 8 实例只多 760 条边。
- **同等预算下，结构保持变异 + 行为签名语料更划算**：608k 次执行（96 worker × 300 s ≈ 2,030 exec/s，其中 187k 次进 T2）产出 100 个样本，`Moonc.*` 覆盖 16.8%，高于 AFL 队列的 12.1%。

---

## 6. 工程坑（实测）

| 坑 | 现象 | 解法 |
|----|------|------|
| 跨进程 id 不可比 | 并集虚高/虚低，最小化退化到 1 个文件 | `AFL_QEMU_OLD_COVERAGE=1` 再算并集 |
| QEMU map 固定 65536 | `AFL_MAP_SIZE` 无效 | 用 `AFL_QEMU_MAP_SIZE`；但 old 模式仍是 16 位哈希 |
| bash 包装毁覆盖率 | `-- bash wrapper.sh @@` 只覆盖 bash（3,254 vs 25,143 槽） | 直接以 `moonc` 为目标 |
| 符号化假阳性 | `0x4000…` 区间减基址"恰好"落进 `.text` | 只接受 `< 0x2000000` 的 PC |
| `/dev/shm` 64 MB | worker 目录写满 → showmap 静默失败 → 覆盖全 0 | 工作目录放 `/tmp` |
| `AFL_CRASH_EXITCODE` 范围 | 199 被拒 | 跑完回放队列筛 ICE |
| OCaml 无 `.debug_line` | `addr2line` 全 `??:?` | 函数级是下限 |

---

## 7. 文献对照

| 工作 | 覆盖粒度 | 对我们的启示 |
|------|----------|--------------|
| AFL 白皮书 / AFL++ | 边 + 命中计数分桶 | 我们的边口径；`(edge,bucket)` ≠ edge，要分开报 |
| CollAFL (S&P'18) | 路径敏感边标识 | 碰撞影响探索；稳定口径下 67% 密度必须说明碰撞偏差 |
| CSmith (PLDI'11) | 不用覆盖反馈 | 语法驱动 + 差分 oracle 本身能出活 |
| EMI (PLDI'14) | 被测程序行覆盖 | 覆盖用于挑"没跑到的地方"再蜕变，比"用覆盖选语料"更贴切 |
| ClassFuzz (PLDI'16) | 参考实现覆盖唯一性 | 覆盖引导选择 + 多实现差分 |
| Survey (CSUR'20) | — | 覆盖与 oracle 正交，分开报告 |
| Marcozzi (OOPSLA'19) | — | finding 要做 triage，bug 数 ≠ 影响 |
| wasm-smith | libFuzzer 边覆盖 | 结构感知生成 + 多引擎差分，可用于 `moonrun`/`link-core` |

---

## 8. 报告口径（以后按这个写）

```
被测对象：moonc <subcommand>，v0.10.20+65efd5b93，ET_EXEC（非 PIE）
插桩：AFL++ QEMU，口径=<稳定哈希 / 进程内序号>，MAP_SIZE=<...>
      注明：跨运行比较只用稳定口径
语料：C，U(C)=|⋃E(P)|（稳定口径）
分母：E_ref=<pilot 并集|插桩边总数>，采集时间<...>
报告：U、密度、稳定性、edges/exec、每万次新边、
      函数覆盖（含 Moonc.* 子集）、碰撞估计
缺陷侧：unique crash / ICE / hang，每 CPU 小时，triage 结论
```

**禁止**：拿语料并集当分母；把诊断码种类叫覆盖率；混用两种口径的数字；只报累计值。

---

## 9. 下一步

1. **T2 继续挖**：AFL T2 只跑 300 s/实例，且 13.3 exec/s/核；换 32 实例、跑 1 小时，看 +760 边能涨到多少。
2. **差分 oracle**：wasm/wasm-gc/js/native 四后端比对，补"误编译"这一整类空白。
3. **结构化生成**：从二进制 dump 的 379 个 Menhir 产生式反推文法，做"永远能过 parser"的生成器。
4. **覆盖率回归**：固定 pilot 语料，每次升级后比较函数集合差异。

---

## 参考文献

1. AFL 技术白皮书 — https://github.com/google/AFL/blob/master/docs/technical_details.txt
2. AFL++ 文档 — https://github.com/AFLplusplus/AFLplusplus/blob/stable/docs/fuzzing_in_depth.md
3. AFL++ QEMU 模式 — https://github.com/AFLplusplus/AFLplusplus/blob/stable/qemu_mode/README.md
4. S. Gan et al., *CollAFL: Path Sensitive Fuzzing*, IEEE S&P 2018, DOI 10.1109/SP.2018.00040
5. X. Yang et al., *Finding and Understanding Bugs in C Compilers*, PLDI 2011, DOI 10.1145/1993498.1993532
6. V. Le et al., *Compiler Validation via Equivalence Modulo Inputs*, PLDI 2014, DOI 10.1145/2594291.2594334
7. Y. Chen et al., *Coverage-Directed Differential Testing of JVM Implementations*, PLDI 2016, DOI 10.1145/2908080.2908095
8. J. Chen et al., *A Survey of Compiler Testing*, ACM CSUR 53(1), 2020, DOI 10.1145/3363562
9. M. Marcozzi et al., *Compiler Fuzzing: How Much Does It Matter?*, PACMPL 3(OOPSLA), 2019, DOI 10.1145/3360581
10. wasm-smith — https://github.com/bytecodealliance/wasm-tools/blob/main/crates/wasm-smith/README.md

---

## 8. 2026-11-11 修订：§4.1 的「边占比」全部作废

用 `--dump-slots` 把每个输入的槽集合落盘后可以直接验证 id 的性质：

```
默认口径 union_slots = {5, 6, …, N}      # 实测 max−min+1 == len(union)，连续
old-cov   union_slots 非连续，max ≤ 65534
```

原因在 `afl_idtable_lookup`：id = `next_id % (map_size−5) + 5`，**按翻译顺序递增**。
不同进程各自从 5 开始，所以跨进程并集只是「最大单输入的那一段」，不是并集。
§4.1 里 46.2% / 68.1% / 66.1% / 67.2% 这些数字都是这么来的，**作废**；
§4.3 的「300 → 165」压缩比也建立在同一错误上，同样作废。

**以后的口径**：

* 跨语料比较 → 只用**函数覆盖**（nm 符号化，无哈希，分母 26,611 明确）；
* 边数 → 只在「单输入/单进程」意义下引用（精确，无碰撞）；
* 必须用边做跨进程比较时 → `AFL_QEMU_OLD_COVERAGE=1`，并且必须报
  「观测槽位数 + 生日校正后的边数估计」（本语料：50,388 槽 → ≈9.6 万边）。

### 修订后的函数覆盖表（唯一权威口径）

| 语料 | 输入数 | `Moonc.*` / 26,611 |
|---|---:|---:|
| 单文件 syncheck（T1） | 1 | ~1,000 |
| T1 种子 | 100 | 1,969（7.4%） |
| T2 混合语料（旧口径最优） | 293 | 4,783（18.0%） |
| T2 混合语料重测（232） | 232 | 4,643（17.4%） |
| core 真程序（本次） | 1,368 | 5,734（21.5%） |
| **两批并集（同调用）** | 1,232 | **5,925（22.3%）** |

修订后：真程序的净效应是 **+2.5pp**（同调用对照：旧语料 5,080 → 5,734），
不是之前写的 +3.5pp——那 +1pp 是编译调用的差异。两批语料互补，最优是 22.3%。
"加输入没用"的正确证据是**并集饱和**（贪心序 232 个输入即覆盖 5,734），
而不是"边际新函数中位数 0"（那条曲线是被文件大小升序排序扭曲的假象）。
详见 `findings/real_corpus.md` §3.1–§3.2。

每输入槽位已落盘在 `out/slots_realcore/`（196 MB），并集/最小化不必重跑。
