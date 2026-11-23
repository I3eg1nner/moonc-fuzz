# Discovery D2/D4：语料计数与 pilot

Date: 2026-11-23. Pin 不变。

`scripts/discovery_pilot.sh` 扫描本机带 `moon.mod` 的包根：
`~/.moon/lib`、`~/.mooncakes`（若存在）、`poc/`、`oracle_cases/`、`regressions/`。

结果：

```json
{"N":94,"attempted":90,
 "wasm_fail":69,"js_fail":68,
 "webassembly_module":0,
 "wasm_ok":21,"js_ok":22,
 "wasm_ms_median":35,"js_ms_median":34}
```

- N=94 ≥50，无需模板替代；
- 双后端成功编译 21/22 包，成功构建中位 35/34 ms；
- 69/68 失败，绝大多数是缺依赖/普通编译错误；
- build-only 扫描中 `CompileError + WebAssembly.Module` = **0**；415 需要 test
  运行阶段才出现 invalid wasm。

D4 pilot 计数：

```text
attempted=90
wasm-gc 失败=69
其中 WebAssembly.Module=0
去重后候选=0
不在 curated 的候选=0
```

只报数，不下结论。失败率高的主因是 registry/依赖与旧语法，不是缺陷。
