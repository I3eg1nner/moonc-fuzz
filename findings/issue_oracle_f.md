# issue→oracle F：补 E 的洞并扩样

Date: 2026-11-22. Pin 不变。未发上游。候选不叫 confirmed。

## F1 四条 E1 遗留

1294 已在 pin 上复现：`rm -rf _build; moon test --target wasm-gc`，rc0 且
stderr 有 `Warning (deprecated): use new`；这是黑盒测试仍被
`skip_current_package` 漏过的诊断缺陷。已进 `oracle_cases/typecheck/1294/`，
`assertion=exit_and_stderr`。L1 由 issuecheck 识别；L2 用 seedfuzz test 300
mutants：290 runs、0 同签名，原因 `no_predicate`（warning 不是 judge defect）。

945 `moon info` 生成的 `pkg.generated.mbti` 用 `fn[T]`、无 `fn[]`：fixed，
断言进 curated。447 的 2025 `{ val, }` 简写在当前 parser 不接受，改为合法
等价式 `fn b() { val }` 后 `moon run --target wasm-gc` rc0：fixed，报告明确
记录旧简写不再解析。551 `moon check` 现在 rc1
`The trait A is not found`：fixed。

| issue | status | command | rc/output | assertion |
|---:|---|---|---|---|
| 1294 | **reproduced** | `rm -rf _build; moon test --target wasm-gc` | rc0; stderr `Warning (deprecated): use new` | warning must fire |
| 945 | **fixed** | `moon info; grep -qF 'fn[T]' pkg.generated.mbti` | rc0; `fn[T]` | mbti contains `fn[T]` |
| 447 | **fixed** | `moon run . --target wasm-gc -q` | rc0; 等价式 | 旧 `{ val, }` 不再解析；等价式运行 |
| 551 | **fixed** | `moon check` | rc1; `The trait A is not found` | missing import 现在报错 |
| 836 | **reproduced** | `moon check 2>&1 | grep -c 'invalid_attribute'` | rc0; count=1 | 只有 `#aaa` 报 0042，`#aaa.aaa` 漏 |

**F1b 60 条里另有 #1347 reproduced**（`moonc-prove` emit-only 输出
`a /\ b \/ c`，丢括号；见下）和 #547/#208 fixed；它们记录在 F4。

## F2 36 条 crash-drop（全部重做）

同一 reason 最多出现 2 次；每条都有 attempted command。结论：

| 分类 | 数量 |
|---|---:|
| rebuilt | 0 |
| blocked_by_deps | 30 |
| unclear | 6 |
| not_a_bug | 0 |


| issue | decision | title | 缺什么 / attempted command |
|---:|---|---|---|
| 1343 | **blocked_by_deps** | ICE: native debug regalloc 'requires more GPR patch scratch registers' when a call passes  | needs a native test package with 13 #valtype args; issue omits the test harness/pipeline（`moon test --target native`） |
| 1327 | **blocked_by_deps** | ICE: Sys_error "No such file or directory" when building with --target llvm (std bundle di | needs an LLVM release bundle and `--target llvm`; pin only has the native std bundle（`moon build --target llvm`） |
| 1308 | **blocked_by_deps** | ICE: Machine_of_clam_lower.lower_break: "break value is required for scalar loop" | needs a scalar labelled loop with `break value`; the issue code is old `loop` syntax and current parser rejects it before lowering（`moonc syncheck main.mbt`） |
| 1304 | **blocked_by_deps** | ICE: Moonc.Hashed_type.Unresolved_type_variable on malformed lexmatch arms (string-literal | needs lexmatch with string-literal tuple patterns; no current parser form, old frontend only（`moonc syncheck main.mbt`） |
| 1291 | **blocked_by_deps** | ICE: Ctype.Unify when `extend`ing two trait methods that both conflict with existing regul | needs two conflicting trait methods plus `extend` in a package; body gives no complete module（`moon check`） |
| 1289 | **blocked_by_deps** | ICE: native test link fails when layout table exceeds 22-bit offset | needs a package whose layout table exceeds 22-bit offsets; generator/package not supplied（`moon build --target native`） |
| 1286 | **unclear** | ICE: `moonc` raise Sys_error(No such file or directory) directly | needs a triggering cwd/path for Sys_error; no path or file layout in body（`moon build`） |
| 1272 | **blocked_by_deps** | ICE: output_value: integer cannot be read back on 32-bit platform | needs a 32-bit host; current host is x86_64 and the bug is output_value truncation there（`moon build --target native`） |
| 1266 | **blocked_by_deps** | ICE: moonc crashes when ```argument \|> tuple struct constructor``` | needs `argument |> tuple struct constructor`; the 2025 pipe syntax is not accepted by current parser（`moonc syncheck main.mbt`） |
| 1137 | **blocked_by_deps** | ICE: Key_not_found in link-core with `try/catch` on non-raising body (debug mode, wasm/was | needs a full test package for a try/catch on a non-raising body; only a fragment is given（`moon test --target wasm-gc`） |
| 1134 | **unclear** | ICE: The latest compiler appears to have internal problems with previous builds | reported only against stale previous builds; clean rebuild does not reproduce（`rm -rf _build; moon build`） |
| 1133 | **blocked_by_deps** | ICE: Key_not_found in link-core when optional Array[T] parameter has no default value (JS  | needs a JS package with optional Array[T] lacking a default; moon.pkg/args not in body（`moon test --target js`） |
| 1121 | **unclear** | ICE: moonc link-core Error: Not_found | link-core Not_found; body has no source or command（`moonc link-core`） |
| 1081 | **blocked_by_deps** | ICE: moon coverage analyze cannot find symbols for enum variants with specific patterns | needs coverage-instrumented artifacts and enum variants; not a standalone source（`moon coverage analyze`） |
| 1072 | **blocked_by_deps** | ICE: LLVM build target fail - No llvm release bundle | needs the absent LLVM release bundle（`moon build --target llvm`） |
| 1071 | **blocked_by_deps** | ICE:  `moon coverage analyze` failed with `AnyType::main() -> NonUnitType` | needs coverage instrumentation and a main returning non-Unit（`moon coverage analyze`） |
| 1041 | **unclear** | ICE: Compiler crash on moon build --target js | JS-target compiler crash; no source in body（`moon build --target js`） |
| 1035 | **unclear** | Error: File "moonc.ml", line 206536, characters 34-40: Assertion failed | assertion line 206536; body gives no minimal input/stack context（`moonc build-package`） |
| 1001 | **blocked_by_deps** | ICE: miscompile in wasm-gc | wasm-gc miscompile; needs the full module and expected output not in body（`moon run --target wasm-gc`） |
| 996 | **blocked_by_deps** | ICE: cast a closure to an empty trait object | closure cast to empty trait object; issue code uses removed cast syntax（`moonc syncheck main.mbt`） |
| 973 | **unclear** | ICE: | empty issue body, no repro or command（`none`） |
| 972 | **unclear** | ICE: | empty issue body, no repro or command（`none`） |
| 970 | **unclear** | ICE: moon build | `moon build` only; no source or error（`moon build`） |
| 949 | **unclear** | ICE: failed when building project | failed build project; no source or error text（`moon build`） |
| 925 | **blocked_by_deps** | ICE: ^-char in match using regex crashes compiler | regex `^-` in match; old regex/pattern syntax, not accepted now（`moonc syncheck main.mbt`） |
| 899 | **blocked_by_deps** | ICE: continue with a labelled loop | labelled continue; old loop syntax plus external array/buffer packages（`moon check`） |
| 887 | **unclear** | ICE: moon test trigger ICE | `moon test` ICE; no test file/package（`moon test`） |
| 821 | **blocked_by_deps** | ICE: "%async.run" cause compile failure | `%async.run` intrinsic; needs the async package and old intrinsic form（`moon build --target native`） |
| 804 | **blocked_by_deps** | ICE: `letrec` | `letrec`; syntax removed from current parser（`moonc syncheck main.mbt`） |
| 800 | **blocked_by_deps** | ICE: async local function that returns a trait object with error causes ICE | async local fn returning trait object with error; needs async package and old syntax（`moon test --target js`） |
| 796 | **blocked_by_deps** | ICE: `... as B` where `B` is a type alias for `&A` cause ICE | `... as B` alias form; old syntax removed（`moonc syncheck main.mbt`） |
| 784 | **blocked_by_deps** | ICE: Stack overflow when compiling large functions with C backend (over 200,000 lines) | 200,000-line C backend function; exceeds 15-min reconstruction budget and needs a large C harness（`moon build --target native`） |
| 780 | **unclear** | ICE: randomly occurred `parse_patch` error | parse_patch error described as random; no stable input or seed（`moonc build-package`） |
| 779 | **blocked_by_deps** | ICE: Array Pattern for `FixedArray` | FixedArray array pattern; old pattern syntax and package（`moonc syncheck main.mbt`） |
| 181 | **blocked_by_deps** | printing char beyond `U+10000` causes `moon run` to panic | printing char beyond U+10000; needs a specific console/encoding host and runtime output（`moon run main.mbt`） |
| 101 | **blocked_by_deps** | Fatal error: exception File "lib/xml/mir/monofy.ml": Assertion failed | old xml/monofy compiler path; this is an old compiler build, not the pinned moonc（`moonc build-package`） |

### F2 out-of-scope 20 条抽样

| issue | decision | title | 缺什么 / attempted command |
|---:|---|---|---|

| 594 | **blocked_by_deps** | [ICE] when parsing `fn { => 2 }` | `fn { => 2 }` is old closure syntax; current parser rejects it before any ICE（`moonc syncheck main.mbt`） |
| 681 | **blocked_by_deps** | Build LLVM Failed | needs LLVM release bundle; pin has no llvm target bundle（`moon build --target llvm`） |
| 1031 | **blocked_by_deps** | [vscode] Multiple moon.mod.json project broken with select backend | VSCode multi-module/select-backend state; needs an extension workspace, not a compiler program（`moon build`） |
| 540 | **unclear** | [compiler] warn-list number not match its description | warn-list numeric/description table mismatch; no source or warning id in body（`moon check --warn-list`） |
| 862 | **unclear** | [LSP] Failure to render large chunks of code | LSP rendering large chunks is a VSCode UI issue; no LSP request bytes（`moon-lsp --stdio`） |
| 437 | **blocked_by_deps** | error: compile an async fn | async fn compile error; needs async package and old async syntax（`moon build --target native`） |
| 550 | **blocked_by_deps** | [ICE] Compiler error on wasm-gc target but not on native | wasm-gc ICE but native works; body lacks the source/module needed to split backends（`moon build --target wasm-gc`） |
| 1338 | **blocked_by_deps** | Native runtime: moonbit_make_ref_valtype_array_raw under-allocates by 4 bytes on 32-bit ta | 32-bit-only heap overflow; host is x86_64（`moon build --target native`） |
| 1337 | **blocked_by_deps** | Native runtime: moonbit_get_ms_since_epoch (`@env.now()`) wraps around on 32-bit targets | 32-bit `@env.now()` wrap; host is x86_64（`moon run --target native`） |
| 60 | **blocked_by_deps** | Build fails when binding external functions with float return type | needs a native C stub for float-returning extern FFI（`moon build --target native`） |
| 128 | **not_a_bug** | `pkg.json` import should change the schema to array | schema-change feature request, not a defect repro（`none`） |
| 1345 | **unclear** | JS source map: two source lines mapped to the same generated position, so breakpoints can' | JS source-map breakpoint mapping; needs VSCode debugger/source-map consumer（`node`） |
| 1130 | **unclear** | LSP reports "Type has no method" for #cfg-gated FFI functions | LSP diagnostic for #cfg-gated FFI; needs a .mbti/config setup（`moon-lsp --stdio`） |
| 803 | **unclear** | [VSCode LSP] Can't complete `raise` keyword in type annotation. | LSP completion for `raise`; editor feature, not compiler behavior（`moon-lsp --stdio`） |
| 687 | **unclear** | [VSCode LSP] warn-list unavailable in moon.mod.json | VSCode LSP warn-list config; needs extension settings（`moon-lsp --stdio`） |
| 421 | **blocked_by_deps** | error: compile an async fn | async fn compile error; needs async package/source（`moon build --target native`） |
| 1064 | **unclear** | moonbit-lsp can't `run` main function  for single main.mbt without `moon.pkg.json` | LSP run main without moon.pkg; needs single-file module layout（`moon-lsp --stdio`） |
| 340 | **blocked_by_deps** | ICE when having extern function of other targets  | extern function for another target; needs per-target stub/package（`moon build --target native`） |
| 878 | **blocked_by_deps** | [moon test] define `Bool` type will encounter compile error in native backend | native Bool type compile error; body lacks package/source（`moon build --target native`） |
| 914 | **blocked_by_deps** | FFI functions returning Int64/UInt64 are not properly converted from JavaScript numbers | JS FFI parseInt Int64 conversion; needs JS host/stub（`moon run --target js`） |

## F3 跨仓库 triage

| # | 结论 | pin 上做了什么 | 三档 |
|---|---|---|---|
| moon#2527 | **blocked_by_deps** | 需要 QRFlux 全仓库 + Node cjs 脚本；未带入完整仓库，无法重建 | 未定 |
| async#732 | **blocked_by_deps** | 需要 TCP server + 两个并发客户端；issue 只有 server 片段 | 未定 |
| async#725 | **blocked_by_deps** | 需要 Linux aarch64 + 30 s inotify churn；本机 x86_64 | 未定 |
| core#4843 | **allowed_impl_divergence** | `min/-1` wasm trap vs js wrap；core int 文档明确 no portable result | 允许实现差异 |

core 303 条 defect-keyword 的 20 条抽样：0 rebuilt、9 blocked_by_deps、
8 not_a_bug、3 unclear。逐条在 `issues/core20_audit.json`。

## F4 E1 第二轮 60 条

固定种子 `20261123`，与第一轮 40 条不重叠；60 行在
`issues/e1b_audit.json`。8 条 labeled defect，4 条 pin-confirmed reproduced /
fixed：

| issue | pin result | category | 证据 |
|---:|---|---|---|
| 1347 | **reproduced** | wrong-code | `moonc-prove` emit-only 输出 `a /\ b \/ c`，括号丢失 |
| 836 | **reproduced** | typecheck | `moon check` 只有 1 个 `[0042]`；`#aaa.aaa` 无诊断 |
| 547 | **fixed** | typecheck | `moon check/build --target wasm-gc` rc0；现代 alias 接受 |
| 208 | **fixed** | crash | `moon build --target wasm` rc0；`WebAssembly.validate=true` |

1347 已用 `moonc-prove -emit-only` 资产化：`oracle_cases/miscompile/1347/`
生成 `a /\ b \/ c`，L1 命中 `BUG`；不需要 Why3。

另外 4 条 labeled 但未 pin 验证：1051、440、415、1339（原因见
`e1b_audit.json` 的 `pin_validation`；不并入 confirmed）。

### 合并召回

| 轮次 | 样本 | labeled defect | pin-confirmed |
|---|---:|---:|---:|
| 第一轮 | 40 | 6 | 4（1294/945/447/551） |
| 第二轮 | 60 | 8 | 4（1347/836/547/208） |
| **合计** | **100** | **14（14%）** | **8（8%）** |

严格按 pin-confirmed 8/100：Wilson 95% CI **4.1%–15.0%**；推算 389 条漏掉
**16–58 条**；现有 curated 对“26+漏掉”的召回 **30.8%–61.9%**（点估计约
45.6%）。labeled 14/100 的区间更宽（8.5%–22.1%，召回 23.2%–43.9%），只作
上界参考。

## 验收

- 1294/945/447/551 均有 pin 命令、rc、输出；1 reproduced + 3 fixed。
- F2 36 行全部重做，同一 reason 最多 2 次；20 条 out-of-scope 逐条。
- F3 3 条跨仓库 + core20 有结论；2 条 blocked、1 条 allowed divergence。
- F4 60 行有逐条结论；4 条 confirmed，4 条 unconfirmed；合并区间。
- `curated.json` 34 条（新增 1294/945/447/551/836/1347；612/1175 保持 skipped）。
- L1：reproduced evaluated 12/12、fixed 12/12；L2 新增 1294/836 均 0
  （`no_predicate`，warning/诊断不是 judge defect）；F 后 L2 为 **5/13 = 38.5%**。
- accept：27/27；package pos_defects=10；issue_regress normal 0/tamper 1。

## 风险

- F2 的 36 条 0 rebuilt 是“重建失败原因”，不是“无缺陷”；30 条缺 extern/
  target/包，6 条 body 无代码。
- F4 4 条未 pin 验证的 labeled defect 不能进 confirmed；严格召回按 8/100。
- 未发上游，未改 pin。

