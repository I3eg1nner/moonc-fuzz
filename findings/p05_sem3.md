# P0-5 sem3：三后端完整 observation

Date: 2026-11-23. Pin 不变。

## 修改

`moonbit/cmd/sem3/main.mbt`：

- 新增 `observations_complete(classes)`：必须 3 个 backend，且每个 class 只能是
  `ok` 或 `trap`；
- `timeout`、`compile_error`、`truncated`、`ice`、`runtime_error` 任一出现，
  verdict 直接 `inconclusive`，不再进入 `any_ok && any_trap` 的 witness 分支；
- 该检查在 `array_oob` 分支之前，因此 `array_oob` 也要求三后端完整 trap；
- 单元测试：`sem3_wbtest.mbt` 覆盖 ok/trap/compile_error/timeout/truncated/ice
  和只有两个 backend 的情况。

## 边界

- 单元测试覆盖 verdict 前提；没有在真实三后端上注入 timeout/compile_error
  的 campaign 正负控。
- `target_class` 仍是 stderr 关键词分类（review6 P0-5 的剩余部分）；
  summary 不逐 backend 记 rc/超时/截断。
- 未改 pin、未发上游、未新增 `.py`。
