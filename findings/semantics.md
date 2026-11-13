# 语义一致性测试：溢出/移位、Double 位级、oracle 灵敏度

日期 2026-11-12。方法按 codex review #2：确定性多包程序，四后端（wasm/wasm-gc/js/native）
真实 `moon run`，**每条操作单独打印**，与**独立参考实现**比对（不只跨后端互比）。

## 1. Int 32 位溢出与移位（`harness/overflow.py`）

* 200 个程序 × 18 例 = **3,600 例**；
* 操作数 MIN / MIN+1 / ±2^15 / ±2^16 / ±2^30 / MAX±1 / -1 / 0 / 1；移位量 0/1/15/16/30/31；
* 操作 ADD / SUB / MUL / SHL / SHR；排除除法与越界移位；
* 参考实现：Python 的 i32 回绕 + 算术右移。

结果：200/200 全后端跑通；**3,600/3,600 与参考一致**；1,200 对全 SAME；0 差异。

## 2. Double 位级（`harness/floatbits.py`）

按 codex 的格式打印 `id|op|a_bits|b_bits|tag|result_bits`（bits 用十进制，等价 hex）。

* 200 个程序 × 20 例 = **4,000 例**；
* 操作数由位模式构造：±0、最小/最大 subnormal、最小 normal 及 +1、最大有限、±inf、
  qNaN、±1 的邻居、2^53 及邻居、halfway；
* 操作 + - * /、取负、== < <=；
* 参考实现：Python `struct` 的 IEEE-754 double，逐位比较；NaN 只比 tag（payload 按
  wasm 规范允许不同）。

结果：200/200 全后端跑通；**4,000/4,000 位级一致**；1,200 对全 SAME；0 差异。

## 3. oracle 灵敏度（注入故障）

把 `lib.add` 改成 `a - b`，其余不动：

```
参考实现不一致: 4 处 {'wasm:ADD': 1, 'wasm-gc:ADD': 1, 'js:ADD': 1, 'native:ADD': 1}
后端对比较: 6 SAME / 0 DIFF
```

两个结论：

1. **oracle 抓得住真错误**（4 个后端全部被抓到，且差值正是 b 的两倍）；
2. **跨后端互比单独用不够**：四个后端"一致地错"，SAME 掩盖了缺陷——
   这就是必须引入独立参考实现的原因（codex 的提醒被这张表证实）。

## 3.5 可变引用别名（`harness/alias.py`，codex 第 4 轮指定）

* 200 个程序 × 12 步 = **2,400 步**；每步后打印 `case|step|read_a|read_b|slot_a|slot_b`；
* 覆盖：共享/独立引用、`f(r,r)` 重复实参、`nested`、`twice(f)` 高阶调用、
  读-写-读序列、跨包（cmd → alg → lib）；
* 参考实现：显式 store + slot id 的解释器。

结果：200/200 全后端跑通；**2,400/2,400 一致**；1,200 对全 SAME。

**注入故障**（把 `bump` 改成"拷贝内容、丢掉写"）：第一步就被抓到，
4 个后端全部报 `exp [0,1,0,1] got [0,0,0,0]`。oracle 灵敏度 ✓。

## 3.6 Int32 复合表达式（`harness/expr32.py`，codex 第 5 轮）

* 200 个程序 × 11 棵表达式树 = **2,200 个复合表达式**；
* 每个 expr_id 对应一棵记录在 `cases.json` 的完全括号化树；AST 解释器**每个节点后回绕**；
* 含 `(a*b)>>k`、`(a+b)>>k`、`((a*b)>>k)+c`；移位量 0..31；
* mandatory witness：`(MAX+1)>>1` 必须 = `-1073741824`。

结果：200/200 全后端跑通；**2,200/2,200 与参考一致**；1,200 对全 SAME；witness 0 失败。

准入检查（两条都过）：

| 检查 | 结果 |
|---|---|
| 若"延迟回绕"（widened），witness 会变成 `+1073741824` | 与正确值不同 ⇒ witness 能抓住 |
| 注入故障（`mul` 改成 `a*b+1`） | 每个后端都被抓到，多个表达式不一致 |

## 3.7 Double 复合表达式（`harness/expr64.py`，codex 第 6 轮）

* 200 个程序 × 16 棵树 = **3,200 个复合表达式**；每棵树记录在 cases.json；
* oracle：binary64 就近偶数舍入，**每个节点后舍入**；NaN 只比分类；
* 7 个 mandatory witness 全部达成：

| witness | 期望 | 实测 |
|---|---|---|
| `(2^53+1)-2^53` | +0 | +0 |
| `2^53+(1-2^53)` | 1 | 1.0 |
| `((1+2^-27)*(1-2^-27))-1` | +0（若 FMA 融合会变 `-2^-54`） | +0 |
| `(MAX_FINITE*2)/2` | +inf | +inf |
| `(MIN_SUBNORMAL/2)*2` | +0 | +0 |
| `(-0*1)+(-0)` | -0 | -0 |
| `1/(-0*1)` | -inf | -inf |

结果：200/200 全后端跑通；**3,200/3,200 一致**；1,200 对全 SAME。
注入故障（`sub` 改成 `a+b`）：witness 与普通表达式全部被抓到。

## 3.8 异常语义（`harness/exceptions.py`，codex 第 7 轮）

* 200 个程序 × 10 个 case = **9,695 条事件**；事件格式 `case|seq|site|event|tag|payload|s0|s1`；
* 事件：WRITE / RAISE / HANDLE / RETHROW / DONE / ESCAPE；
* 覆盖：嵌套处理器、rethrow 保留 payload、handler 内抛错外泄、raise 后的副作用被跳过、
  跨包抛出与捕获（lib 定义 suberror，alg 传播，main 处理）；
* 参考：Python 解释器（显式 store + Normal/Raised，不用 Python 异常）。

结果：200/200 全后端跑通；**9,695/9,695 事件一致**；1,200 对全 SAME。
注入故障（rethrow 时 payload +1）：ESCAPE 事件被抓到，4 后端全报。

注：MoonBit 的 suberror 是"只读类型"，跨包 **不能** `raise @lib.Boom(v)`，
必须由定义包提供 `rethrow` 辅助函数——这条是实测出来的语言约束。

## 3.9 Unicode（`harness/unicode.py`）

* 200 个程序 × 10 例 = **2,000 例**；字符串含 ASCII/Latin-1/组合字符/BMP/astral/ZWJ/区域旗/零字符；
* 观测：`char_length()`（码点）、`length()`（UTF-16 码元）、`code_unit_at(i)`；
* 参考：Python 码点语义 + UTF-16 编码。

结果：200/200 全后端跑通；**2,000/2,000 一致**；1,200 对全 SAME。
注入故障（`length()` 换成 `char_length()`）：被抓住。

结论（有边界）：**四个后端的 `String::length()` 都按 UTF-16 码元计**（"aé中😀" = 5），
`char_length()` 按码点计（4）。这是观测到的一致语义，不是规范结论。

## 4. 到目前为止的语义结论

| 族 | 例数 | 差异 |
|---|---:|---:|
| Int 溢出/移位 | 3,600 | 0 |
| Double 位级 | 4,000 | 0 |
| 可变引用别名 | 2,400 | 0 |
| Int32 复合表达式 | 2,200 | 0 |
| Double 复合表达式 | 3,200 | 0 |
| 异常语义 | 9,695 | 0 |
| Unicode | 2,000 | 0 |

干净的族不证明编译器正确，只提供有界证据。七个语义族合计 **27,095 例/事件**。

**codex 第 8 轮裁决（2026-11-12）：**

> This bounded semantic campaign is complete. All seven families passed their gates,
> with zero discrepancies against independent oracles across all four backends.
> This provides bounded evidence of semantic consistency, not proof of compiler correctness.

**"You should stop expanding this campaign."** —— 本轮监督到此结束。
