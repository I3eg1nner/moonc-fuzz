> 历史文档：部分计数/命令已过期，以 `findings/handoff_final.md` 的 P0-4/P0-2 为准。

# J2：original-config package replay

Date: 2026-11-23. Pin 不变。

## 实现

`save_pkg_witness` 在 `findings/.../<sig>/` 下新增：

```text
original/
  moon.mod
  moon.pkg
  source.mbt
  argv.txt
  manifest.json   # sha1 of the four files
```

`capsule.json` 带 `"original":"original"`；witness 同时保留 `pkg/` 快照。
replay 始终从 `original/` 复制到全新临时目录，不读 live 包。

## Gate

`scripts/original_config_replay.sh` 构造一个 TEST_FAIL 包：

```moonbit
test "fail_case" { assert_eq(1, 2) }
```

保存 snapshot + manifest，随后：

- 3 次 fresh replay：比较 rc、stdout/stderr（含 test 名和
  `FAILED: `1 != 2`` 断言文本）；
- 正控制 1：改 live 包的 test 为通过，replay 仍用 snapshot并通过；
- 正控制 2：改 snapshot 的断言为 `assert_eq(2, 2)`，replay 报 mismatch。

实测：

```json
{"saved":1,"replayed":3,"matched":3,
 "expected":"FAILED: `1 != 2`",
 "live_mutation_still_match":1,
 "tamper_mismatch":1}
```

`original_config_replay` gate 通过；detail 带 saved/replayed/matched 和
live/tamper 控制。

## 边界

- gate 用 fixture 重现 witness 布局，覆盖 replay 协议；实际 `save_pkg_witness`
  的 original snapshot 代码已编译，但本 gate 不依赖真实 campaign 生成一个
  TEST_FAIL witness。
- 比较的是 rc + 完整 stdout/stderr（含 test 名/断言文本），不是只比签名。
- 没有改 pin，没有发上游，没有新增 `.py`。


## J2b end-to-end

`original_config_e2e.sh` 用 `regressions/pkg_semantic/f8_30/pkg` 跑小预算
package campaign，真实写出 witness：

```text
findings/build/BUILD_FAIL/<sig>/original/{moon.mod,moon.pkg,source.mbt,argv.txt,manifest.json}
```

- manifest 的四个 sha1 全部匹配；
- 从 snapshot `pkg` + `original/source.mbt` 在 3 个 fresh 目录 replay，
  3/3 相同 rc/签名；
- gate `original_config_replay` detail 的 `e2e=1`；另有独立
  `original_config_e2e` gate。

实测：`{"e2e":1,"replayed":3,"matched":3,"baseline_mismatch":1}`。
manifest 对 `moon.mod/moon.pkg/source.mbt/argv.json/paths.json/expected.json`
逐项非空校验；e2e replay 读 `argv.json` + `paths.json` + `expected.json`，
不读 argv.txt，不硬编码 build-only。`baseline_mismatch=1` 是负控：把
`source.mbt` 换成 baseline 后 rc/错误码不一致。


## TEST_FAIL 收尾

`original_config_e2e` 不再自己比 rc/FAILED，直接调用 `cmd/triage --case`；
normal `confirmed 3/3`、stage=test；expected/name/baseline 三个负控都不是 confirmed。
campaign 级 TEST_FAIL 生成仍受 mutator 限制，独立缺口。
