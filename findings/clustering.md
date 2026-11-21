# 根因聚类：签名从"短哈希 + 源哈希"改成归一化原因

Date: 2026-11-21. 依据：独立评审 §4.3（去重不是根因聚类）。
工具链 pin 未改。

## 问题

- `save_crash` 用 `stage|kind|ice_detail|rc` 的短哈希：`ice_detail` 是第一条
  `Error:` 行，含临时路径/数字；同一根因的不同 witness 可能分桶，不同根因
  相同首行也可能合并。
- formatter 路径用 `"fmt-hang|" + sha1(src)`：每个输入一个签名、一个目录。

## 方案（`moonbit/cluster`）

`crash_signature(kind, rc, stderr, stdout)`：

- 提取**原因 token**：优先 `who="..."`（Machine_error）、异常构造器
  （`Invalid_argument`/`Basic_utf8_decode` 等）、第一条栈帧
  （`File "..."`/`Raised at`）、否则第一条 `Error:` 行；
- 归一化：数字串→`#`、绝对路径→`<path>`、空白折叠、220 字符截断；
- 已知类匹配：`lower_array_make`→F7、`finish_stub_wrapper_shell`→F9、
  `Char.chr`→F2、`Basic_utf8_decode`→F4、`Assertion failed`→F8、
  `out of memory`→F3，命中后追加 `|known=Fn`；
- 无文本时用 `crash|kind|rc=N`（信号仍可区分）。

`formatter_signature(rc, stderr, stdout)`：只取原因 token，**不含源哈希**；
同一 formatter 缺陷在不同输入上共享一个目录。

## 验证（`cluster/cluster_wbtest.mbt`）

| 用例 | 期望 | 结果 |
|---|---|---|
| F1 / F1b：`SIG` rc=-11，无文本 | 合并 | 相同 `crash|SIG|rc=-11` |
| F2 / F2b：`Invalid_argument("Char.chr")` | 合并 | 相同 |
| F4 / F4b：`Basic_utf8_decode.Malformed` | 合并 | 相同 |
| F7 / F8 / F9 | 不合并 | 三者互异，分别带 known=F7/F8/F9 |
| formatter 两个不同源、同一错误 | 合并 | 相同，且不含 `fmt-hang`/源哈希 |
| 不同 formatter 错误 | 不合并 | 互异 |

## 边界

- 已知库 6 条是人工维护的子串表，不是完整历史库；未知根因仍靠归一化文本
  分桶。
- 路径归一化是启发式（遇到引号/空格结束），对含空格路径会截断；测试只
  覆盖常见形式。
- `crash|SIG|rc=-11` 会把所有无文本 SIGSEGV 合并——这是有意的粗粒度，
  需要靠栈/复现再细分；细分证据在 PoC 里，不在签名里。
- 签名变化会改变既有 findings 目录名；旧目录不迁移，只影响新运行。
