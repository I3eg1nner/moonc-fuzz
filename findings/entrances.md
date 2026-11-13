# 多入口并集：7,097 / 26,611 = 26.67%（2026-11-11）

判断"分母里有多少是单一入口不可达的"，唯一办法是把核心二进制暴露的入口都跑一遍。
结论先说：**入口不是超集关系，link-core 是纯增量 +1,154 个函数**；四入口并集
**7,097 = 26.67%**（含自建语料 7,415 = 27.86%）。

## 1. 为什么手拼 `-i` 永远拼不对

core 的 1,473 个文件里 55% 编不过，根因不是编译器限制，是依赖方式错了：

| 坑 | 现象 | 事实 |
|---|---|---|
| 别名是**每个消费者自己声明**的 | `@flate` / `@encoding/utf8` | `zip/moon.pkg` 写 `"…/compress/flate"`，默认别名 `flate`；别处可能写全长 |
| 子包别名带 `/` | `-i x.mi:utf8` 无效 | 必须 `-i x.mi:encoding/utf8` |
| trait 按**全路径**可见 | `debug.Debug` / `quickcheck/shrink.Shrink` 报 "package not imported" | 同一个 .mi 还要再以 `moonbitlang/core/<rel>` 注册一次 |
| 白盒测试 | `-whitebox-test` + 同包源码一起编 | 私有符号只在同编译单元里可见 |
| `Unit`/prelude | `-pkg` 用 core 包名时 prelude 不自动注入 | 显式 `-i builtin` + `-i prelude` |

所以换掉"手拼"，直接用官方驱动算出来的命令：

```bash
cd <core 副本>
moon check --target wasm-gc --dry-run -v > cmds_check.log   # 299 条
moon build --target wasm-gc --dry-run -v > cmds_build.log   # 130 条
moon test  --target wasm-gc --dry-run -v > cmds_test.log    # 429 build + 299 link
python3 harness/replay.py cmds_*.log --cwd <core 副本> --out out/cov_replay_*.json
```

`replay.py` 把每条命令的 `-o` 重定向到临时文件（输入只读），在
`afl-qemu-trace -d exec` 下重放，再用 `nm` 符号化成函数集合。

## 2. 四个入口的数字

| 入口 | 命令数 | `Moonc.*` | 占比 | 执行 TB |
|---|---:|---:|---:|---:|
| `check`（含 39 条 `-whitebox-test`） | 299 | 5,119 | 19.24% | 0.79 G |
| `build-package`（模块级） | 130 | 5,476 | 20.58% | 0.29 G |
| `test` 的 build-package（含白盒/黑盒/内部测试包） | 429 | 5,908 | 22.20% | 1.39 G |
| `link-core` | 299 | 1,676 | 6.30% | **4.10 G** |
| **四入口并集** | — | **7,097** | **26.67%** | — |
| release 的 build（130 条，无 `-O0`/`-g`） | 130 | 5,787 | 21.75% | 0.37 G |
| release 的 test build（429 条） | 429 | 6,231 | 23.41% | 1.87 G |
| 再并上自建语料（1,368 真程序 + 232 混合） | — | **7,729** | **29.04%** | — |

集合关系（不是超集）：

| 关系 | 数量 |
|---|---:|
| `build − check` | 776 |
| `check − build` | 419 |
| `test − build` | 432 |
| `build − test` | **0**（test ⊃ build） |
| `link − (check∪build∪test)` | **1,154** |
| 自建语料 − 四入口 | 151 |
| 四入口 − 自建语料 | 1,514 |

读法：

1. **`test` 是 `build` 的超集**（0 丢失），所以模块级四条入口里它可以替代 build；
2. **`link-core` 谁都不覆盖**：单独只有 6.3%，但给并集 +1,154（+16%）——
   codegen / wasm 发射 / 链接这条路之前**一次都没走过**；
3. 自建的单文件语料 79% 被四入口覆盖，只带来 151 个独有函数，
   **所以"手拼 -i + 单文件"这套模型可以退休了**；
4. 代价：link 的 TB 数是 4.1 G，按工作量算它是四者里最贵的，但对覆盖的边际收益也最大。

## 3. 和旧数字的关系

| 口径 | `Moonc.*` | 占比 |
|---|---:|---:|
| 单文件语料（上一版"最优"） | 5,734 | 21.55% |
| 两批语料并集（上一版 22.3%） | 5,925 | 22.27% |
| **四入口并集（本次）** | **7,097** | **26.67%** |
| **全部并集** | **7,415** | **27.86%** |

+4.4pp 全部来自入口，不来自"更多输入"——和"语料已饱和（贪心 232 个打满）"的判断一致。

## 3.1 配置轴：release vs debug（codex review 的第一优先项，已实测）

`moon build --release --dry-run -v` 与 debug 的差别不只是开关：**release 换掉了
源文件集合**（`assert.mbt` → `assert_release.mbt`），所以覆盖差异是真的。

| 配置 | `Moonc.*` | 新增 |
|---|---:|---:|
| debug build | 5,476 | — |
| release build | 5,787 | +315 vs debug（debug−release 只有 4） |
| release test build | 6,231 | +315 对 debug 四入口并集 |

四入口并集 7,097 → **+release build 7,399 → +release test 7,412（27.85%）**，
再并语料 **7,729 = 29.04%**。裁决规则（codex 给的）：200 个可执行 case 内少于
100 个新函数就放弃；实测 +302，通过。

注意：moonc 只有 `-O0` 一个开关（LLVM 后端另有 `-llvm-opt 0..3/s/z`），
所以"优化矩阵"在 build-package 层面只有 debug/release 一维；多档在 `link-core`
的 dedup/优化里，尚未测。

## 3.5 剩下没覆盖的子命令（快速探测）

每个子命令各跑一个代表输入，看对四入口并集有没有增量（下界，未全量）：

| 子命令 | 单次 `Moonc.*` | 对 u4 新增 |
|---|---:|---:|
| `gen-test-info` | 763 | +29 |
| `bundle-core`（2 个 .core） | 156 | +7 |
| `compile`（单文件→wasm） | 738 | +93 |
| `build-interface` / `wasm-ld` | 未测（core 安装里没有 .mbti，wasm-ld 需要 .o） | — |

合计 ≈ +130（≈ +0.5pp），属"顺手补"，不是两位数。`gen-test-info` 值得全量补
（它只在 `moon test` 运行时调用，`--build-only` 抓不到）。

## 3.6 后端与开关面：预期 +1,500~3,000，实测 +82

| 面 | 命令 | 自身 `Moonc.*` | 对 6 入口并集新增 |
|---|---:|---:|---:|
| `-target native` | 133 | 5,593 | **+82** |
| `-target llvm` | 130 | 5,589 | +78（且 **llvm ⊂ native**，`llvm−native = 0`） |
| `-enable-coverage` | 130 | 4,695 | +97 |
| `-stacktrace` | 130 | 5,476 | **+0**（与基线逐位相同） |
| 并集 | — | — | 7,591（28.53%） |

结论：**native/llvm 不是"独立的一大套 lowering"，在函数计数上是薄薄一层**
（+82/+78），比估算低约 20 倍。原因和前端/后端工作量结论一致：`Moonc.*` 的
绝大多数函数是 parser/typer/monofy，后端 lowering 只占很小一部分。

**措辞更正（codex review #2）**：未覆盖的 18,764 个函数**不能**称为"不可达"。
观测并集只是**可达性的下界**；未观测到不等于不可达。正确说法是"在已测入口与配置
下未触发"，其中可能包含 runtime、未注册子命令、错误分支，也可能包含我们没构造出
的合法路径。因此"80% 不可达"这个结论撤回。

## 4. 口径声明

* 分母仍是 26,611 个 `Moonc.*` 符号，**包含四个入口都不可达的代码**
  （未注册的子命令、错误分支、OCaml runtime 的未用部分）；
* 每个入口只重放了 dry-run 打出的命令，**没有覆盖 `moon` 自己的调度逻辑**
  （那是 Rust 二进制，不在 moonc 覆盖范围内）；
* TB 数含进程启动与 130 个 `.mi` 的加载，只能当工作量量级，不能当指令数精确值。

## 5. 复现

```bash
cp -a ~/.moon/lib/core /tmp/corecopy && cd /tmp/corecopy
moon check --target wasm-gc --dry-run -v > /tmp/cmds_check.log
moon test  --target wasm-gc --build-only            # 生成 .mi/.core/.wasm 依赖
moon test  --target wasm-gc --dry-run -v > /tmp/cmds_test.log
grep '^moonc build-package' /tmp/cmds_test.log > /tmp/cmds_test_build.log
grep '^moonc link-core'     /tmp/cmds_test.log > /tmp/cmds_link.log
python3 /data/audit/mbtfuzz/harness/replay.py /tmp/cmds_check.log --cwd . --workers 32
python3 /data/audit/mbtfuzz/harness/replay.py /tmp/cmds_test_build.log --cwd . --workers 32
python3 /data/audit/mbtfuzz/harness/replay.py /tmp/cmds_link.log --cwd . --workers 30
```
