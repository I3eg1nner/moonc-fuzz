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
