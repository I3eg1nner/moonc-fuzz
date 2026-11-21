# Edge 反馈 30 分钟 × 3 seeds（新身份空间）

Date: 2026-11-21. 依据：本轮 (2)。工具链 pin 未改。

## 配置

function vs func-edge，各 30 min、2 workers、T1/T2 20%、baseline 8（spread，
complete）、`--edge-cap 200000`、seed 1/7/2026；seed 主序、每批两臂并行。
CPU 用 GNU time `%U %S` 记录（不是 wall）。

## 逐 seed

| arm | seed | it | t2_ok | adds | new_edges | baseline | edge_status | collisions | CPU s | RSS MB |
|---|---|---:|---:|---:|---:|---|---|---:|---:|---:|
| function | 1 | 15,407 | 19 | 1,960 | 18,057 | complete | ok | 40,179 | 2,391.66 | 467 |
| function | 7 | 17,037 | 33 | 1,961 | 17,137 | complete | ok | 40,190 | 2,453.25 | 434 |
| function | 2026 | 15,951 | 21 | 1,825 | 16,682 | complete | ok | 40,182 | 2,431.34 | 469 |
| func-edge | 1 | 9,337 | 15 | 1,932 | 17,201 | complete | ok | 40,186 | 2,341.67 | 467 |
| func-edge | 7 | 10,230 | 24 | 1,964 | 16,831 | complete | ok | 40,134 | 2,355.07 | 436 |
| func-edge | 2026 | 10,426 | 17 | 2,013 | 17,721 | complete | ok | 40,171 | 2,360.11 | 467 |

中位数：

| arm | it | t2_ok | adds | new_edges | CPU s |
|---|---:|---:|---:|---:|---:|
| function | 15,951 | 21 | **1,960** | 17,137 | 2,431.34 |
| func-edge | 10,230 | 17 | **1,964** | 17,201 | 2,355.07 |

## 判读

- **edge 没死**：6/6 运行 baseline complete、`edge_status=ok`、未饱和，
  `new_edges` 17k–18k，说明这轮确实在测边新颖度，而不是 50k cap 截断。
- **奖励收益没有出现**：两臂 `adds` 中位数 1,960 vs 1,964（差 4 个函数，
  远小于 seed 内/间波动：function 1,825–1,961、func-edge 1,932–2,013）；
  `new_edges` 17,137 vs 17,201 同样交叠。
- **func-edge 的迭代吞吐更低**（中位 10,230 vs 15,951），CPU 却相近
  （2,355 vs 2,431 s）——同样的 CPU 预算下，edge 奖励把父本选择推向
  单位迭代更贵/更少迭代的路径，但没有换来更多新函数或新边。
  后续 300 s 分阶段计时把差距定位到 **T1 syncheck 单次成本**
  （38.9 vs 14.4 ms/it；mutate 相近、T2 <3 s），边记账不在该路径；
  父本输入分布为何更贵未测，见 `findings/phase_timing.md`。
- 结论：**在这组配置和 3 个 seed 下，没有可重复证据表明 edge 奖励提高新函数
  或新边产出**；它显著改变调度（吞吐），不改变产出。不能反过来说"edge 无效"，
  cap、输入分布和 seed 数都仍是边界。

## 边界

- 3 个 seed、单机；adds 的 seed 方差（±4%）与臂间差同量级，需要更多 seed
  才能给置信区间；
- CPU 是 user+sys，不含 qemu trace 的 wall 等待；两臂 trace 失败/丢弃数
  未在表中展开；
- 身份空间让 universe 约 40k 碰撞、100k+ key；200k cap 下未饱和，但更长的
  运行或更多 stage 可能再次触顶（届时 `edge_status=degraded_cap` 会显式出现）。
