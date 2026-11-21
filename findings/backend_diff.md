# 跨后端差分（包模式）

Date: 2026-11-21. 工具链 pin 未改。

## 实现

包模式新增第二后端：

- `--pkg-run-argv-b`：同一变异包，用另一套 target 跑同一测试命令；
- `--pkg-run-cmd-b`：直接跑任意命令（用于正控/stub 后端）。

每轮 A 后端跑 `--pkg-run-argv`，B 后端跑 B 配置；只有
`backend_diff_class(out_a, out_b, rc_a, rc_b)` 判 witness 才落盘：

`<out>/backend_diff/<src-hash>/{source.mbt, baseline.mbt, argv_a.txt,
argv_b.txt, out_a.txt, out_b.txt, rc.txt}`。

计数：`backend_attempts`、`backend_witnesses`、`backend_excluded`。

## 语义域

`backend_diff_class` 先排除已知后端差异：输出/rc 相同 → none；
若差异文本含 `Float`/`Double`/`Int64`/`UInt64`/`nan`/`inf`/`undefined`/
`timing`/`GC`/`debug`/`elapsed`/`ms)` → **excluded**；否则 witness。
设计意图：只比较 Int/字符串/数组/控制流/异常这类明确语义，显式排除
浮点格式化、Int64 在 js 的表示、未初始化内存、GC/时序、调试输出。

## 正负控

- 正控（人为差异）：`--pkg-run-cmd-b 'echo "Total tests: 1, passed: 0,
  failed: 1."; exit 1'`，45 s、f8：
  `backend_attempts=2, backend_witnesses=2, backend_excluded=0`，
  `backend_diff/` 下 2 个 witness 目录；
- 负控（排除域）：B 输出 `Float nan`，30 s：
  `backend_attempts=1, backend_witnesses=0, backend_excluded=1`；
- 负控（同后端）：classifier 单测 `same output/rc -> none`。

## 可用后端对

| 包 | A | B | B 可构建? |
|---|---|---|---|
| f8 | js | wasm-gc | 是（baseline `moon test --target wasm-gc` rc=0） |
| moonldif | wasm-gc | js | 是（baseline `moon test --target js` rc=0） |
| f9 | native release | wasm-gc / js | **否**：`test --target wasm-gc`/`js` 都报 4021（v128 stub 仅 native） |

f9 没有可用的第二后端，本轮只能跑 f8 与 moonldif 的 30 分钟；这是包本身
的后端限制，不是差分链的问题。

## 30 分钟结果（第一轮：f8 js vs wasm-gc，moonldif wasm-gc vs js）

| 包 | 后端对 | T3 尝试 | backend attempts | 运行时报 witness | 离线重判 |
|---|---|---:|---:|---:|---|
| f8 | js / wasm-gc | 1,056 | 1,056 | 1,056（假） | **164 唯一目录，全部 excluded** |
| moonldif | wasm-gc / js | 494 | 494 | 0 | 0 witness，6 excluded |

f8 的 B 后端 `moon test --target wasm-gc` 报 `Total tests: 0`（async 测试
没有被该后端发现/执行），所以第一版分类器把"1 个测试 vs 0 个测试"全判成
witness。修正后：先比较 `Total tests`/`failed` 计数，一侧为 0 或总数不等
→ **excluded**，不再当差异；164 个目录全部应判 excluded。教训：**先验证
第二后端真的跑了测试套件**，否则只是在比较 harness。

moonldif js/wasm-gc 两边测试都跑，494 次尝试里 0 witness、6 excluded：
这轮变异没有产生跨后端语义差异。

## f9

f9 的 `test --target wasm-gc` 与 `--target js` 都报 4021（v128 stub 仅
native），没有第二后端可用，未跑跨后端。
