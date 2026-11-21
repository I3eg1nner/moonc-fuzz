# 未知候选的晋级条件（第四轮复核 2/3）

Date: 2026-11-21. 工具链 pin 未改。

## 修的两处

1. **minimize 只在支持的 stage 要求**：`t1` 映射到 `syncheck`，而归约器只支持
   `check/build/test`；旧逻辑因为 fuzz 总传 `--minimize` 而把这类候选判
   flaky。现在 `minimise_required = 支持的 stage && 传了 --minimize`；
   capsule 包模式不做单文件归约，也不因此 flaky。
2. **归约必须复现原缺陷**：minimize 调用补上 `--target wasm-gc`；归约发布后，
   triage 把 reduced 写进新包、用原 stage/预算重跑，要求 rc≠0、签名仍是
   crash 且与候选 `signature` 一致，否则 `minimised=false`、
   `minimise_note="reduced did not reproduce"`。

## 判定表（纯函数测试）

`triage_status(defect=true, timeout=false, reproduced=3, control_clean=true,
known=false, minimise_required=false, minimised=false)` → `confirmed`；
同一输入 `known=true` → `known`；`reproduced=2` → `flaky`。

## 未完成的验收：真实未知 witness → confirmed

要求用"真实 save_crash 产出的、未知的稳定 T1/T2"做正控。本轮没有找到合格
样本：

- 仓库里的 ICE 都落在 known 表（F2/F3/F4/F7/F8/F9）；
- F1/F1b 是 `moon.pkg` 的 SIGSEGV，当前 triage 的单文件 replay 不能复现
  （它跑 `moonc syncheck main.mbt`，不是 pkg 文件）；
- 手工试了 `#valtype` + Map/Set/Array 变体，Map/Array 正常，Set 是普通类型
  错误（4018），不是 ICE。

因此 confirmed 路径目前只有单元级证明，**没有**端到端未知 witness 证据；
这是下一轮要补的（pkg 级 replay 或找到表外 ICE），不写成已完成。
