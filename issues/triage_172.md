# 172 条粗筛：keep/drop 理由

| # | state | decision | title | reason |
|---:|---|---|---|---|
| 1378 | open | **drop** | js backend: numeric `FixedArray`s other than `Byte` are plain `Array`s; typed arrays measure 2–2.8× faster | feature/performance, no correctness predicate |
| 1376 | open | **keep** | moon-lsp stops reading requests after an input decoding exception | curated: executable repro + machine assertion |
| 1372 | open | **keep** | moon-lsp hangs at 100% CPU in format-nth when the last top-level block has no trailing newline | curated: executable repro + machine assertion |
| 1371 | closed | **drop** | wasm (linear memory): every bounds-checked array read calls two out-of-line helpers, about 3x slower than unsafe_get | feature/performance, no correctness predicate |
| 1370 | open | **drop** | `moon fmt`: interpolation-heavy string costs ~9.5x more per doubling (1.6 s -> 15 s) | out of scope or insufficient minimal repro |
| 1369 | open | **keep** | `moon fmt` prints unary plus as `~+`, producing code that cannot be re-parsed | curated: executable repro + machine assertion |
| 1368 | open | **keep** | ICE: native link rejects an exported closure-containing type with an ICE instead of a diagnostic | curated: executable repro + machine assertion |
| 1367 | open | **keep** | ICE: SIGSEGV in `moonc syncheck` on a malformed `moon.pkg` | curated: executable repro + machine assertion |
| 1366 | open | **keep** | ICE: 19-byte parser input grows past 5 GiB and aborts (`moonc syncheck`) | curated: executable repro + machine assertion |
| 1365 | open | **keep** | ICE: invalid escape in a string literal reaches the typer as Invalid_argument("Char.chr") | curated: executable repro + machine assertion |
| 1364 | open | **keep** | ICE: invalid UTF-8 in a `.mbt.md` file reaches Basic_utf8_decode.MalFormed | curated: executable repro + machine assertion |
| 1346 | open | **drop** | VS Code Test panel drops snapshot failure details (expected/actual diff and location) | environment/tooling, not portable |
| 1345 | open | **drop** | JS source map: two source lines mapped to the same generated position, so breakpoints can't be set on the call's line | out of scope or insufficient minimal repro |
| 1344 | open | **keep** | ICE: native debug 'aggregate stub wrapper arguments are not lowered' for extern "C" taking V128 | curated: executable repro + machine assertion |
| 1343 | open | **drop** | ICE: native debug regalloc 'requires more GPR patch scratch registers' when a call passes 13+ #valtype arguments | crash shape but no minimal/self-contained repro in issue body |
| 1340 | open | **keep** | ICE: link-core assertion when an async function calls a `raise?` parameter after a suspension | curated: executable repro + machine assertion |
| 1338 | closed | **drop** | Native runtime: moonbit_make_ref_valtype_array_raw under-allocates by 4 bytes on 32-bit targets (heap overflow) | out of scope or insufficient minimal repro |
| 1337 | open | **drop** | Native runtime: moonbit_get_ms_since_epoch (`@env.now()`) wraps around on 32-bit targets | out of scope or insufficient minimal repro |
| 1328 | open | **keep** | moonc folds x + 0.0 to x, which is wrong for x = -0.0 (IEEE 754 6.3), on every backend | curated: executable repro + machine assertion |
| 1327 | closed | **drop** | ICE: Sys_error "No such file or directory" when building with --target llvm (std bundle dir is named `native`, not `llvm | crash shape but no minimal/self-contained repro in issue body |
| 1326 | open | **keep** | Native release: UInt taken from UInt? is treated as signed (to_uint64 sign-extends, >> is arithmetic) | curated: executable repro + machine assertion |
| 1322 | open | **keep** | ICE: native debug Array::push of #valtype record with enum fails in lower_array_make | curated: executable repro + machine assertion |
| 1312 | closed | **drop** | Missing Feature :- Pipe into async functions | feature/performance, no correctness predicate |
| 1308 | closed | **drop** | ICE: Machine_of_clam_lower.lower_break: "break value is required for scalar loop" | crash shape but no minimal/self-contained repro in issue body |
| 1304 | closed | **drop** | ICE: Moonc.Hashed_type.Unresolved_type_variable on malformed lexmatch arms (string-literal patterns in tuple form) | crash shape but no minimal/self-contained repro in issue body |
| 1292 | open | **drop** | `implicit_impl_as_method` (E0079): the suggested `pub extend` fix often doesn't compile (tuples → E4024, qualified path  | environment/tooling, not portable |
| 1291 | closed | **drop** | ICE: Ctype.Unify when `extend`ing two trait methods that both conflict with existing regular methods | crash shape but no minimal/self-contained repro in issue body |
| 1289 | open | **drop** | ICE: native test link fails when layout table exceeds 22-bit offset | crash shape but no minimal/self-contained repro in issue body |
| 1286 | closed | **drop** | ICE: `moonc` raise Sys_error(No such file or directory) directly | crash shape but no minimal/self-contained repro in issue body |
| 1274 | open | **drop** | Wasm backend miscompiles a #valtype struct with a Double first field returned from a raise function (i32.wrap_i64 expect | out of scope or insufficient minimal repro |
| 1272 | open | **drop** | ICE: output_value: integer cannot be read back on 32-bit platform | crash shape but no minimal/self-contained repro in issue body |
| 1266 | closed | **drop** | ICE: moonc crashes when ```argument \|> tuple struct constructor``` | crash shape but no minimal/self-contained repro in issue body |
| 1265 | closed | **drop** | VSCode native lsp: `moonbit.inlayHints.*` params not working | LSP feature request, not hang/crash |
| 1258 | open | **drop** | Primitive `Bytes == Bytes` in a contracted function generates invalid WhyML typing | out of scope or insufficient minimal repro |
| 1240 | closed | **drop** | Native LSP crashes on start | out of scope or insufficient minimal repro |
| 1178 | closed | **drop** | `wasm target: Unit-returning cross-package wrapper leaves extra value on stack (wasm-tools validate fails)` | out of scope or insufficient minimal repro |
| 1168 | open | **drop** | #borrow() is a no-op on closure parameters — does not eliminate per-call RC overhead | feature/performance, no correctness predicate |
| 1165 | open | **drop** | Native backend lacks Common Subexpression Elimination (CSE) for struct field access | feature/performance, no correctness predicate |
| 1163 | closed | **drop** | Feature request: borrowed/read-only references to eliminate refcount overhead in method calls | feature/performance, no correctness predicate |
| 1155 | open | **keep** | Native target: array length silently truncated to 28 bits, causing SIGABRT for allocations >= 256MB | curated: executable repro + machine assertion |
| 1139 | closed | **drop** | ICE in link-core: nested #external generic type with trait-constrained method (Key_not_found) | out of scope or insufficient minimal repro |
| 1137 | closed | **drop** | ICE: Key_not_found in link-core with `try/catch` on non-raising body (debug mode, wasm/wasm-gc/native) | crash shape but no minimal/self-contained repro in issue body |
| 1134 | closed | **drop** | ICE: The latest compiler appears to have internal problems with previous builds | crash shape but no minimal/self-contained repro in issue body |
| 1133 | closed | **drop** | ICE: Key_not_found in link-core when optional Array[T] parameter has no default value (JS target) | crash shape but no minimal/self-contained repro in issue body |
| 1131 | closed | **drop** | [Bug] wasm-gc: "Invalid stub type" for closure parameters containing String or Array in FFI stubs | out of scope or insufficient minimal repro |
| 1130 | closed | **drop** | LSP reports "Type has no method" for #cfg-gated FFI functions | out of scope or insufficient minimal repro |
| 1129 | closed | **drop** | Empty traits allow coercion from any type to trait object, bypassing nominal check | feature/performance, no correctness predicate |
| 1128 | closed | **drop** | WASM toolchain support for Windows aarch64 | feature/performance, no correctness predicate |
| 1123 | closed | **drop** | wasm-gc: trait object from #external type causes validation error | out of scope or insufficient minimal repro |
| 1121 | closed | **drop** | ICE: moonc link-core Error: Not_found | crash shape but no minimal/self-contained repro in issue body |
| 1114 | closed | **drop** | TCC crashes with SIGBUS when compiling large C files on ARM64 macOS | environment/tooling, not portable |
| 1081 | closed | **drop** | ICE: moon coverage analyze cannot find symbols for enum variants with specific patterns | crash shape but no minimal/self-contained repro in issue body |
| 1072 | closed | **drop** | ICE: LLVM build target fail - No llvm release bundle | crash shape but no minimal/self-contained repro in issue body |
| 1071 | closed | **drop** | ICE:  `moon coverage analyze` failed with `AnyType::main() -> NonUnitType` | crash shape but no minimal/self-contained repro in issue body |
| 1070 | closed | **drop** | Compiler bug in: `if false { -0.0 } else { 0.0 }` | out of scope or insufficient minimal repro |
| 1067 | open | **drop** | moonbit vscode error: `moon build` finishes okay but vscode extension reports error | out of scope or insufficient minimal repro |
| 1064 | closed | **drop** | moonbit-lsp can't `run` main function  for single main.mbt without `moon.pkg.json` | out of scope or insufficient minimal repro |
| 1057 | closed | **drop** | Wrong auto-completion in the case of changing an Iterable when iterating over it | LSP feature request, not hang/crash |
| 1054 | closed | **drop** | Allow exporting functions from another package for FFI | feature/performance, no correctness predicate |
| 1041 | closed | **drop** | ICE: Compiler crash on moon build --target js | crash shape but no minimal/self-contained repro in issue body |
| 1038 | closed | **drop** | Request for Support of the Full WebAssembly Atomic Instruction Set | feature/performance, no correctness predicate |
| 1036 | closed | **drop** | ICE: Request for Support of the Full WebAssembly Atomic Instruction Set | feature/performance, no correctness predicate |
| 1035 | closed | **drop** | Error: File "moonc.ml", line 206536, characters 34-40: Assertion failed | crash shape but no minimal/self-contained repro in issue body |
| 1031 | open | **drop** | [vscode] Multiple moon.mod.json project broken with select backend | out of scope or insufficient minimal repro |
| 1022 | closed | **drop** | Overlong type name cause `tcc` to truncate and report false duplication | out of scope or insufficient minimal repro |
| 1006 | closed | **keep** | Pattern match `[.., ch]` binds the wrong character | curated: executable repro + machine assertion |
| 1001 | closed | **drop** | ICE: miscompile in wasm-gc | crash shape but no minimal/self-contained repro in issue body |
| 996 | closed | **drop** | ICE: cast a closure to an empty trait object | crash shape but no minimal/self-contained repro in issue body |
| 992 | closed | **drop** | "The error type of this function is never used" should be a warning rather than an Error | out of scope or insufficient minimal repro |
| 981 | closed | **drop** | ICE: build target llvm failed in WSL(archlinux) | environment/tooling, not portable |
| 976 | closed | **drop** | `moon task` to run custom CLIs commands. | out of scope or insufficient minimal repro |
| 973 | closed | **drop** | ICE: | crash shape but no minimal/self-contained repro in issue body |
| 972 | closed | **drop** | ICE: | crash shape but no minimal/self-contained repro in issue body |
| 970 | closed | **drop** | ICE: moon build | crash shape but no minimal/self-contained repro in issue body |
| 968 | closed | **keep** | moonc parsing incorrect result for `UInt` integer literal | curated: executable repro + machine assertion |
| 949 | closed | **drop** | ICE: failed when building project | crash shape but no minimal/self-contained repro in issue body |
| 943 | closed | **drop** | Proposal: Add Support for `\f` Escape Sequence in String Literals | feature/performance, no correctness predicate |
| 941 | closed | **drop** | [LSP] rename action is incorrect for `fnalias` | LSP feature request, not hang/crash |
| 937 | closed | **drop** | ICE: Moonbit compiling fails in Windows OS | environment/tooling, not portable |
| 929 | closed | **drop** | [Doc] defer syntax documentation incorrect | documentation only |
| 925 | closed | **drop** | ICE: ^-char in match using regex crashes compiler | crash shape but no minimal/self-contained repro in issue body |
| 914 | closed | **drop** | FFI functions returning Int64/UInt64 are not properly converted from JavaScript numbers | out of scope or insufficient minimal repro |
| 912 | open | **drop** | [LSP] Crash on invalid warn-list | out of scope or insufficient minimal repro |
| 911 | closed | **drop** | rename `lsp-server.js` to `moonlsp` | LSP feature request, not hang/crash |
| 910 | closed | **drop** | failed to run "moon update" | out of scope or insufficient minimal repro |
| 906 | open | **drop** | [moonc] Wrong lexing error prompts | out of scope or insufficient minimal repro |
| 900 | closed | **drop** | [Doc] E4100: trait object type cast syntax error message is incorrect | documentation only |
| 899 | closed | **drop** | ICE: continue with a labelled loop | crash shape but no minimal/self-contained repro in issue body |
| 898 | closed | **drop** | [Docs] Fix typo in Cascade Operator example in fundamentals.md | documentation only |
| 887 | closed | **drop** | ICE: moon test trigger ICE | crash shape but no minimal/self-contained repro in issue body |
| 878 | closed | **drop** | [moon test] define `Bool` type will encounter compile error in native backend | out of scope or insufficient minimal repro |
| 875 | closed | **keep** | [moonfmt] Incorrectly formatted for a type with the name `Option` | curated: executable repro + machine assertion |
| 874 | closed | **drop** | [LSP] `typealias` doesn't support completion for unqualified name | feature/performance, no correctness predicate |
| 865 | open | **drop** | [LSP] Unusual lag for many type parameters | feature/performance, no correctness predicate |
| 864 | open | **drop** | [moonc] Some Unicode identifiers are not properly supported | feature/performance, no correctness predicate |
| 862 | closed | **drop** | [LSP] Failure to render large chunks of code | out of scope or insufficient minimal repro |
| 861 | closed | **keep** | ICE on invalid: crash on malformed utf-8 | curated: executable repro + machine assertion |
| 860 | closed | **keep** | [Miscompilation] WASM type error while no error reported by frontend | curated: executable repro + machine assertion |
| 857 | closed | **drop** | [LSP] Doesn't support completion for `visibility modifier` | feature/performance, no correctness predicate |
| 851 | closed | **drop** | [syntax trap] The priority of negative operator and dot syntax is unclear | out of scope or insufficient minimal repro |
| 837 | closed | **drop** | improve error report for `impl Trait for Type` | out of scope or insufficient minimal repro |
| 832 | closed | **drop** | Toolchain: Cannot build project with args `moon build --target native` on windows template project | environment/tooling, not portable |
| 821 | closed | **drop** | ICE: "%async.run" cause compile failure | crash shape but no minimal/self-contained repro in issue body |
| 804 | closed | **drop** | ICE: `letrec` | crash shape but no minimal/self-contained repro in issue body |
| 803 | closed | **drop** | [VSCode LSP] Can't complete `raise` keyword in type annotation. | out of scope or insufficient minimal repro |
| 800 | closed | **drop** | ICE: async local function that returns a trait object with error causes ICE | crash shape but no minimal/self-contained repro in issue body |
| 796 | closed | **drop** | ICE: `... as B` where `B` is a type alias for `&A` cause ICE | crash shape but no minimal/self-contained repro in issue body |
| 795 | closed | **drop** | deprecated `typealias` syntax doesn't report warnings. | out of scope or insufficient minimal repro |
| 784 | closed | **drop** | ICE: Stack overflow when compiling large functions with C backend (over 200,000 lines) | crash shape but no minimal/self-contained repro in issue body |
| 780 | closed | **drop** | ICE: randomly occurred `parse_patch` error | crash shape but no minimal/self-contained repro in issue body |
| 779 | closed | **drop** | ICE: Array Pattern for `FixedArray` | crash shape but no minimal/self-contained repro in issue body |
| 766 | open | **drop** | [bug] `Format Document` in VSCode fails to properly handle line comments for enum | documentation only |
| 754 | closed | **drop** | [VSCode LSP] doesn't support `fnalias TypeName::meth_name` code completion | feature/performance, no correctness predicate |
| 753 | closed | **drop** | [VSCode LSP] error type has one constructor doesn't support complete constructor name | feature/performance, no correctness predicate |
| 739 | closed | **drop** | VSCode LSP can't use code completion for newtype(struct) and newtype(tuple) | LSP feature request, not hang/crash |
| 728 | closed | **drop** | `Automatically insert Some when supplying optional arguments` syntax is counter-intuitive | out of scope or insufficient minimal repro |
| 697 | closed | **drop** | [wasm-gc] Optimizing trait polymorphism memory usage by using static tables | feature/performance, no correctness predicate |
| 689 | closed | **drop** | [ICE]: local function same name | out of scope or insufficient minimal repro |
| 687 | closed | **drop** | [VSCode LSP] warn-list unavailable in moon.mod.json | out of scope or insufficient minimal repro |
| 681 | closed | **drop** | Build LLVM Failed | out of scope or insufficient minimal repro |
| 666 | closed | **drop** | moonc should report error when user use unsupported intrinsics rather ICE directly. | feature/performance, no correctness predicate |
| 661 | closed | **drop** | `moonbit.h` should support C++ in native backend | feature/performance, no correctness predicate |
| 660 | closed | **drop** | [ICE] use FuncRef in global scope | out of scope or insufficient minimal repro |
| 655 | closed | **drop** | Why add type annotation in different place has different result? | feature/performance, no correctness predicate |
| 654 | closed | **keep** | [ICE] Using impossible trait objects in type definitions | curated: executable repro + machine assertion |
| 653 | closed | **drop** | Can't use mutual recursion separate by let binding | out of scope or insufficient minimal repro |
| 652 | closed | **drop** | fnalias doesn't support `Foo::foo` | feature/performance, no correctness predicate |
| 626 | closed | **drop** | [ICE] type alias for trait object type can't use for qualified method | out of scope or insufficient minimal repro |
| 609 | closed | **drop** | G-Machine example run (twice id 99) failed | documentation only |
| 596 | closed | **keep** | [ICE] when deriving Default with inexisted fields | curated: executable repro + machine assertion |
| 594 | closed | **drop** | [ICE] when parsing `fn { => 2 }` | out of scope or insufficient minimal repro |
| 588 | closed | **drop** | Fix garbled Unicode output in Windows console with native backend | environment/tooling, not portable |
| 582 | closed | **drop** | Add op_set_view to support view modification | feature/performance, no correctness predicate |
| 573 | closed | **keep** | ICE when use intrinsic function with invalid string | curated: executable repro + machine assertion |
| 569 | closed | **drop** | improve type infer when use binary operator | out of scope or insufficient minimal repro |
| 565 | closed | **drop** | memory.atomic.wait64 parse failed in wasm backend but available in wasm-gc | out of scope or insufficient minimal repro |
| 564 | closed | **drop** | Stack overflow when use release flag in wasm backend | feature/performance, no correctness predicate |
| 560 | closed | **drop** | VSCode LSP can't trigger completion list when enter `&My::` use trait object as namespace | LSP feature request, not hang/crash |
| 550 | closed | **drop** | [ICE] Compiler error on wasm-gc target but not on native | out of scope or insufficient minimal repro |
| 540 | closed | **drop** | [compiler] warn-list number not match its description | out of scope or insufficient minimal repro |
| 513 | closed | **drop** | Documentation Error in Chapter `Array Pattern Match` | documentation only |
| 477 | closed | **drop** | Compiler Error in "lib/lexers/wasm_lexer/wasm_lex.ml" about `StringView` | out of scope or insufficient minimal repro |
| 448 | closed | **keep** | Compiler Error: Incorrect Array Construction for ExternRef in Native Backend | curated: executable repro + machine assertion |
| 437 | closed | **drop** | error: compile an async fn | out of scope or insufficient minimal repro |
| 433 | closed | **drop** | A possible compiler bug in WasmGC backend | out of scope or insufficient minimal repro |
| 424 | closed | **drop** | Fails to execute tests from CLI or VS Code | environment/tooling, not portable |
| 421 | closed | **drop** | error: compile an async fn | out of scope or insufficient minimal repro |
| 409 | closed | **drop** | Executing `moon test` encounters ICE | out of scope or insufficient minimal repro |
| 381 | closed | **drop** | error: failed when testing. moonc version: v0.1.20241223+62b9a1a85 | out of scope or insufficient minimal repro |
| 375 | closed | **drop** | Possible compiler bug for target `wasm-gc` | out of scope or insufficient minimal repro |
| 371 | closed | **drop** | error: failed when building. moonc version: v0.1.20241218+f4a066f5f  | out of scope or insufficient minimal repro |
| 342 | closed | **drop** | Feature request: support `derive` for traits | feature/performance, no correctness predicate |
| 340 | closed | **drop** | ICE when having extern function of other targets  | out of scope or insufficient minimal repro |
| 338 | closed | **drop** | Possible compiler bug | out of scope or insufficient minimal repro |
| 333 | open | **drop** | Export to JS output Struct::method logic upgrade | out of scope or insufficient minimal repro |
| 323 | closed | **drop** | [feat request] Show trait info in LSP completion | feature/performance, no correctness predicate |
| 322 | closed | **drop** | [ICE] crash when println `String` | out of scope or insufficient minimal repro |
| 314 | closed | **drop** | Doc error, `moon run main` should be `moon run src/main` | documentation only |
| 278 | closed | **drop** | confused error message for struct initialize | out of scope or insufficient minimal repro |
| 197 | closed | **keep** | moonfmt: Unexpected format with indented comment | curated: executable repro + machine assertion |
| 181 | closed | **drop** | printing char beyond `U+10000` causes `moon run` to panic | crash shape but no minimal/self-contained repro in issue body |
| 152 | closed | **drop** | [Feature Request] Specify FFI export name | feature/performance, no correctness predicate |
| 130 | closed | **drop** | `moon new` error on Windows | environment/tooling, not portable |
| 128 | closed | **drop** | `pkg.json` import should change the schema to array | out of scope or insufficient minimal repro |
| 127 | closed | **drop** | `moon add ` should not mandate the package version | feature/performance, no correctness predicate |
| 101 | closed | **drop** | Fatal error: exception File "lib/xml/mir/monofy.ml": Assertion failed | crash shape but no minimal/self-contained repro in issue body |
| 68 | closed | **keep** | code formatting breaks the code unexpectedly | curated: executable repro + machine assertion |
| 60 | closed | **drop** | Build fails when binding external functions with float return type | out of scope or insufficient minimal repro |
| 54 | closed | **drop** | Error: Bad wat format | out of scope or insufficient minimal repro |
| 45 | closed | **keep** | Formatting: Big line with struct destructuring becomes syntax error | curated: executable repro + machine assertion |
| 44 | closed | **drop** | Formatting: Parenthesis being removed from logical expressions | out of scope or insufficient minimal repro |
| 16 | closed | **drop** | bug report: v0.1.95 | out of scope or insufficient minimal repro |
