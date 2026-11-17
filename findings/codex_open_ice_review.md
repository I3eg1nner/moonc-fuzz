# Codex 独立复验：F7/F8/F9

日期：2026-11-17。命令行：`codex-cli 0.166.0`，模型 `gpt-6-astra`，通过
`127.0.0.1:7890` 代理。复验在 `/tmp/codex-verify` 的隔离副本中进行；工具链
三个二进制 SHA-256 与原安装一致，未复用 PoC 的 `_build`。每个问题至少跑
3 次，并包含负控制、fresh copy、cwd/rc/signal/判别子串记录。

结论：三个问题均为 **REAL**，都是编译器/链接期 ICE，不是 miscompile。
Codex 同时指出 F9 README 原先关于 `moon test --build-only` 的说法有误；该
README 已修正。以下为 Codex 原始中文报告（逐字保留）。

---

三个问题均为 **REAL**：复现的是编译器 ICE／链接失败，未发现 miscompile 证据。

实际环境：在 `/tmp/codex-verify` 执行以下命令，均 `rc=0`、无 signal、stderr 为空：

```text
moon version --all
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)
Feature flags: rr_moon_mod, rr_moon_pkg

moonc -v
v0.10.20+65efd5b93 (2026-11-05)

uname -m
x86_64
```

| 问题 | verdict | 关键 rc/signature | caveat |
|---|---|---|---|
| F7 | **REAL** | native debug 三次均 rc=1；`Machine_error`、`lower_array_make`、`uninitialized non-null GC ref arrays are not lowered` | release、其他后端及两个源码控制成功 |
| F8 | **REAL** | JS 三次、wasm/native 各一次均 rc=1；`moonc link-core` → `Assertion failed` | check 成功；首次依赖缺失的 rc=255 已排除 |
| F9 | **REAL** | native debug 三次均 rc=1；`Machine_error`、`finish_stub_wrapper_shell`、`aggregate stub wrapper arguments are not lowered in this batch` | check/build 成功，但 test `--build-only` 同样失败；README 有误 |

所有下述命令的进程均无 signal 终止。每次构建前均删除该副本的 `_build`、`target`，依赖源码下载缓存保留；没有复用 PoC 构建产物。工具链复制到隔离目录，三个二进制的 SHA-256 与原安装一致。原副本所有原有文件的内容哈希前后相同；此副本没有 `.git`，因此采用全文件哈希核验。

**F7 exact command 证据**

cwd：`/tmp/codex-verify/.acceptance/f7`

```text
moon run repro.mbt --target native -q
# 三次 rc：1、1、1；stdout 均为空

moon run repro.mbt --target native --release -q
# rc=0；stdout="0\n"

moon run repro.mbt --target wasm-gc -q
moon run repro.mbt --target wasm-gc --release -q
moon run repro.mbt --target wasm -q
moon run repro.mbt --target wasm --release -q
moon run repro.mbt --target js -q
moon run repro.mbt --target js --release -q
# 六条均 rc=0；stdout="0\n"
```

三次失败的 stderr 均明确指出 `failed to link moon/test/single (native)`，并包含完整预期 Machine_error。成功运行仅有未使用构造器／字段警告。

负控制分别在 cwd `/tmp/codex-verify/.acceptance/f7-no-valtype`、`/tmp/codex-verify/.acceptance/f7-no-id` 执行：

```text
moon run repro.mbt --target native -q
```

删除 `#valtype`：rc=0，打印 `0`。保留 `#valtype`、删除 `id` 字段及初始化项，并将输出改为读取 `kind` 内的字符串：rc=0，打印 `x`，stderr 为空。

**F8 exact command 证据**

隔离环境初次没有 registry 索引，check/test 返回 rc=255，错误为 `module was not found in the registry`，这些结果不计入 ICE。cwd `/tmp/codex-verify/.acceptance/f8` 执行 `moon update`，rc=0；随后从原始源码建立新副本。实际下载的依赖声明确认为 `moonbitlang/async`、`version = "0.22.9"`。

有效复现 cwd：`/tmp/codex-verify/.acceptance/f8-fresh`

```text
moon check -q
moon check --target js -q
moon check --target wasm -q
moon check --target native -q
# 均 rc=0；stderr 为空

moon test --target js -q
# 三次 rc：1、1、1

moon test --target wasm -q
moon test --target native -q
# 各 rc=1

moon test --target js -v
# rc=1，补充核验链接阶段
```

失败均定位到 `example/ice-repro/repro` 的 blackbox test、`moonc link-core`，stderr 为：

```text
Error: File "moonc.ml", line 125623, characters 29-35: Assertion failed
```

stdout 均为空，链接未完成、未执行测试。并非文件缺失、包名错误或缺 core/prelude。

负控制 cwd 分别为 `/tmp/codex-verify/.acceptance/f8-fresh-no-pause`、`/tmp/codex-verify/.acceptance/f8-fresh-raise`：

```text
moon test --target js -q
moon test --target wasm -q
moon test --target native -q
```

前者只将 `@aio.pause()` 改为 `()`，保留 async 函数及 async test；后者只将 `raise?` 改为 `raise`。六次均 rc=0，无断言；前者只有 unused 警告，后者 stderr 为空。后者额外运行 `moon test --target js`，rc=0，明确打印 `Total tests: 1, passed: 1, failed: 0.`。

**F9 exact command 证据**

cwd：`/tmp/codex-verify/.acceptance/f9`

```text
moon check --target native -q
moon build --target native -q
# 均 rc=0

moon test --target native -q
# 三次 rc：1、1、1

moon test --target native --build-only -q
# rc=1，同一 Machine_error

moon test --target native --release -q
moon test --target native --release
# 均 rc=0；非 quiet 运行明确显示 1 个测试通过

moon test --build-only
# rc=1；The value identifier store is unbound.
```

native debug 失败均明确定位到 `moonc link-core`，包含预期的 `finish_stub_wrapper_shell` Machine_error，stdout 为空。

负控制 cwd：`/tmp/codex-verify/.acceptance/f9-no-call`。保留 extern 声明、C stub 和测试，将调用语句替换为 `ignore(x)`：

```text
moon test --target native -q
moon test --target native
# 均 rc=0；后者明确显示 1 个测试通过
```

成功运行只有 experimental／unused／测试导入警告，无 ICE。

**README 中不被我的运行支持的说法**

- **明确不成立：**F9 的“`moon test --build-only` 正常”。显式 native 时仍发生同一链接 ICE；按 README 字面省略 target 时，则因 `store` 未绑定而失败。不能将 `moon build` 成功等同于 test `--build-only` 成功。
- **尚未验证，不能据此认定错误：**F7 README 关于其他 enum 布局、`Array[Int]` payload，以及“触发必须满足全部条件”的完整最小性结论；本次只验证了上述具体复现和控制。
- **尚未验证：**F8 “移除 callback 的 error”这一额外控制；本次验证的是删除挂起点和 `raise?`→`raise`。
- 上游 #1322/#1340/#1344 仅按题设作为对应编号；本次未核验其当前开放状态，也不声称发现新的上游根因。

逐次完整 cwd、命令、rc、signal、stdout/stderr 已保留在 [results.jsonl](/tmp/codex-verify/.acceptance/results.jsonl)。所有新增文件均位于 `/tmp/codex-verify/.acceptance`。