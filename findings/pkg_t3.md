# 包模式的 T3 语义 oracle：跑包内测试

Date: 2026-11-21. 工具链 pin 未改。

## 实现

`--pkg-run-argv`：T2 构建成功后，在同一个包目录跑运行阶段（`moon test
--target js` 等），以**包自带测试**作为 expected。计数：

- `pkg_t3_attempts` / `pkg_t3_ok` / `pkg_t3_fail`；
- `pkg_t3_distinct`（按源 sha1 去重）；
- 失败时把 `source.mbt`、`baseline.mbt`、`stdout.txt`、`stderr.txt`、
  `argv.txt` 写到 `<out>/pkg_mismatch/<hash>/`，并通过 `save_pkg_witness`
  以 `kind=TEST_FAIL` 进 findings，交给 capsule 包模式 triage。

## 5 分钟结果

| 包 | T2 尝试/成功 | T3 尝试 | T3 ok | T3 fail | distinct | 说明 |
|---|---:|---:|---:|---:|---:|---|
| f8（js） | 5,381 / 148 | 148 | 124 | 24 | 63 | 24 个语义失败已落盘 |
| f9（native release） | 5,090 / 169 | 169 | 169 | 0 | 136 | 测试全过 |

带 `--triage` 的 f8 复跑：`pkg_t3 ok=126, fail=24`，`triage_checked=4`，
`confirmed=0`，`inconclusive=4`——TEST_FAIL/BUILD_FAIL 不是 crash，triage
按规则不晋级；失败包确实进了 `findings/build/{TEST_FAIL,BUILD_FAIL}/` 与
`pkg_mismatch/`，triage 的 capsule 模式能在包上下文重放。

## 边界

- expected 是包内测试，不是独立解释器；测试覆盖不到的行为不算 mismatch；
- f8 的 24 个失败没有被最小化/确认是生成程序的语义错误还是测试脆弱；
- f9 的 0 失败可能因为测试只覆盖了很小一部分，不能当作"语义正确"的证明；
- T3 目前只在包模式；普通文件模式的 T3 仍是 trace/wasm 对拍。
