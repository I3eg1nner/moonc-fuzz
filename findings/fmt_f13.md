# F13 formatter 回归门禁

Date: 2026-11-23. Pin 不变。

`fmt_f13` 固定三例：

- `-(-2147483648)` → `--2147483648` → `moon check` `[4095]`；
- `-(-9223372036854775808L)` → `[4095]`；
- `-(-(-2147483648))` → `[4095]`。

负控 `-(-1)` 格式化后可 reparse 且 `moon check` rc0。  
分类：`compiler_inconsistency_candidate`（valid→invalid，输出不能按原语义重解析），
不叫 confirmed。`fmt_f13` accept gate 3/3 + negative=1。

未做：hex min 当前格式化后 `moon check` rc0，不算同形态失败；未进 gate。
