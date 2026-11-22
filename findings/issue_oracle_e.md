# issue→oracle E：语料召回 + 被丢弃 issue 回收

Date: 2026-11-22. Pin 未改。A–D 的 26/28 条 curated、五状态与 L1/L2 见
[`issue_oracle_a_b.md`](issue_oracle_a_b.md)、[`issue_oracle_c.md`](issue_oracle_c.md)、
[`issue_oracle_d.md`](issue_oracle_d.md)。

## E1 召回审计（389 条未进 172 的抽样 40 条）

固定随机种子 `20261122`，从 561 条中排除 172 条粗筛后，对 **389 条**抽 40 条。
逐条按 crash/wrong-code/typecheck/formatter/LSP 挂死判断，结论 40 行。

- 真缺陷：**6/40**（15%）：
  - 612 polymorphic recursion 未被报告（类型检查误接受；旧语法）；
  - 1175 `moonc prove` wildcard 生成 broken WhyML（proof）；
  - 1294 `skip_current_package` 漏进 blackbox tests；
  - 945 `moon info` mbti 出现 `fn[]`；
  - 447 `use-js-builtin-string` wasm-gc 编译错误；
  - 551 缺 import list 的 traitalias 未被检查。
- Wilson 95% 区间：**7.1%–29.1%**（点估计 15%）。
- 推算 389 条中漏掉 **27–113 条**缺陷类 issue（点估计 58）。
- 现有 26 条 curated 对“26 + 漏掉”的召回约 **30.8%**（区间 **18.7%–48.6%**）。

按验收要求，样本中 ≥2 条真缺陷，已把 **612**（needs_old_toolchain）和
**1175**（unclear，blocked_by_deps）补进 `oracle_cases/typecheck/` 与
`issues/curated.json`（curated 26→28）。两条都未进入 C 的 L1/L2 分母。

## E2 回收 36 条 crash-drop

从 172 条粗筛的 36 条“crash 形态但无最小/自包含 repro”逐条处理，单条 10 分钟上限：
0 rebuilt、30 blocked_by_deps、6 unclear。逐条表如下。

### E1 40 rows

| # | state | verdict | title | reason |
|---:|---|---|---|---|
| 324 | closed | **not_defect** | 文档顺序问题 - 下载界面 | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 406 | closed | **not_defect** | doc: rewrite tutorial | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 778 | closed | **not_defect** | [question] What is the release cycle of the different moonbit toolchains for `core`'s CI? | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 218 | closed | **not_defect** | document error handling | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 612 | closed | **defect** | compiler doesn't report error when use polymorphic recursion | typecheck: polymorphic recursion accepted (old syntax) |
| 148 | closed | **not_defect** | Dyn trait support inside data structures, like Vectors | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 227 | closed | **not_defect** | missing document for `fn main` | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 1175 | open | **defect** | moonc prove: wildcard `_` in #proof_pure match arms generates broken WhyML | typecheck/prove: wildcard WhyML arity |
| 1132 | closed | **not_defect** | 文档里MoonBit for Go Programmers的位置太靠前了 | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 217 | closed | **not_defect** | document `panic`, `abort` properly | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 607 | closed | **not_defect** | typo: coref Issue on page /example/gmachine/gmachine-2.html | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 1294 | closed | **defect** | `#deprecated(skip_current_package=true)` still warns the package's own blackbox tests | typecheck/diagnostic: skip_current_package leaks into blackbox tests |
| 945 | closed | **defect** | [moon info] Unexpected empty type param list in generated mbti files | tooling: mbti emits fn[] |
| 551 | closed | **defect** | Missing import list in moon.pkg.json without check error when use traitalias | typecheck: missing import list not reported |
| 425 | closed | **not_defect** | Issue on page /toolchain/moon/package.html | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 77 | closed | **not_defect** | 开启moon check --watch后，print依然飘红 | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 428 | closed | **not_defect** | views (string, array, byte) | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 794 | closed | **not_defect** | [doc] `fnalias` used to create alias for values. | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 213 | closed | **not_defect** | WebAssembly.instantiate(): Import #0 module="spectest": module is not an object or function | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 643 | closed | **not_defect** | guard keyword doesn't support completion, only has snippet in VsCode | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 706 | closed | **not_defect** | [VSCode LSP enhancement] improve integer value of constant enum | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 591 | closed | **not_defect** | Issue on page /language/ffi-and-wasm-host.html#provide-host-functions | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 379 | closed | **not_defect** | doc: error and warning list + explanation | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 750 | closed | **not_defect** | [incosnistent] VSCode Error Message in E0011 | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 116 | closed | **not_defect** | It is recommended to provide a binary installation package, rather than installing it online using c | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 88 | closed | **not_defect** | Vscode plugin invalid type (?) | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 391 | closed | **not_defect** | doc: regenerate command line helper | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 447 | closed | **defect** | Compile Error when enabling `use-js-builtin-string` | wasm codegen: use-js-builtin-string compile error |
| 727 | closed | **not_defect** | [doc syntax trap] `type! E` and `type T` | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 679 | closed | **not_defect** | inconsistent name in moonbit.h in native backend | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 1008 | closed | **not_defect** | Tool chain update error on Win 64 | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 1052 | closed | **not_defect** | Proper versioning | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 3 | closed | **not_defect** | Type corresponding the WebAssembly `i64` type | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 390 | closed | **not_defect** | doc: Include a link to the stdlib docs on the homepage | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 630 | closed | **not_defect** | doc: rewrite sudoku part | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 249 | closed | **not_defect** | update the build sys doc w/ default Wasm-gc | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 264 | closed | **not_defect** | 换行优化建议 | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 805 | closed | **not_defect** | [Question] Why `letrec` syntax doesn't support `function type's newtype`? | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 212 | closed | **not_defect** | 中文编程语言为什么代码不能用中文写，看了下还是英文 | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |
| 353 | closed | **not_defect** | `moon new hello` got `Permission denied (os error 13)` | docs/feature/question/environment; not crash/wrong-code/typecheck/formatter/LSP-hang |

### E2 36 rows

| # | state | decision | title | reason |
|---:|---|---|---|---|
| 1343 | open | **blocked_by_deps** | ICE: native debug regalloc 'requires more GPR patch scratch registers' when a call passes 13+ #valty | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1327 | closed | **blocked_by_deps** | ICE: Sys_error "No such file or directory" when building with --target llvm (std bundle dir is named | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1308 | closed | **blocked_by_deps** | ICE: Machine_of_clam_lower.lower_break: "break value is required for scalar loop" | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1304 | closed | **blocked_by_deps** | ICE: Moonc.Hashed_type.Unresolved_type_variable on malformed lexmatch arms (string-literal patterns  | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1291 | closed | **blocked_by_deps** | ICE: Ctype.Unify when `extend`ing two trait methods that both conflict with existing regular methods | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1289 | open | **blocked_by_deps** | ICE: native test link fails when layout table exceeds 22-bit offset | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1286 | closed | **blocked_by_deps** | ICE: `moonc` raise Sys_error(No such file or directory) directly | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1272 | open | **blocked_by_deps** | ICE: output_value: integer cannot be read back on 32-bit platform | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1266 | closed | **blocked_by_deps** | ICE: moonc crashes when ```argument \|> tuple struct constructor``` | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1137 | closed | **unclear** | ICE: Key_not_found in link-core with `try/catch` on non-raising body (debug mode, wasm/wasm-gc/nativ | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 1134 | closed | **unclear** | ICE: The latest compiler appears to have internal problems with previous builds | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 1133 | closed | **blocked_by_deps** | ICE: Key_not_found in link-core when optional Array[T] parameter has no default value (JS target) | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1121 | closed | **blocked_by_deps** | ICE: moonc link-core Error: Not_found | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1081 | closed | **blocked_by_deps** | ICE: moon coverage analyze cannot find symbols for enum variants with specific patterns | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1072 | closed | **blocked_by_deps** | ICE: LLVM build target fail - No llvm release bundle | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1071 | closed | **blocked_by_deps** | ICE:  `moon coverage analyze` failed with `AnyType::main() -> NonUnitType` | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1041 | closed | **unclear** | ICE: Compiler crash on moon build --target js | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 1035 | closed | **blocked_by_deps** | Error: File "moonc.ml", line 206536, characters 34-40: Assertion failed | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1001 | closed | **blocked_by_deps** | ICE: miscompile in wasm-gc | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 996 | closed | **blocked_by_deps** | ICE: cast a closure to an empty trait object | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 973 | closed | **blocked_by_deps** | ICE: | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 972 | closed | **blocked_by_deps** | ICE: | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 970 | closed | **blocked_by_deps** | ICE: moon build | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 949 | closed | **blocked_by_deps** | ICE: failed when building project | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 925 | closed | **blocked_by_deps** | ICE: ^-char in match using regex crashes compiler | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 899 | closed | **unclear** | ICE: continue with a labelled loop | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 887 | closed | **blocked_by_deps** | ICE: moon test trigger ICE | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 821 | closed | **blocked_by_deps** | ICE: "%async.run" cause compile failure | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 804 | closed | **blocked_by_deps** | ICE: `letrec` | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 800 | closed | **blocked_by_deps** | ICE: async local function that returns a trait object with error causes ICE | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 796 | closed | **blocked_by_deps** | ICE: `... as B` where `B` is a type alias for `&A` cause ICE | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 784 | closed | **blocked_by_deps** | ICE: Stack overflow when compiling large functions with C backend (over 200,000 lines) | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 780 | closed | **unclear** | ICE: randomly occurred `parse_patch` error | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 779 | closed | **blocked_by_deps** | ICE: Array Pattern for `FixedArray` | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 181 | closed | **blocked_by_deps** | printing char beyond `U+10000` causes `moon run` to panic | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 101 | closed | **unclear** | Fatal error: exception File "lib/xml/mir/monofy.ml": Assertion failed | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |

### E2 out-of-scope 20 rows

| # | state | decision | title | reason |
|---:|---|---|---|---|
| 594 | closed | **unclear** | [ICE] when parsing `fn { => 2 }` | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 681 | closed | **blocked_by_deps** | Build LLVM Failed | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1031 | open | **blocked_by_deps** | [vscode] Multiple moon.mod.json project broken with select backend | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 540 | closed | **blocked_by_deps** | [compiler] warn-list number not match its description | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 862 | closed | **unclear** | [LSP] Failure to render large chunks of code | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 437 | closed | **unclear** | error: compile an async fn | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 550 | closed | **unclear** | [ICE] Compiler error on wasm-gc target but not on native | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 1338 | closed | **unclear** | Native runtime: moonbit_make_ref_valtype_array_raw under-allocates by 4 bytes on 32-bit targets (hea | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 1337 | open | **unclear** | Native runtime: moonbit_get_ms_since_epoch (`@env.now()`) wraps around on 32-bit targets | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 60 | closed | **blocked_by_deps** | Build fails when binding external functions with float return type | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 128 | closed | **unclear** | `pkg.json` import should change the schema to array | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 1345 | open | **blocked_by_deps** | JS source map: two source lines mapped to the same generated position, so breakpoints can't be set o | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 1130 | closed | **unclear** | LSP reports "Type has no method" for #cfg-gated FFI functions | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 803 | closed | **unclear** | [VSCode LSP] Can't complete `raise` keyword in type annotation. | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 687 | closed | **blocked_by_deps** | [VSCode LSP] warn-list unavailable in moon.mod.json | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 421 | closed | **unclear** | error: compile an async fn | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 1064 | closed | **unclear** | moonbit-lsp can't `run` main function  for single main.mbt without `moon.pkg.json` | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 340 | closed | **unclear** | ICE when having extern function of other targets  | bounded read: no self-contained module/command; 10-min reconstruction did not reach pin repro |
| 878 | closed | **blocked_by_deps** | [moon test] define `Bool` type will encounter compile error in native backend | custom toolchain/OS/external package dependency; not reconstructible in 10 min |
| 914 | closed | **blocked_by_deps** | FFI functions returning Int64/UInt64 are not properly converted from JavaScript numbers | custom toolchain/OS/external package dependency; not reconstructible in 10 min |

### E2 小结

- **rebuilt=0**：36 条里没有能在 10 分钟内重建出 pin 上可运行最小模块的条目；
  30 条依赖 OS/LLVM/TCC/Why3/第三方包，6 条 body 无代码块或缺少模块/命令。
- 没有把“重建失败”写成“不是 bug”；`blocked_by_deps`/`unclear` 是证据分类。
- 20 条 out-of-scope 抽样同样 0 rebuilt、8 blocked_by_deps、12 unclear。

## E3 新复现缺陷

E1/E2 没有产生新的 pin 上可复现缺陷：

- 612：2025 `typealias`/`fn[T]` 语法在当前 parser 直接 `E3002`，需旧工具链；
- 1175：需要 Why3 + proof-enabled package，当前环境没有该依赖，未运行；
- E2 36 条：rebuilt=0，全部 blocked/unclear，不能进入 L1/L2；
- 与 F1–F13 去重：612 是 typecheck 误接受（旧语法，非新签名），1175 是 proof
  工具链问题；没有与 F1–F13 相同签名的新条目。

因此 E3 没有新 oracle case、没有新 PoC/regression；这一条是**有证据的空结果**，
不是“没发现问题”。

## E4 其他仓库是否是缺陷入口

用已认证 `gh` 拉取 `state=all`，另存日期快照（不覆盖 moonbit-docs）：

| repo | snapshot issues | open | defect-keyword hits |
|---|---:|---:|---:|
| `moonbitlang/core` | 755 | 149 | 303 |
| `moonbitlang/moon` | 513 | 134 | 157 |
| `moonbitlang/async` | 88 | 25 | 58 |

`moonbitlang/moonbit-compiler` 的 `has_issues=false`，所以 `moonbit-docs` 是
公开 ICE/编译器 bug 的入口。`core`/`moon`/`async` 有 issue，但它们是库、构建
系统、async 运行时仓库，不是闭源 `moonc` 的同一入口；本轮只做快照与关键词
统计，没有并入 561 条召回分母（否则会把库 bug 与编译器 bug 混在一起）。
快照与 sha256 见 `issues/raw/README.md`。

代表性样本：core #4843 是 `min/-1` 跨后端差异（规范允许，见
`int_min_divergence.md`）；moon #2527 是 JS foreign_library 返回值错误（候选，
需单独 triage）；async #732/#725 是运行时 abort/panic。它们没有被静默忽略，
但也不伪装成 `moonc` 缺陷。

## 风险与结论

- E1 的召回区间很宽（18.7%–48.6%），说明 172 条粗筛不是完整缺陷集；剩余风险
  主要来自**无代码块/无最小模块**的 issue（E2 30 blocked + 6 unclear）。
- 36 条 crash-drop 没有任何 rebuilt，是“重建失败原因”而不是“没有问题”。
- 本轮没有新 pin 缺陷；新增资产只有 612/1175 两条**非当前复现**的召回记录，
  以及其他仓库快照。
- 未发上游 issue/comment，未改 pin。

## 交付

- `issues/e1_sample.json`、`issues/e1_audit.json`（40 行）
- `issues/e2_36.json`、`issues/e2_out20.json`（36+20 行）
- `issues/curated.json`（28 条；612/1175 为新增）
- `issues/raw/`：docs + core/moon/async 快照
- 本报告 `findings/issue_oracle_e.md`
