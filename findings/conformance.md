# 多包一致性测试（codex review #2 的 C 项）

日期 2026-11-12。目标：按 codex 的判定线，验证"确定性的多包程序 × 4 后端"这条线是否成立。

## 设计

`harness/conform.py`：
* 每个程序 3 个包：`lib`（seed/clamp/first[T]）← `alg`（map 闭包/reduce/apply_twice）← `cmd/main`（executable）；
* 参数化：乘数 k、偏移 m、长度 n、clamp 上下界、transform 表达式 10 种、fold 6 种、初值 4 种；
* 确定性：`random.Random(0xA11CE + i)`，无时间/环境依赖；
* 运行方式：真实 `moon run cmd/main --target {wasm,wasm-gc,js,native}`（不是单文件拼装）；
* 判据：4 后端全跑通的比例；差异用修好的 `difftpl.normalize` 分类。

## 结果（200 个程序）

| 指标 | 值 |
|---|---:|
| 生成程序 | 200 |
| 4 后端全跑通 | **200（100%）** |
| 后端对比较 | 1,200 对 |
| SAME | 1,200 |
| REAL_DIFF / FORMAT_DIFF / TRAP_DIFF | **0 / 0 / 0** |

对照 codex 的放弃线（<160/200 就放弃）：**100% 通过**，这条线成立。

## 解读（谨慎）

* 100% 跑通说明生成器的类型/语法是正确的，**不说明**编译器一致性；
* 0 差异主要因为程序语义太"安全"：全是 Int 算术 + 数组 + 闭包，没有浮点、
  没有溢出边界、没有位运算宽度、没有异常、没有引用别名；
* 下一批必须换语义族，而不是加数量——同族跑到 1 万次也只会得到同样的 SAME。

## 下一步（待 codex 裁决）

语义族候选：Double 格式化与边界、Int/Int64/UInt 溢出与移位、异常跨调用、
可变引用别名、字符串/Unicode、泛型嵌套实例化。
