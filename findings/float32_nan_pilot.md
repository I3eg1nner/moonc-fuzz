# Float32 / NaN-payload oracle pilot：API 前提被推翻，0 candidate

Date: 2026-11-22. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. Host: Linux x86_64；Node v24.14.1。
All artifacts under `/tmp/sub_float`; no repo code changes.

## 1. 关键更正：Float32 不是“没有 bits API”

`findings/float_async.md` 原写“Float（f32）没有可用的 `to_bits`/reinterpret
API”。实际是**只缺 `to_bits` 这个名字**；core 0.10.20 有完整的 f32 位操作：

| API | core 位置 | intrinsic |
|---|---|---|
| `Float::reinterpret_as_uint() -> UInt32` | `core/float/methods.mbt:818` | `%f32.to_i32_reinterpret` |
| `Float::reinterpret_as_int() -> Int32` | `:557` | 同上 |
| `Float::reinterpret_from_uint(UInt32) -> Float` | `:867` | `%i32.to_f32_reinterpret` |
| `Float::reinterpret_from_int(Int32) -> Float` | `:843` | 同上 |
| `Float::to_be_bytes()` / `to_le_bytes()` | `:138/:168` | 基于 reinterpret |
| `Float::to_double()` / `from_double()` | `:503/:942` | `%f32.to_f64` / `%f64.to_f32` |

`@float` 可用；`@float.not_a_number = 0x7FC00000`。`Float::to_bits` 不存在
（`[4015] Type Float has no method to_bits`），这大概就是旧结论只查了名字的
原因。Double 仍有 `reinterpret_as_uint64` / `reinterpret_as_double`。core 里
没有 `DataView` 符号，也不需要用 extern C。

本机快速复核：

```moonbit
fn main {
  let f = Float(1.5)
  println(f.reinterpret_as_uint())                 // 1069547520 = 0x3FC00000
  println(Float::reinterpret_from_uint(0x3FC00000U)) // 1.5
  println(Float::reinterpret_from_int(0x7F800001).reinterpret_as_uint())
                                                    // 2139095041 = 0x7F800001
}
```

三个后端 rc 0。

## 2. Pilot 设计

- 17 个 f32 case + 16 个 f64 case + 4 个派生计算；
- 每个 case：`raw`、函数传递、`Array` 存储、struct 字段、`neg`、`abs`、
  `to_be_bytes`、`add1`、`mul2`、f32↔f64 位型、NaN/inf/finite 标志；
- 派生：`max+max` 溢出、`min_subnormal+self`、`1/3`、`0/0`；
- 输入 bits：±0、±1、±inf、min/max subnormal、max finite、min normal、
  quiet NaN、qNaN payload 1、negative qNaN、signaling NaN、all-ones NaN；
  Double 对应；
- expected 由 Python `struct` + `numpy.float32/float64` 独立计算；NaN 的
  payload/sign 传播按结构分类，不硬编码为“必须一致”；
- 每后端跑 3 次 fresh；输出 41 行，每后端 437 个字段检查。

命令：

```bash
cd /tmp/sub_float/proj
moon run main --target wasm-gc
moon run main --target js
moon run main --target native
python3 /tmp/sub_float/check.py
```

## 3. 结果

```
wasm-gc: exact=405 allowed=32 candidate=0   (3/3 identical hash)
native : exact=405 allowed=32 candidate=0   (3/3 identical, same hash as wasm-gc)
js     : exact=403 allowed=34 candidate=0   (3/3 identical)
cross-backend field diffs = 16, all NaN quiet-bit-only
cross candidates = 0
```

非 NaN 全部与 numpy 位级一致：±0、±inf、min/max subnormal、max finite、
min normal、1 以上的下一个值、`1/3`（`3EAAAAAB` / `3FD5555555555555`）、
`min_sub+self -> 2`、`max+max -> +inf`。

qNaN payload 在构造、函数传递、Array/struct 存储、`neg`、`abs`、`+1`、`*2`
上都保留：f32 `7FC00001`，f64 `7FF8000000000001`；f32→f64 保留 payload。
sNaN 算术 quieten 后 payload 保留，三后端一致：`7FC00001` / `FFC00001`
（f32），`7FF8000000000001` / `FFF8000000000001`（f64）。
`0/0` 三后端都给 negative default NaN（`FFC00000` / `FFF8000000000000`），
NaN sign/payload 允许变化，记为 allowed。

## 4. 允许的差异（全部 JS-only、全部 NaN）

1. **f32 sNaN 在 JS 构造时被 quieten**：输入 `7F800001` 观察为
   `7FC00001`（`FF800001` → `FFC00001`），出现在 raw/id/arr/box/neg/abs/be。
   生成 JS 的 `$f32_reinterpret_i32` 用 `DataView.setInt32/getFloat32`，但
   MoonBit `Float` 在 JS 是 `Number`（f64），f32→f64 host 转换会 quieten
   sNaN；Node `Float32Array` 同样把 `0x7f800001` 读回 `0x7fc00001`。
2. **f64 sNaN 经 `Array[Double]` 在 JS 被 quieten**：
   `7FF0000000000001` → `7FF8000000000001`；函数传递和 struct 字段保留
   原 sNaN。Node 确认 V8 对 JS array store 会 canonicalize sNaN，而对象属性
   保留；MoonBit JS `Array` 是 JS array。

分类：**allowed host/engine divergence**，不是编译器缺陷。IEEE 754 不要求
NaN payload 传播，sNaN 可以 quieten；JS Number 没有 sNaN 表示。

## 5. 控制

对保存的输出做单 bit 注入：

- 翻 `one.add1` 一位 → 1 candidate；
- 翻 `qnan.nan` true→false → 1 candidate；
- 翻 `one.be` 一位 → 1 candidate。

说明 checker 对数值/纯位错误敏感，不是在 NaN allowance 下“什么都放过”。

## 6. 结论与建议

- **0 candidate**：Float32 位型、qNaN payload、±0、±inf、subnormal、溢出、
  1/3 在三个后端与 numpy 一致；没有新的编译器缺陷。
- 旧能力表必须更正：Float32 可测，`to_bits` 只是名字不存在。
- 新 oracle 值得继续：把 f32 位型/qNaN/signed zero/inf/subnormal 纳入常规
  campaign；sNaN 在 JS 上排除或只比较 quiet 后的形式；Double NaN 经
  array/struct/算术也可扩展，但 JS `Array[Double]` 的 sNaN quieting 要归一化。
- expected 用 numpy/struct，不再依赖 node DataView。
- 没有发上游 issue/comment；本文不声称 compiler defect。

## Evidence

- `/tmp/sub_float/summary.md`（完整报告）
- `/tmp/sub_float/proj/main/main.mbt`（pilot 源）
- `/tmp/sub_float/results/{wasm-gc,js,native}.{1,2,3}.txt`
- `/tmp/sub_float/check.py`, `check.out`, `summary.json`
- `/tmp/sub_float/controls/c{1,2,3}.out`（注入故障控制）
