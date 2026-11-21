# 稳定 feature 空间：给边加 binary/config/mode 身份

Date: 2026-11-21. 依据：本轮第 1 项。工具链 pin 未改。

## 变化

边 key 从裸 TB pair（`pc0,pc1`）改为
`<mode>|<config_hash>@<pc0>,<pc1>`。`config_hash` 本身由 `moonc` 的
file_sha1、`all_pkgs`、builtin/prelude `.mi`、`pkg_config`、target 组成，
T1/T2 任务还会追加 `|entry=<stage>`，所以同一个裸 pair 在不同编译器/配置/
阶段下不再合并。

新增统计：

- `edge_collisions`：同一**裸** key 出现在两个以上身份下的数量（旧全局空间
  会静默合并它们）；
- `edge_status`：`ok` 或 `degraded_cap`；到 cap 时后者显式出现，不再只用
  `new_edges=0` 表示；
- `edge_keys`：现在是身份空间里的 key 数（会比裸 key 多）。

## 四段确定性控制（单测，cap=8）

| 步骤 | 期望 | 结果 |
|---|---|---|
| baseline A：`{p1,p2,p2,p3}` 同一身份 | 计 2 | 通过 |
| 候选 B：`{p3,p4}` 同身份 | 计 1 | 通过 |
| 同名 raw pair 换 config 身份 | **算新**，并计 collision | 通过 |
| 填到 cap 后再加新边 | 返回 0，`edge_status=degraded_cap` | 通过 |

另有断言：`new_edges>0` 时父本能量确实增加（奖励路径可达）。

## 真实运行（120 s，2 workers，T1/T2 5%，edge-cap 200000，deep-p 20）

```json
{"it":2615,"baseline_state":"complete","edge_keys":104991,
 "edge_saturated":false,"edge_status":"ok","edge_collisions":39347,
 "edge_new_baseline":104937,"edge_new_t1":54,"new_edges":54,
 "deep_t3_attempts":536,"deep_t3_distinct":536,"deep_t3_mismatch":0}
```

- **collisions=39,347**：T1 与 T2 的 raw 边大量重叠但身份不同；旧空间把它们
  压成一份，掩盖了"哪条 lane 贡献了哪条边"。身份化不是减少 key，而是**放大**
  universe（约 1.6×，105k vs 65k 量级），因为同一裸边在不同配置下各存一份；
  这会**更早**碰到 cap，不是更晚。
- 200k cap 下仍未饱和；
  `new_edges` 54 全部来自 T1，T2 trace 在这轮没有新增。
- deep lane 同轮 536 个 distinct T3 matched、0 mismatch，和 `edge_*` 计数
  互不影响。

## 为什么这条 summary 的 coverage_adds=0

不是覆盖学习停了，也不是 cap 拒绝：`coverage_written=9`、`coverage_cap=4000`、
`coverage_skipped=0`，预算远未用满；`baseline_state=complete`。真正原因是
trace 采样：17 条完成的 trace 里 16 条是 baseline，12 条失败（日志上限）、
46 条被队列丢弃，几乎没有候选 trace 进入 `trace_apply_delta`，所以没有
可计的新函数。该运行的深阶段证据来自 `deep_t3_*`（536 distinct），不是
coverage_adds。

## 边界

- 身份化会放大 universe（约 1.6× 于同配置裸集），cap 需要按此调大；
- `config_hash` 只覆盖二进制/核心包/入口，不覆盖环境变量与宿主；
- `edge_collisions` 只按裸 key 首次冲突计数，不区分冲突的双方身份组合；
- 到 cap 的 `degraded_cap` 只在单测里固定验证，尚未跑一条真实饱和 run
  （真实饱和需要把 cap 设小，见 `findings/edge_saturation.md` 的 50k 实验）。
