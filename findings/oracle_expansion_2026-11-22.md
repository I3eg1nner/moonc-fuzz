# 2026-11-22 issue→oracle 扩展：三路并行结果

Pin: `moon 0.1.20261104 (940aa18)`, `moonc v0.10.20+65efd5b93`.
所有 pilot 脚本/生成物在 `/tmp/sub_f7_layout`、`/tmp/sub_float`、
`/tmp/sub_asem`；主分支只收录结论。三路任务都不改 pin、不发上游 issue。

## 1. F7 布局扩展（174 个新程序）

在 `findings/issue_oracle_pilot.md` 的 F7 构造等价 oracle 上扩容器与布局：
`Array[Entry]`、`Option[Entry]`、`Result[Entry,String]`、`Array[Array[Entry]]`、
`Array[Option/Result]`、`FixedArray[Entry]`、`ArrayView` slice；2/4/8 字段、
1–4 个 enum、payload Int/String/Array[Int]/Int64/Bool；literal/push/
make/makei/map/filter/FixedArray::make/from_array/nested；n=0/1。
期望值由 Python 结构模型独立计算，从不使用 MoonBit 输出。

结果（108 primary + 45 supplemental + 21 mixed-layout）：

```
release: 174/174 rc=0 且 stdout == expected（wasm-gc/js/native --release）
native debug: 106 D_KNOWN_F7 + 68 D_PASS
signatures: 只有 F7:lower_array_make（106 次，who/message 相同）
candidates: none
```

按容器 release：`Array` 141、`Array[Option]` 8、`Array[Result]` 7、
`Array[Array]` 6、`Option` 6、`Result` 6。debug 的 106 个 F7 全部是已知
`lower_array_make`；`Option/Result/nested` 只复现这个已知签名，没有新触发。
边界观察（仍是同一签名，不是 candidate）：`FixedArray::make/makei` debug 通过，
但 `FixedArray::from_array` 和 `Array::from_fixed_array(FixedArray::make)` 会
触发 F7；`ArrayView` slice 通过；`Array::make(0, elem)` 在长度 0 时仍触发，
而空 literal + 零次 push 通过；`Array[Option/Result]` 的 make/makei/push 通过，
但如果先单独用 `Array::makei` 构造 F7-shaped Entry 再包进去，仍触发已知 F7。

## 2. Float32 / NaN payload（437 checks/后端）

### 先纠正一个旧前提

`findings/float_async.md` 原写“Float(f32) 没有 to_bits/reinterpret API”。
实际只有 `to_bits` 这个名字不存在；core 0.10.20 有：

- `Float::reinterpret_as_uint() -> UInt32`
- `Float::reinterpret_from_uint(UInt32) -> Float`
- `Float::reinterpret_from_int(Int32) -> Float`
- `Float::to_be_bytes()/to_le_bytes()`

所以 Float32 **可测**。详细报告见
[`float32_nan_pilot.md`](float32_nan_pilot.md)。

### 结果

17 个 f32 case + 16 个 f64 case + 4 个派生，每后端 437 个字段检查，
3 次 fresh 运行：

```
wasm-gc: exact=405 allowed=32 candidate=0
native : exact=405 allowed=32 candidate=0
js     : exact=403 allowed=34 candidate=0
cross-backend field diffs = 16, all NaN quiet-bit-only
cross candidates = 0
```

- 非 NaN 全部与 numpy 位级一致：±0、±inf、subnormal、max finite、1/3、
  max+max→inf、min_sub+self→2；
- qNaN payload 在构造/传递/Array/struct/neg/abs/算术上保留；
- sNaN 算术 quieten 后 payload 保留，三后端一致；
- JS-only allowed：f32 sNaN 构造时被 host quieten；f64 sNaN 经 `Array[Double]`
  被 V8 array store quieten。Node 直接验证，属于 host/engine，不是编译器缺陷。

控制：单 bit 注入 `add1`/`qnan.nan`/`be` 各触发 1 candidate，checker 有灵敏度。
**0 candidate，没有新编译器缺陷。**

## 3. async 38 个 distinct case（3–4 层）

在固定 10+1 之外生成 38 个 case：3 层顺序、循环 await、break/continue、
异常前后、跨 3 层异常、try/catch、defer LIFO、`all`/`spawn`、取消/超时。
每个 case 一个包，`moon test --target js/native/wasm-gc`。

结果（修正模型后重跑）：

```
js     : 38/38 pass
native : 38/38 pass
wasm-gc: 38 unsupported（Total tests: 0）
totals : 76 pass, 0 mismatch, 0 crash, 0 build_failure, 0 F8, 0 timeout
```

第一轮有 2 个 mismatch（`31_cancel_before`、`37_cancel_twice`）：expected 里
没有 `ASEM:c0:a`，实际有。复核发现 **expected 模型错**，不是编译器 bug：
`core/async/task_group.mbt` 明确写
“It is undefined whether the child task will start running immediately before
`spawn` returns”。`cancel` 之前 child 已经/正在启动，`c0` 打印、到 `pause`
才收到取消，是 API 允许的行为；js/native 输出逐字节一致，3/3 replay 相同。
期望文件已修正为允许 child 先启动，重跑 38/38。

**0 new async candidate；F8 known 0。**

## 4. 本轮唯一新缺陷候选：F13 formatter

从扩展后的 formatter pilot（12 个语法 case，11 通过）得到：

```moonbit
fn main { println(-(-2147483648)) }
```

原程序 rc 0、输出 `-2147483648`；`moonfmt` 打出
`println(--2147483648)`，格式化后 `moon run` 因
`E4095 Integer literal 2147483648 is out of range` 失败，3/3。
`-(-9223372036854775808L)` 同样；`-(-2147483647)`、hex min、表达式形式是
控制。详见 [`fmt_nested_minus.md`](fmt_nested_minus.md) 与
`poc/f13_fmt_nested_minus/`。

这是 formatter 有效性缺陷（valid → invalid），不是 miscompile；与 F5
（unary plus → `~+`）同一组件、不同签名，是否同根因未证明，暂记 candidate。

## 5. 结论

- **新增 1 个候选**：F13 formatter 嵌套一元负号。
- **没有新增编译器根因**：F7 布局、Float32/NaN、async 扩展都是 0 candidate。
- **一个旧前提被推翻**：Float32 不是无 bits API；`float_async.md` 已更正。
- **一个 async 负结果被纠正**：2 个 mismatch 是 spawn 启动时机未定义导致的
  模型错误，不是编译器缺陷；修正后 38/38。
- 这些结果再次说明：历史 issue 邻域接近饱和；新表面（Float32、async 状态机、
  formatter 边界）比继续扩 F7 更有产出。

## 6. 下一步

1. 把 F13 送 triage：确认是否与 F5 同根因；若是独立，补 `regress` 与 PoC 门禁。
2. 把 Float32/qNaN oracle 接入常规 campaign，sNaN 在 JS 上排除/归一化。
3. 把 async 38 case 固化为 `cmd/asem` 的第二组，保留 spawn 启动时机的
   允许模型，避免再把 `c0` 当 mismatch。
4. F7 容器扩展作为负结果保留，不再在同一邻域加样本。

## Evidence

- `/tmp/sub_f7_layout/summary.json`, `release.jsonl`, `debug.jsonl`, `cases/`
- `/tmp/sub_float/summary.md`, `summary.json`, `results/`, `controls/`
- `/tmp/sub_asem/results/summary.json`, `results.jsonl`,
  `model_correction.md`, `cases/`
- 本地 F13：`poc/f13_fmt_nested_minus/`, `findings/fmt_nested_minus.md`
