# Discovery E1/E2：产物校验与失败分桶

Date: 2026-11-23. Pin 不变。

## E1

`scripts/discovery_validate.sh` 在 `/tmp` 副本上：

- 对 21 个 wasm-gc build 成功的包找 `_build/wasm-gc/**/*.wasm`，用
  `node WebAssembly.validate` 校验；
- 对 21 个 wasm-ok 包跑 `moon test --target wasm-gc` 和 `js` 对照；
- assertion 失败不算候选。

结果：

```json
{"N":94,"pkgs_wasm_ok":21,"wasm_artifacts":6,
 "invalid_artifacts":0,"invalid_packages":[],
 "test_attempted":21,"test_compile_fail":3,
 "differential":1,
 "differential_packages":["oracle_cases/miscompile/415"]}
```

- build 阶段没有 invalid artifact；
- test 阶段 3 个 compile fail，其中 **415** wasm 失败且 js 通过；
- 415 是已知 issue/正控，不是新候选。

## E2

69 个 wasm 失败：

```json
{"buckets":{"missing_dep":0,"old_syntax":0,
 "wasm_only":1,"other_backend":68},
 "error_codes":{"3005":45,"4037":15,"4023":2,"4156":2,"no_code":5}}
```

- **唯一 wasm-only 差分包：`oracle_cases/miscompile/1051`**，
  wasm 首错 `Error: [4156]`，js rc0；1051 是 known/curated，不是新发现。
- 其余 68 个两边都失败；没有 missing_dep/old-syntax 桶，因为保留了本地
  `.mooncakes`，失败以 3005/4037 为主。
- 本轮新候选 0；瓶颈是语料/后端差异密度，不是“没有缺陷”。
