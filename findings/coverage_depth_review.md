# 覆盖率与搜索深度复盘：为什么“零候选”没有覆盖到 F7/F8/F9

日期：2026-11-17。工具链：`moon 0.1.20261104`、`moonc v0.10.20+65efd5b93`、
`moonrun 0.1.20261104`。主机：Linux x86_64，128 vCPU。

这份报告回答两个问题：

1. 现有 four-cell / IR / 真实包搜索的覆盖口径到底是什么，缺什么；
2. 为什么本轮新增的三个可复现缺陷（F7、F8、F9）不在既有零候选的覆盖范围内。

F7/F8/F9 都是**链接期编译器崩溃**，不是误编译结论。三者都对应上游仍开放的
报告；本仓库的贡献是固定工具链上的最小复现、控制实验和证据归档。

## 1. 当前覆盖口径

### 1.1 函数符号覆盖是唯一稳定的跨语料指标

`moonc` 未 strip，`nm -n` 可按最近前置 `T/t/W/w` 符号把 QEMU guest PC 归因到
函数。历史并集是：

```
camlMoonc* 函数符号  7,916 / 26,611 = 29.75%
```

这个数字的边界必须写清楚：

- 它是**函数符号级**并集，不是源码行、分支或可行路径覆盖；
- 分母包含匿名闭包和 Menhir action；
- 7,916 是历史 campaign 的并集，不是本轮 four-cell 的基线；
- 29.75% 只能说明“约 70% 的函数符号从未在已采集语料中执行”，不能说明
  未执行函数里一定有缺陷，也不能给出缺陷率上界。

### 1.2 QEMU trace 已经含块/边信息，但当前实现把它丢掉了

`-d exec` 日志逐条给出 TB 的 guest PC。现有 `trace/summarize_trace` 做的是：

```
pc_0, pc_1, ..., pc_n  ->  { func_of(pc_i) }  -> 排序去重
```

它只保留函数集合，丢掉了相邻关系 `(pc_i, pc_{i+1})` 和同一函数内的
连续 PC 段。因此：

- 当前没有**基本块覆盖**；
- 当前没有**边覆盖**；
- 当前没有**分支覆盖**；
- 现有 `total_tb` 是执行过的 TB 事件数，不是去重后的块数或边数。

这是一个实现缺口，不是数据缺口：同一份日志可以直接导出
`(prev_pc, pc)` 的去重边集，不需要 AFL 的哈希 bitmap，也不受跨进程 id
不稳定的影响。它仍然不是源码级分支覆盖（QEMU TB 边界不等于源码分支），
但比函数集合深一层，且可精确跨运行比较。

### 1.3 four-cell 是“同一后端、两个构建维”的差分

`optdiff` 的四个臂是：

```
B0L0  build -O0, link -O0
B0Ld  build -O0, link 默认
BdL0  build 默认, link -O0
BdLd  build 默认, link 默认
```

它能回答的是：

- 同一 target 下，build/link 的 O0/default 是否改变测试状态；
- code section / core / JS 输出是否真的变化（机制活性）。

它不能回答的是：

- wasm-gc / wasm / js / native 之间的语义是否一致；
- async、`#valtype`、FFI、异常、闭包布局等**源语言特性**是否被正确 lower；
- 优化器是否在某个未出现在测试套件里的输入上改变了结果。

已有机制活性数据支持“four-cell 不是空转”：

| 后端 | 机制活性 |
|---|---|
| wasm-gc | 162/162 artifact 的 code section 在四臂间有差异 |
| native | 37/45 对 O0/default core 哈希不同；object 大小随臂变化 |
| js | 173/173 artifact 的四臂 JS 输出不同 |

但“产物不同”不等于“语义被测试覆盖”。F7/F8/F9 恰好落在产物生成之后或
测试套件之外的路径上。

### 1.4 IR 的深度：样本量够，结构多样性不够

IR 已有两轮：

| 轮次 | 规模 | 结果 | 结构 |
|---|---:|---|---|
| v1 | 12,096 例 | 四臂全 ok，0 错误 | 9 种粗结构组合 |
| v2 | 12,096 例 | 0 错误；动态 `a[i]` 2,076/12,000 | 仍是同一 `main` 模板 |

IR 的类型子集只有 `Int`、`Bool`、`Unit`、`Array[Int]`。它没有：

- 除法/取模（除零与 MIN/-1 的边界）；
- 浮点、字符串、`Bytes`；
- 闭包、泛型、trait、递归 ADT；
- 异常、async、FFI、`#valtype`；
- trap/abort 路径。

因此 24,192 个 IR case 主要增加的是常量、分支和数组大小的组合，不是
“新的编译器路径”。这也解释了为什么 IR 的零错误不能外推到 F7/F8/F9。

### 1.5 真实包语料的深度：测试套件不是输入生成器

已有真实包结果：

| 后端 | 有效包 | artifact | test ID | candidate |
|---|---:|---:|---:|---:|
| wasm-gc | 94 | 162 | 8,849 | 0 |
| native | 111 | 184 | 9,249 | 0 |
| js | 103 | 173 | 9,031 | 0 |

这些测试是库作者写的单元测试，不是边界值/属性测试。它们通常覆盖正常
API 路径，很少覆盖：

- `#valtype` + 特定字段布局；
- `raise?` 回调 + async 挂起；
- 13+ 个 ABI 聚合参数；
- `V128` FFI；
- 超大 layout table / 导出闭包类型。

所以“111 个包、9,249 个 test ID、0 candidate”不能推出“这些特性没有缺陷”。
它只说明：**这批测试没有触发这些特性的失败路径**。

## 2. 本轮新增的三个缺陷为什么不在 four-cell 覆盖里

### F7：native debug 的 `#valtype` + enum 数组 lowering

最小源：

```moonbit
enum Kind { Ref(String) }
#valtype
struct Entry { id : Int; kind : Kind }
fn main {
  let values : Array[Entry] = []
  values.push({ id: 0, kind: Kind::Ref("x") })
  println(values[0].id)
}
```

`moon run ... --target native`（debug，`-g -O0`）在 `link-core` 失败：

```
Machine_error(kind=unsupported;
  who="Machine_of_clam_lower.lower_array_make";
  message="uninitialized non-null GC ref arrays are not lowered")
```

控制：

- `native --release` 成功；
- wasm / wasm-gc / js debug+release 成功；
- 去掉 `#valtype` 成功；
- 只保留 `kind : Kind` 成功；
- `id : Int; s : String` 成功；
- 换成 `Kind { A; B(String) }` 成功；
- `Kind { Ref(String) }` 或 `Kind { Ref(Array[Int]) }` 触发。

覆盖缺口：

1. four-cell 的 native 语料来自 core 包的测试，不含这个 `#valtype` 布局；
2. 该失败发生在 native **debug link**，而 `--release` 不复现；four-cell 的
   native `--llvm-opt 3` 也只是另一个 debug 臂，不会构造这个类型；
3. IR 没有 `#valtype`、enum、GC ref 字段；
4. 函数覆盖只看到“某个函数执行过”，看不到 `lower_array_make` 内部的
   布局分类分支。

上游对应：[#1322](https://github.com/moonbitlang/moonbit-docs/issues/1322)。

### F8：async 挂起后调用 `raise?` 参数的 link-core 断言

最小源（依赖 `moonbitlang/async@0.22.9`）：

```moonbit
pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}
```

`moon check` 通过；`moon test --target js`（以及 wasm、native）在
`moonc link-core` 失败：

```
Error: File "moonc.ml", line 125623, characters 29-35: Assertion failed
```

覆盖缺口：

1. IR 没有 async、没有 `raise?`、没有挂起；
2. four-cell 不链接 async 测试驱动；`optdiff` 的 wasm/js/native 路径是
   同步 `main`/test driver；
3. core 的 async 测试里没有这个 `raise?` 参数形状；
4. 函数覆盖无法区分“async 状态机的哪个 resume 分支被链接”。

上游对应：[#1340](https://github.com/moonbitlang/moonbit-docs/issues/1340)。

### F9：native debug 的 V128 extern stub wrapper ICE

最小包：

```moonbit
extern "C" fn store_v128(address : UInt64, value : V128) -> Unit = "repro_store_v128"
pub fn store(x : Float) -> Unit {
  store_v128(0UL, @v128.f32x4_const(x, x, x, x))
}
```

`moon.pkg` 声明 `native-stub: ["stub.c"]`，`stub.c` 接收
`moonbit_v128_t`。`moon test --target native` 在 debug 链接失败：

```
Machine_error(kind=unsupported;
  who="Machine_of_clam_lower.finish_stub_wrapper_shell";
  message="aggregate stub wrapper arguments are not lowered in this batch")
```

`--release` 成功。覆盖缺口：

1. four-cell 不测试 `extern "C"`/`native-stub`；
2. IR 没有 `V128` 和 FFI；
3. core 测试不含这个 ABI 形状；
4. 该错误发生在 stub wrapper lowering，不在普通函数代码生成。

上游对应：[#1344](https://github.com/moonbitlang/moonbit-docs/issues/1344)。

## 3. 本轮实际跑过的补充实验

这些实验不是 four-cell 的替代，而是用来验证“边界值/特性覆盖”是否有收益。

### 3.1 常量折叠 vs 运行时（Int / Int64 / UInt64）

每个表达式树同时以两种方式求值：

- 常量版本：所有叶子是字面量，允许编译期折叠；
- 运行时版本：同样的叶子经 `#inline(never)` 函数传入，阻止折叠。

两者应逐位相等；同时比较四个 target × debug/release。

| 类型 | 表达式对 | 配置 | const/runtime 不一致 | 跨配置不一致 |
|---|---:|---:|---:|---:|
| `Int`（四则/位运算/移位） | 1,920 | 8 | 0 | 0 |
| `Int`（加除法/取模/`lnot`） | 10,000 | 8 | 0 | 0 |
| `Int64` | 6,000 | 8 | 0 | 0 |
| `UInt64` | 6,000 | 8 | 0 | 0 |
| **合计** | **23,920** | **8** | **0** | **0** |

边界值包含 `0`、`±1`、`Int::MIN/MAX`、`Int64::MIN/MAX`、`UInt64::MAX`、
`1<<31`、`1<<63`、`±2^30`、`±2^62`。除法只使用非零常量除数，并排除
`MIN / -1`（文档明确为无便携结果，见下）。

### 3.2 整数除法溢出的边界：不是缺陷

`Int::MIN / -1` 在 wasm/wasm-gc 触发 `divide result unrepresentable`，
js 返回 `Int::MIN`，native debug `SIGFPE`，native release 返回 `Int::MIN`。
但 core 的 `int/README.mbt.md` 明确写：

> dividing the minimum `Int32` or `Int64` by `-1` with either operator ...
> These cases have no portable result. Depending on the backend and build mode,
> the program may abort or get an arbitrary value.

因此这**不是**本轮缺陷，也不应写成跨后端语义 bug。类似地，NaN 的符号位/
payload 差异不在语言保证内。

### 3.3 Unicode 字符串、异常、泛型、闭包、循环

手工构造并跑 8 个配置：

- 10 个字符串（空串、中文、emoji、组合字符、U+10FFFF、NUL），所有
  `s[i:j]` 切片、`length`、`iter`、`compare`、`to_upper/to_lower`、`find`；
- `try/catch/noraise` 嵌套、re-raise、闭包内 raise；
- 泛型 `reduce/map/pair/Opt/Box`、`#derive(Show/Eq/Compare/Default)`；
- 结构体/枚举/trait object/可变字段/数组别名/视图/`blit`；
- 闭包捕获可变变量、循环内创建闭包、200 个共享闭包体。

结果：四个 target × debug/release 的 stdout 全部逐字节一致。这里没有
发现缺陷，但这些是“有预期语义”的输入，不是随机语法。

### 3.4 数学函数：允许的 ULP 差异

300 个随机 64 位有限 double，比较 `sin/cos/exp/ln/sqrt/pow`。native 与
wasm/js 在部分大参数上差 1 ULP；core 的 `math/quickcheck_test.mbt` 明确
说明 sin/cos 在不同后端“legitimately differ by a few ulps”。因此不记为
缺陷。

### 3.5 全量 core release 测试

选 8 个包（`array`、`string`、`json`、`bigint`、`hashmap`、`deque`、
`sorted_map`、`float`）× 4 target × release：全部 rc=0。

整模块 release：

- wasm-gc、js：rc=0；
- wasm、native：rc=255，卡在 `async/socket` 的
  `cannot find suitable network interface for testing`。

这是环境限制，不是编译器结果，不能计入 candidate。

## 4. 结论：瓶颈是“特性/路径覆盖”，不是样本数

现有证据支持以下判断：

1. **函数覆盖 29.75% 不能支撑“优化器基本没问题”的结论。** 它只覆盖了
   函数入口，不覆盖分支；而 F7/F8/F9 都发生在函数内部/链接阶段的特定分类。
2. **four-cell 的零候选不能外推到 async、`#valtype`、FFI、异常。** 这些
   特性不在 IR 类型子集，也不在 four-cell 的同步 test-driver 语料里。
3. **继续加同模板 IR seed 的边际收益很低。** 12,096 例只落在 9 种结构
   组合；应改为增加结构/类型/协议维度，而不是同一模板的常量。
4. **真实包测试是“行为语料”，不是“边界语料”。** 111 包/9,249 test ID
   的零候选说明正常 API 路径稳定，不能说明异常/布局/链接边界稳定。
5. **F7/F8/F9 是可复现的链接期崩溃，但不是误编译。** 不应把它们写成
   “优化器错误”或“代码生成错误”；应写成“ICE / 诊断缺陷”。

## 5. 下一步优先级

1. **把 QEMU TB 序列变成精确块/边覆盖。**
   对每条 trace 记录 `(prev_pc, pc)`，按 `symbol+offset` 去重；报告
   `unique_blocks`、`unique_edges`、`edges/function`。这不依赖 AFL 哈希，
   可跨运行比较。 Caveat：QEMU TB 边界不是源码分支，报告时必须写明。
2. **特性导向的 MoonBit 源生成器。**
   至少覆盖：`#valtype` 布局矩阵（标量/GC/enum/嵌套）、`raise?`/`try`、
   async/`@aio.pause()`、闭包捕获、泛型实例化、FFI/`extern "C"`、`V128`。
   生成器要能输出“应成功”的程序，用四后端 × debug/release 的 stdout
   digest 做 oracle；链接失败单独分类为 ICE。
3. **跨后端同源差分。**
   当前 four-cell 是 target 内 build/link 差分；应补 wasm-gc/wasm/js/native
   四后端对同一源程序的 stdout/rc 差分，至少对特性生成器跑。
4. **真实包扩展。**
   registry 缓存有 239 个 zip；优先选能编译的包，记录 API 漂移，不把
   “旧包编译失败”算成编译器缺陷。
5. **build 维正控。**
   native/js 的 build 维已有机制活性，但仍缺“在 build 维注入语义变化，
   oracle 必须报 candidate”的正控；这决定 `Bd*` 零候选的可信度。

## 6. 证据边界

- F7/F8/F9 是 **link-time ICE**：F7/F8 的源程序通过 `moon check`，F9 通过
  `moon check --target native`（该包只声明 native）；失败发生在
  `moonc link-core`，没有执行到测试体。
- F7 只在 native **debug** 复现；release 和其他后端通过。不能据此声称
  native release 也有误编译。
- F8 在 js/wasm/native 的链接阶段复现；wasm-gc 不在该 PoC 的
  `supported_targets` 内。
- F9 只在 native **debug** 复现；`--release` 通过。它是 stub wrapper
  lowering 的 ICE，不是 V128 语义错误。
- 三者都对应上游仍开放的 issue；本仓库不声称新的上游根因，只声称在固定
  版本上复现并最小化。独立 codex 复验（每个 3 次 + 控制）见
  `findings/codex_open_ice_review.md`；它确认 F9 的 `moon test --build-only`
  也会命中同一 ICE。
- 本文的 23,920 个 const/runtime 对、300 个数学值、字符串/异常/泛型用例
  都是**负证据**：在这些输入和配置下没有观察到差异；它们不构成编译器
  正确性证明。
