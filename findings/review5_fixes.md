# 第五轮复核 P0/P1 修复

Date: 2026-11-21. 工具链 pin 未改。

## P0-1 sem3 观测不再静默跳过

每个 target 现在有独立 `Obs{class, out, rc}`，分类：
`ok / trap / compile_error / ice / runtime_error / timeout / truncated`。
规则：

- 正常族：三个后端必须**全部 class=ok** 且与 expected 逐行一致才 pass；
  任一后端 compile_error/ICE/timeout/truncated → 落 `inconclusive/` 证据；
- 一个后端 ok、另一个 trap → **witness**（真实后端分歧），不是 inconclusive；
- `array_oob`：每个后端必须 `class=trap`（真正执行并 trap），compile_error
  或 timeout 不算 pass；
- 保存失败 → 打印错误并 `exit 2`，不再静默。

本轮立刻暴露了两类此前被吞掉的东西：

- `expr_i64` 含移位的树曾因右操作数渲染成 Int64 而 compile_error（9/10 被
  旧逻辑静默跳过）；修 render 后归零；
- **`min / -1` 的后端分歧**（Int32/Int64）：js wrap，wasm-gc/native trap。
  按 `moonbitlang/core` int 文档，该情形"no portable result… may abort or
  get an arbitrary value"，因此归为 **allowed_impl_divergence**，不是
  compiler inconsistency；详见 `findings/int_min_divergence.md`。

## P0-2 witness 持久化

`cmd/sem3` 的 `ensure_dir` 改为真正递归（先建父再建自己）；`save_case`
写入后逐文件 `path_exists` 校验，**写成功才计数**，失败 exit 2。单测
`first write into a nested witness directory is durable`。旧目录计数与目录
数不一致（54 vs 53 等）由这个 bug 解释。

## P0-3 TEST_FAIL 的 replay 命令

`save_pkg_witness` 增加 `cmd` 参数并写 `cmd`/`build_cmd`/`run_cmd`：
TEST_FAIL 保存 **run argv**（`test --target ...`），BUILD_FAIL/ICE 保存
build argv。triage capsule 模式继续按 `cmd` 重放，因此 TEST_FAIL 现在重跑
原 test，而不是 build 命令。

## P1-4 跨后端分类

同 failed 计数不再直接判 none：比较失败测试的**身份行集合**；集合相同 →
none，不同 → witness。已知后端差异的排除词仍作用于原始 diff（未逐测试
应用，仍是边界）。

## P1-5 sem3 参考值与口径

- 32 位 Div/Mod 在 expected 里也做 wrap；
- `te_render64` 的移位右操作数按 Int 渲染（核心接口要求 Int32）；
- 新增 `--seed` 与 `unique_programs`（按源码 sha1），cases 不再当 unique；
- i64 的 expected 仍用宿主 Int64（wrap 语义与三后端探测一致），这是
  "参考值独立性"的剩余弱点，未假装解决。

## 口径

- "未观察到稳定收益" ≠ "已证明无差异"；
- "窄域三后端差分能力已建立" ≠ "9,448 个完备 case 通过"；cases 里有重复、
  域很窄，且本轮还抓到自己的 render/oracle bug。
