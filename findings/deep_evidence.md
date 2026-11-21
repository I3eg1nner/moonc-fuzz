# Deep lane：证据、截断与全局去重（第四轮复核 4）

Date: 2026-11-21. 工具链 pin 未改。

## 改动

- `TraceTask` 新增 `lane`，deep 源的 T2 trace 提交带 `lane="deep"`；
  `trace_apply_delta` 对 deep lane **不再** `feedback_upsert`，T1/T2 novelty
  路径此前已排除 deep——deep 不能经任何 feedback/trace 路径进普通父本池；
- deep T3 的 mismatch 现在落盘到 `<out>/deep_mismatch/<hash>/`：
  `source.mbt`、`expected.txt`、`actual.txt`、`argv.txt`（moon run + fname +
  target + cwd）、`ir_seed.txt`（生成 seed/size/truncated/rc）。IR 以
  "seed+生成器参数+派生源"保存，仓库的 IR 没有文本 dumper；
- `rr.stdout_truncated` 为真时计入 `deep_t3_inconclusive`，不算 mismatch；
- distinct 改为 `prog.deep_matched` 全局集合，summary 增加
  `deep_t3_distinct_global`；worker 局部的 `deep_t3_distinct` 仅作事件计数，
  不再当 distinct 下界/上界引用。

## 验证

单测 378 通过；短跑（70 s，deep-p 50）此前 42/42 matched。本轮改了全局
去重，未重跑长 campaign；`deep_t3_distinct_global` 与 matched 事件数的关系
需要在下一轮用非零 mismatch 才能压力测试。

## 边界

- 全局 Map 在 async worker 间无显式锁；当前 worker 是协作式调度，插入不
  跨 await，仍不是线程安全证明；
- mismatch 证据只在主 campaign 的 deep T3 路径落盘，deepfuzz 独立命令已有
  自己的保存逻辑；
- IR 不是完整 AST dump，只是可重放的生成参数 + 源。
