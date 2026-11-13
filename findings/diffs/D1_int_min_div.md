# D1 — `Int::min / -1` 跨后端行为分歧（wasm trap vs js 回绕）

| 项目 | 值 |
|------|-----|
| 目标 | `moonc v0.10.20+65efd5b93`，`moonrun 0.1.20261104`，node（js 后端） |
| 输入 | 3 行 MoonBit |
| 现象 | wasm 后端运行时 trap；js 后端正常运行并输出回绕值 |
| 发现方式 | 第二步"手写语义探针"（`/tmp/diffprobe` 的 int 探针扩展） |
| 定性 | **待确认**：可能是 wasm `i32.div_s` 的规范语义（overflow → trap），也可能是后端实现不一致；需要对照语言规范 |

## 复现

```moonbit
fn main {
  let a = -2147483648
  println((a / -1).to_string())
}
```

- wasm：`moonc build-package ... -target wasm` → `link-core ... -target wasm -wasi` → `moonrun out.wasm`

```
RuntimeError: divide result unrepresentable
    at @fuzz/p.compute (wasm://wasm/...:wasm-function[38]:0xe25)
exit code 1
```

- js：`-target js` → `node out.js`

```
-2147483648
exit code 0
```

## 为什么值得记

1. 这是本轮**第一个真实的跨后端行为分歧**，而且是最小化后 3 行。
2. 它说明差分 oracle 的**输入门槛**一旦解决（模板 + 只改函数体），产出会立刻出现——之前 0 发现不是 oracle 不行，是输入到不了 oracle 面前。
3. 同类候选还有 `a % -1`（wasm 同样 trap，js 返回 0），以及 `Int` 溢出（`max + 1`）——后者两边都回绕，暂未分歧。

## 需要确认的事

- MoonBit 语言规范对 `Int` 除法溢出的定义：是"未定义/陷阱"还是"回绕"？
  - 若是陷阱：wasm 正确，js 后端应改成 trap（当前 js 是静默回绕）。
  - 若是回绕：wasm 后端应改成回绕（或显式文档化为目标相关）。
- 这类目标相关行为应该在差分流水线里**单独归类**（TRAP_DIFF），不要和"真误编译（两后端都正常返回但值不同）"混在一起统计。

## 流水线处理

`harness/difftpl.py` 已把"只有一个后端能跑"的情况从"失败"提升为 `TRAP_DIFF` 候选：

- `WASM_RUN` + js ok → `TRAP_DIFF`
- `JS_RUN` + wasm ok → `TRAP_DIFF`
- 两边都跑通且输出不同 → `REAL_DIFF`
- 数值格式归一后相同 → `FORMAT_DIFF`
