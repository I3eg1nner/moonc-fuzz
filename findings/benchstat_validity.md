# benchstat 有效性：无效数据报 invalid，不报 0

Date: 2026-11-21. 依据：本轮 (3)。工具链 pin 未改。

## 变化

- 窗口从"每 30 个采样"改为**真实时间**：monitor 每 2 s 往 stats.jsonl 写
  `elapsed_ms`，benchstat 按 60 s 桶取累计 `coverage_adds+new_edges` 的差分；
- 缺字段/缺时间戳/无效 baseline/边饱和时输出 `valid:false` 与
  `invalid_reasons`，`median_window` 为 `null`，不再用 0 冒充；
- CPU 仍按 GNU time `%U %S` 的百分之一秒解析（1372.66/1508.50/1502.18 与
  原始账本一致）。

## 验证

旧 10 分钟账本（没有新字段）：

```json
{"arm":"function","cpu_s":1508.5,"median_window":null,"windows":0,
 "valid":false,
 "invalid_reasons":["baseline=incomplete","stats missing coverage_adds/new_edges","stats missing elapsed_ms"]}
```

新单测：

- 三个带 `elapsed_ms` 的采样（0/60s/120s）得到窗口 `[4,5]`，`has_time=true`；
- 只有 `coverage_adds/new_edges`、没有 `elapsed_ms` 时窗口为空且
  `has_time=false`——无效，不是 0。

## 边界

- 60 s 桶只按采样边界，不插值；采样如果中断，窗口数会少；
- `baseline_state=disabled`（无 trace 运行）也判 invalid，因为此时没有
  覆盖学习可言；
- `edge=degraded_cap` 判 invalid 只影响边指标，函数 `adds` 仍可读，但整个
  arm 被标 invalid 以防混用。
