全部提交的触发样本均复现了所述异常，但若干 README 的数量、根因归并及影响范围需要修正。没有发现由不存在的文件、错误 cwd、缺失核心库或旧缓存造成的假阳性。

原始记录保存在 [results.json](/tmp/mbt-verify/results.json)，包括每次的绝对 cwd、完整 argv、退出码、信号和耗时；同目录的 `*.stdout`、`*.stderr` 保存原始输出。补充控制记录位于 [extra](/tmp/mbt-verify/extra/results.json) 和 [finalchecks](/tmp/mbt-verify/finalchecks/results.json)。

**工具链与验证方式**

最先成功执行的检查为：

```text
cwd=/data/audit/mbtfuzz
moon version --all
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)
Feature flags enabled: rr_moon_mod,rr_moon_pkg

moonc -v
v0.10.20+65efd5b93 (2026-11-05)
```

两条命令均 rc=0，与 pinned 版本一致。最初一次执行被执行环境的 `bwrap` namespace 故障阻止，尚未启动工具链；切换到可用执行环境后完成检查，没有将该环境故障计入缺陷。

F2、F6 的三次复现分别使用三个排除 `_build` 的全新副本，避免缓存影响。F3 仅运行两次，始终限制地址空间并设超时；P1 每个规模、每种输入均计时三次。除 F1/F1b 和 F3 外，以下结果均未观察到进程信号终止。

| 缺陷 | 判定 | 证据 | 限定 |
|---|---|---|---|
| F1 | **REAL** | 3/3：SIGSEGV，shell rc=139 | 实际是 **50** 个 `1`，不是 49 |
| F1b | **REAL** | 3/3：SIGSEGV，rc=139；与 F1 前两帧一致 | 支持同类故障，不能证明同一根因 |
| F2 | **REAL** | 3/3：`moon check` rc=1，`Invalid_argument("Char.chr")` | `syncheck` 3/3 返回 0 |
| F2b | **REAL** | 3/3：build-package rc=199，`Char.chr` | README 缺少完整命令；已验证脚本参数 |
| F3 | **REAL** | 2/2：rc=134，SIGABRT，`out of memory` | 仅证明受限条件下资源耗尽 |
| F4 | **REAL** | 3/3：rc=199，`Basic_utf8_decode.MalFormed` | 文件实际 40 B |
| F4b | **REAL** | 3/3：rc=199，同一异常 | 同一异常不足以证明同一底层根因 |
| F5 | **REAL** | 三轮均为 syncheck=0、fmt=0、reparse=2/E3001 | 是 formatter 往返缺陷；原程序不通过类型检查 |
| F6-min | **REAL** | 三个干净副本均 rc=255，指定 Machine_error | native `link-core` 阶段的诊断/工具缺陷 |
| F6 external | **REAL** | 三个干净副本均 rc=1，同一签名 | bridge 包链接失败；没有误编译证据 |
| P1 | **REAL** | 插值数翻倍，中位耗时增加 **9.68 倍** | 两点测量不能确定渐近复杂度阶数 |

**F1**

```text
cwd=/data/audit/mbtfuzz/poc/f1_moon_pkg_segv
moonc syncheck moon.pkg
三次：rc=139，SIGSEGV(11)，stderr 为空
```

额外执行：

```bash
gdb -q -batch -ex run -ex 'bt 8' --args moonc syncheck moon.pkg
```

真实栈顶为：

```text
#0 camlMoonc__next_segment_head_71310
#1 camlMoonc__report_failed_to_parse_71498
#2 camlMoonc__loop_71725
```

字节检查显示提交文件长 101 B，含 **50 个 `1`**。在 `/tmp/mbt-verify/f1-*`、`f1exact-*` 中生成控制，均执行 `moonc syncheck moon.pkg`：

| `1` 的数量 | 无末尾换行 | 有末尾换行 |
|---:|---:|---:|
| 48 | rc=2 | rc=2 |
| 49 | rc=2 | rc=2 |
| 50 | SIGSEGV，rc=139 | rc=2 |

因此崩溃真实存在，README 的边界计数错误。证据范围是显式调用 package syncheck，不能推导正常项目构建也会触发。

**F1b**

```text
cwd=/data/audit/mbtfuzz/poc/f1b_pkg_map_segv
moonc syncheck moon.pkg
三次：rc=139，SIGSEGV(11)，stderr 为空
```

GDB 观察到：

```text
#0 camlMoonc__next_segment_head_71310
#1 camlMoonc__report_failed_to_parse_71498
#2 camlMoonc__parse_map_elem_72891
...
#7 camlMoonc__parse_map_72879
```

在 `/tmp/mbt-verify/f1bControl` 删除最后一行 map entry，再执行同一命令，返回 rc=2，未崩溃。

这支持“F1 错误报告路径的另一触发样本”。闭源条件下，公共栈顶也可能是不同解析状态汇入同一错误处理函数，不能据此断言根因完全相同。

**F2**

三个全新 cwd 分别为：

```text
/tmp/mbt-verify/f2fresh0
/tmp/mbt-verify/f2fresh1
/tmp/mbt-verify/f2fresh2
```

每个副本均没有 `_build`，执行：

```text
moon check
三次：rc=1
stderr：Oops, the compiler has encountered an unexpected situation.
stderr：Error: Invalid_argument("Char.chr")
```

在原始 cwd 执行 `moonc syncheck cmd/main.mbt`，三次均 rc=0。

`xxd` 确认异常转义是 `5c e4 b8 ad`，即反斜杠加“中”；`file` 判为 UTF-8 文本。控制副本 `/tmp/mbt-verify/f2Valid` 只将 `\中` 改成 `\n`，`moon check` 返回 rc=0。这是输入相关 ICE，不是编码损坏或模块缺失。

**F2b**

```text
cwd=/data/audit/mbtfuzz/poc/f2b_zwsp_escape_t2_ice
moonc syncheck main.mbt
三次：rc=0
```

实际执行的完整编译命令为：

```bash
moonc build-package main.mbt \
  -o /tmp/mbt-verify/f2b.core \
  -pkg f2b/p -pkg-type executable \
  -i /home/user/.moon/lib/core/_build/wasm/release/bundle/builtin/builtin.mi:moonbitlang/core/builtin \
  -i /home/user/.moon/lib/core/_build/wasm/release/bundle/prelude/prelude.mi:prelude \
  -pkg-sources f2b/p:. -target wasm -g -O0 -workspace-path . \
  -all-pkgs /data/audit/mbtfuzz/harness/all_pkgs.json
```

三次均 rc=199，stderr 包含 `Error: Invalid_argument("Char.chr")`。

`xxd` 确认为 `5c e2 80 8b`：反斜杠加 U+200B，文件整体为合法 UTF-8。两个核心 `.mi` 路径均存在。

控制及排除 harness：

- `/tmp/mbt-verify/f2bValid` 中换成 `\n`，使用上述完全相同的参数，rc=0。
- 在 `/tmp/mbt-verify/extra/f2bOwnModule` 建立独立模块，直接 `moon check`，仍 rc=1、`Char.chr`。因此异常不依赖仓库的 `all_pkgs.json` 或 `f2b/p` 包名。

**F3**

```text
cwd=/data/audit/mbtfuzz/poc/f3_parser_oom
/usr/bin/time -v prlimit --as=6442450944 -- moonc syncheck cmd/main.mbt
```

| 次数 | 外层 rc | 子进程信号 | stderr | elapsed | 最大 RSS |
|---:|---:|---|---|---:|---:|
| 1 | 134 | SIGABRT(6) | `Fatal error: out of memory` | 16.73 s | 5,658,964 KiB |
| 2 | 134 | SIGABRT(6) | 同上 | 14.73 s | 5,661,736 KiB |

`time` 明确报告 `Command terminated by signal 6`；它自身输出中的 `Exit status: 0` 不能替代外层实际 rc=134。

控制 cwd `/tmp/mbt-verify/f3Control`，文件内容为恰好 19 B 的：

```text
fn f() -> Int { 1 }
```

执行 `prlimit --as=6442450944 -- moonc syncheck main.mbt`，rc=0，约 0.009 s。

两次已经稳定复现约 5.40 GiB RSS 的消耗，故没有第三次重复，更没有运行 uncapped。当前证据证明小型畸形输入导致严重资源耗尽，尚不能证明无限循环、无限增长或 README 中未限额运行的具体数字。

**F4**

```text
cwd=/data/audit/mbtfuzz/poc/f4_invalid_utf8
moonc syncheck doc.mbt.md
三次：rc=199
stderr：Error: Moonc.Basic_utf8_decode.MalFormed
并有明确 ICE banner
```

`xxd` 显示文件实际 **40 B**，偏移 `0x1e` 开始为 `ff fe`；`file` 判为 ISO-8859 文本。

在 `/tmp/mbt-verify/f4Valid` 保留相同 Markdown/code fence 结构，只将这两个字节改为 ASCII `ok`，执行同一命令，rc=0。

**F4b**

```text
cwd=/data/audit/mbtfuzz/poc/f4b_invalid_utf8_2
moonc syncheck doc.mbt.md
三次：rc=199
stderr：Error: Moonc.Basic_utf8_decode.MalFormed
```

`xxd -s 6120 -l 80` 确认偏移 6140 附近包含 `85 8b ... 92`；`file` 判为非 ISO 扩展 ASCII 文本。

额外在 `/tmp/mbt-verify/extra/f4bValid` 将非法 UTF-8 解码成合法 U+FFFD，保留其余结构后，syncheck 返回 rc=2，输出普通 E3001/E3002，未出现解码 ICE。这不是不存在文件产生的假异常。

**F5**

原始 cwd 为 `/data/audit/mbtfuzz/poc/f5_prefix_plus`。对 `i=0,1,2` 分别执行：

```bash
moonc syncheck u.mbt
moonfmt u.mbt -o /tmp/mbt-verify/f5-$i.mbt
moonc syncheck /tmp/mbt-verify/f5-$i.mbt
```

三轮均为 **0 → 0 → 2**。格式化产物含：

```text
fn f(y : Int32) -> Int32 {
  ~+(y)
}
```

重新解析的 stderr：

```text
[E3001] Lexing error: unrecognized character "~" (U+007E)
```

控制 `/tmp/mbt-verify/f5Minus` 将 `+y` 改成 `-y`，syncheck、fmt、reparse 均 rc=0。独立 executable 模块中的 minus 版本也通过 `moon check`。

README 的 `moon check u.mbt` 调用有效：实际 rc=1，诊断为 `[4021] The value identifier ~+ is unbound.`，独立模块同样如此。**普通 unbound 诊断本身不算缺陷；这里成立的是 formatter 将可解析输入输出成不可解析文本。**不能宣称它破坏了原本能通过类型检查的程序。

**F6-min**

三个干净副本 `/tmp/mbt-verify/f6minFresh0`、`1`、`2` 分别执行：

```text
moon build --target native
三次：rc=255
```

stderr 明确为 `failed to link f6min (native)`，实际失败子命令是 `moonc link-core`，带 ICE banner：

```text
Machine_error(kind=unsupported;
 who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback";
 message="the Native backend cannot export types containing closures")
```

两个干净控制均执行同一 build 命令：

| cwd | 修改 | rc |
|---|---|---:|
| `/tmp/mbt-verify/f6-noexport` | 仅删除 `#export_name` | 0 |
| `/tmp/mbt-verify/f6-noclosure` | 保留导出，将 closure 字段改为 `Int32` | 0 |

因此它是 native 链接阶段暴露内部异常的诊断/工具缺陷。证据没有表明这种闭包 ABI 应当受支持，也没有误编译证据。

**F6 external**

直接使用已提取的 `assets/f6_external/moonldif` 创建三个排除缓存的副本，没有 fetch。

```text
cwd=/tmp/mbt-verify/f6external0、f6external1、f6external2
moon test --target native
三次：rc=1，同上 Machine_error/ICE
```

在 `f6external0` 中进一步验证：

| 命令 | rc | 结果 |
|---|---:|---|
| `moon test --target native src` | 0 | 66/66 |
| `moon build --target native src` | 0 | 成功 |
| `moon build --target native src/bridge` | 255 | 同一链接 ICE |
| `moon build --target native` | 255 | 同一链接 ICE |
| `moon test --target js` | 0 | 66/66 |

问题定位到 `WeiR-h/moonldif/bridge` 的 native 链接；不是整个库无法编译，也不局限于 test 模式。

**P1**

生成命令：

```text
cwd=/data/audit/mbtfuzz/poc/p1_fmt_interp
bash generate.sh 1024 /tmp/mbt-verify/p1/i1024.mbt
bash generate.sh 2048 /tmp/mbt-verify/p1/i2048.mbt
```

计时 cwd 为 `/tmp/mbt-verify/p1`，使用单调时钟测量完整进程墙钟时间：

```bash
moonfmt i1024.mbt -o /tmp/mbt-verify/p1/out.mbt
moonfmt i2048.mbt -o /tmp/mbt-verify/p1/out.mbt
```

普通字符串控制使用完全相同的函数外形，将字符串内容换成 ASCII `x`，分别保持 **6082 B、13250 B**，各运行三次：

| 输入 | 第一次 | 第二次 | 第三次 | 中位数 |
|---|---:|---:|---:|---:|
| 插值 1024 | 1.608974 s | 1.584913 s | 1.580072 s | 1.584913 s |
| 插值 2048 | 15.288680 s | 15.441895 s | 15.347758 s | 15.347758 s |
| 等字节普通字符串 1024 | 0.005184 s | 0.004387 s | 0.003208 s | 0.004387 s |
| 等字节普通字符串 2048 | 0.003859 s | 0.003822 s | 0.003432 s | 0.003822 s |

所有 formatter 调用 rc=0；两种插值输入及其格式化输出 syncheck 均 rc=0。观察到 **9.68 倍**中位耗时增长，支持性能缺陷；不是非法输入、错误输出文件参数或 parser 拒绝输入造成的计时假象。

**`scripts/reproduce_all.sh` 审查**

- `ROOT` 计算及各 package cwd 正确；F1/F4 使用根目录相对路径也确实指向存在的文件。
- F2、F6-min、F6 external 运行前删除 `_build`；其余主要为直接 syncheck，不依赖项目缓存。
- F2b 的核心库路径在实际 `$HOME=/home/user` 下存在，合法转义控制通过。
- `run()` 的最后一条命令是 `echo`，**不传播被测命令退出码**。独立运行原函数加 `run false`，打印 `rc=1`，外层实际 rc=0。
- 只有 `set -uo pipefail`，没有结果断言；缺失文件、普通诊断和真正 ICE 都只打印 rc。
- 外部 assets 缺失时直接跳过；P1 完全没有包含在该脚本中。
- F5 使用固定 `/tmp` 路径且不检查 formatter 成功，存在旧输出被继续检查的潜在陷阱。本次三个独立输出文件均由成功的 formatter 调用生成，排除了该问题。

所以该脚本可提供人工查看的日志，不能作为“退出 0 即全部复现成功”的自动验证器。

**README 中不受本次证据支持或需要修正的内容**

- F1：“49 个 token 触发”错误；当前文件为 50 个，49 个控制不崩溃。
- F4：初读 README 写 22 B，实际为 40 B。
- F1b、F2b、F4b：“同一根因”应降级为同类异常/候选归并，黑盒运行没有证明底层原因。
- F2b：README 中 `build-package ...` 不足以独立复现，应补完整参数。
- F3：uncapped 的 8.2 GiB/20 s 未验证；本次有意不执行。不能据两次受限 OOM 断言无限增长。
- F5：全矩阵及 662/662、43/467 的历史统计未重新验证；当前结果只支持提交样本的往返缺陷。
- F6：当前最小源码实际为 10 行；“12 行”描述不准确。“正确返回码必须为 2”也不是本次实验能够证明的接口规范。
- P1：复现了约十倍增长，但未证明具体复杂度阶数，也未另行验证 `moon fmt` 的整包行为。

验证期间两个 README 出现了非本次工具调用写入的修改，其中包括将 F4 的 22 B 改为 40 B。我未覆盖这些修改；受跟踪 PoC 源码没有被本次验证修改。

**发布风险判断**

- **可以发布的实证**：F2 的阶段差异与 ICE；F3 的有界资源耗尽；F4/F4b 的解码 ICE；P1 的实测性能曲线。
- **发布前需改措辞**：F1 修正 token 边界；F1b/F2b/F4b 弱化同根因断言；F5 明确仅为语法往返缺陷；F6 明确为不支持导出类型时的链接 ICE/诊断缺陷。
- **仍需更多工作**：底层根因与独立缺陷数量、F3 的终止性分析、P1 的复杂度阶数、F5 的历史全矩阵统计。当前证据均不足以支持内存破坏利用、运行时误编译或远程攻击面的宣传。