# 等待/关闭路径的死锁测试

Date: 2026-11-21. 工具链 pin 未改。

## 单元测试（382 tests 内）

1. `backpressure wait returns immediately on stop with a full queue`：
   queue cap=1，填满后 `q.stop=true`，第二次提交在 <2 s 返回 false，
   `deferred_timeout=1`；
2. `backpressure deadline ends the wait without a consumer`：cap=1、填满、
   `q.deadline=now`，提交立即返回 false，`deferred_timeout=1`。

两条路径都不依赖 trace worker 存在。

## 集成测试

| 场景 | 配置 | 结果 |
|---|---|---|
| stop_reason 中途置位 | `--rss-limit-mb 1`，120 s，queue 8 | rc=0，summary 写出，`stop_reason=memory`，baseline 16/16 |
| 队列非空 + drain | queue 8，trace-workers 1，50% 采样 | 正常退出，deferred_close=0 |
| 无消费者 + drain 超时 | `--trace-workers 0`，duration 10 | rc=0，summary 写出，无挂死（monitor 在 drain deadline 关闭队列） |

`monitor` 每 2 s 把 `q.stop` 设为 `stop_reason != ""`；等待循环每 10 ms
检查 `q.stop`/`deadline`；`drain_deadline` 到期时即使没有 trace worker 也会
置 `q.closed=true`。

## 边界

- 集成测试的 duration 短（10–120 s），drain grace 固定 240 s；真正的
  240 s 超时路径由 monitor 的 deadline 分支覆盖，没有单独跑满 4 分钟；
- `--trace-workers 0` 是人为极端配置，正常 campaign 不会这样跑。
