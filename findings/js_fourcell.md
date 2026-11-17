# JS 四格：实现、正控与跨包结果

日期：2026-11-17。工具链：`moon 0.1.20261104`、`moonc v0.10.20+65efd5b93`。
实现：`cmd/optdiff --target js --four-cell`。

> 这是差分检测链和负证据记录，不是 JS 后端正确性证明。逐 artifact 数据在 `findings/js_fourcell_data.json`。

## 1. 实现

JS 路径与 wasm 的差异：

- `moonc link-core` 产出 `.js`，由 `node --enable-source-maps <file.js> <test-args-json>` 运行；
- test args 是最后一个 JSON 参数，不是 `moonrun --test-args`；
- 四格仍是 `B0L0` / `B0Ld` / `BdL0` / `BdLd`，`default` 是省略 `-O0`；
- `parse_runs` 同时接受 `.wasm` + `--test-args` 和 `.js` + 末尾 JSON；
- `target_ext` 决定重复链接产物是 `.wasm` 还是 `.js`。

新增测试覆盖：

- `target_ext("js") == ".js"`；
- node 命令的 `.js` 索引和 JSON test args 解析。

## 2. 正控

```bash
optdiff --module /data/audit/mbtfuzz/seeds \
  --out /tmp/js-control \
  --packages moonbitlang/core/argparse \
  --target js \
  --four-cell-control argparse/help_render.mbt 'Usage: ' 'Use: '
```

结果：

```
1 artifact
changed=156
link_changed=78
build_changed=0
both_changed=78
candidates=1, errors=0, exit=1
```

## 3. 跨包扫描

对 142 个含 `moon.pkg` 的目录逐个运行：

```bash
optdiff --module /data/audit/mbtfuzz/seeds \
  --out /tmp/eval-js-all/<tag> \
  --packages moonbitlang/core/<rel> \
  --target js --four-cell --repeats 1
```

12 路并行，约 2 min。

分类：

| 结果 | 数量 |
|---|---:|
| 进程 exit 0 | 102 |
| 进程 exit 2 | 40 |
| 有 evidence 的包 | 103 |
| artifact | 173 |
| test ID | 9,031 |
| candidates | **0** |

失败分类：

| 类型 | 数量 | 说明 |
|---|---:|---|
| `cannot parse four-cell runtime commands` | 35 | 没有可重放的 JS test driver / 零测试 |
| 其他 async 运行问题 | 3 | `async/raw_fd`、`async/shell` 等 |
| baseline 不绿 | 2 | `diff`、`test` |

## 4. 机制活性

对 173 个有 evidence 的 artifact，四个 JS 产物的完整文件哈希都不同：

```
173 / 173 artifact 的四臂输出不是同一个文件
```

JS 产物大小比（相对 `B0L0`）示例：

```
0.946 / 0.960 / 0.899
1.000 / 1.339 / 1.336
0.970 / 0.964 / 0.931
```

这说明 build/link 两维都真实改变 JS 产物；零候选不是“所有臂跑同一份文件”。

## 5. 边界

- 0 candidate 只说明这批包/测试/这一轮下没有观察到状态差异；
- JS 测试仍是固定断言，不是随机输入；
- `default` 是省略 `-O0`，不是显式 `-O2`；
- 正控是 harness 注入，不是 JS 后端缺陷；
- 35 个包没有 JS runtime，2 个 baseline 不绿，未计入零候选；
- 首轮 `repeats=1`；全量稳定性由单独的 `repeats=2 --aa` 实验记录。

## 6. repeats=2 + A/A 稳定性复核

对首轮有 evidence 的 103 个包重跑：

```
--target js --four-cell --repeats 2 --aa
103 packages
173 evidence rows
9,031 test IDs
0 candidates
0 changed
102/103 包 clean
```

`moonbitlang/core/diff` 的 blackbox baseline 仍不绿（与首轮一致），不进入有效比较。
没有任何 artifact 在重复 B0L0 之间出现不稳定状态。

这是 JS 侧的负证据；仍不能证明 JS 后端正确，测试仍是固定断言。
