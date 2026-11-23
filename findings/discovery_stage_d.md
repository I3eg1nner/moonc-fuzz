# Discovery stage D：预注册

Date: 2026-11-23. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. 本文件先 commit，之后不再改判据。

## 假设

1. 双后端 wasm-gc 与 js 的产物/运行时差异中存在未被 curated 覆盖的真缺陷；
2. 大量包编译失败中，只有 `CompileError + WebAssembly.Module` 才是 invalid-wasm
   候选；普通语法/类型错误不是缺陷；
3. 415 是已知 issue，只作正控，不计新发现。

## Oracle

- pkg lane：`rc!=0` 且 stderr 同时含 `CompileError` 和 `WebAssembly.Module`
  → `kind=INVALID_WASM`，走 `save_pkg_witness` → triage；confirmed 必须能重放。
- 非该组合的编译错误 → 不 confirmed。
- 干净包 → 不生成 witness。
- 415 正控必须 confirmed；但归类 known issue。

## 语料

- 包根：`~/.moon/lib`、`poc/`、`oracle_cases/`、`regressions/` 中带
  `moon.mod` 的目录；零网络 registry 快照若存在一并计入。
- 当前本机计数 N（见 D2 报告）；N<50 时用模板 + 定向变异补足，不拿少数包
  硬跑后报 yield。

## 预算

- 2 h × 32 workers；每包先 build wasm-gc/js，能跑 test 的加 test。
- 超时/截断/ICE 与 invalid-wasm 分开计数。

## 成功判据

候选必须同时满足：

1. 最小化后 <20 行；
2. pin 上失败；
3. js 上通过；
4. 不在 `issues/curated.json`；
5. 不在已知上游 issue 表；
6. 去重规则：signature + 根因；同根因只留一条；
7. 失败即负结果，不改判据。

## 非目标

- 不声称编译器无缺陷；
- 不把普通编译错误、已知 415、setsid/cgroup 限制算发现；
- 不新增 `.py`，不改 pin，不发上游。

## Amendment 1（方法修订，不改判据）

原 pilot 只跑 `moon build`，不能判别 invalid-wasm；415 在 test 加载阶段才失败。
方法改为：wasm build 成功后用 `WebAssembly.validate` 校验所有 `.wasm`，并对
可测包跑 `moon test --target wasm-gc`，与 js 对照。成功判据不变；这只是测量
方法修正，不是改判据。
