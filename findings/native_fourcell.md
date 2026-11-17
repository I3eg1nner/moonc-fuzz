# Native 四格：实现、正控与跨包结果

日期：2026-11-17。工具链：`moon 0.1.20261104`、`moonc v0.10.20+65efd5b93`。
实现：`cmd/optdiff`，`--target native --four-cell`。

> 这是差分检测链和负证据记录，不是 native 优化器正确性证明。逐 artifact 数据在 `findings/native_fourcell_data.json`。

## 1. 实现

native 路径与 wasm 的差异：

- `moonc link-core` 产出 `.o`，再由 `/usr/bin/cc` 链接成测试 `.exe`；
- 没有 `moonrun`；运行时参数直接跟在 `.exe` 后面；
- `cc` 参数含 `$MOON_HOME`，适配器把它展开为实际的 MoonBit home；
- native 的 build 维度也真实存在：删除 default 树旧 core 后，37/45 个 core 的 O0/default 哈希不同；
- 四格仍然是 `B0L0` / `B0Ld` / `BdL0` / `BdLd`，`default` 是省略 `-O0`。

新增的解析/执行单元测试覆盖：

- native test-id 的 `/` 路径与右开区间；
- `.o` / `.exe` stem 配对；
- `cc` 的 object/exe 替换和 `$MOON_HOME` 展开；
- native runtime 行解析。

## 2. 正控与 A/A

`argparse` 的 link 注入正控：

```
--target native --four-cell-control argparse/help_render.mbt 'Usage: ' 'Use: '
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

`argparse --four-cell --repeats 2 --aa`：

```
3 artifacts, 0 candidates, 0 errors, exit=0
```

## 3. 跨包扫描

对 `seeds/` 下 142 个含 `moon.pkg` 的目录逐个运行：

```bash
optdiff --module /data/audit/mbtfuzz/seeds \
  --out /tmp/eval-native-all/<tag> \
  --packages moonbitlang/core/<rel> \
  --target native --four-cell --repeats 1
```

12 路并行，约 3–4 min，临时目录约 5 GB。

分类：

| 结果 | 数量 |
|---|---:|
| 进程 exit 0 | 109 |
| 进程 exit 1（候选） | 1 |
| 进程 exit 2 | 32 |
| 有有效 artifact 的包 | **111** |
| 有效 artifact | **184** |
| 有效 test ID | **9,249** |
| 确认 candidate | **0** |

失败分类：

| 类型 | 数量 | 说明 |
|---|---:|---|
| `cannot parse native runtime commands` | 28 | 没有可重放的 native test driver / 零测试 |
| baseline 不绿 | 4 | `async/fs`、`async/socket`、`diff`、`test` |
| 候选待复核 | 1 | `async/http` |

## 4. async/http 候选：网络环境误报

首轮 `async/http`：

```
http.blackbox_test: changed=3
  link_changed=0
  build_changed=1
  both_changed=2
```

差异测试：

```
README.mbt.md|1        pass -> "Name or service not known"
client_test.mbt|1      pass -> "Temporary failure in name resolution"
proxy_test.mbt|2       pass -> "ProxyError"
```

对应测试访问 `https://www.moonbitlang.com` / `http://www.example.org`，并依赖 DNS。用同一命令、同一 HEAD 复核：

```
--target native --four-cell --repeats 3 --aa
2 artifacts, 0 candidates, 0 errors, exit=0
```

结论：**不确认**为编译器缺陷；属于外部网络/异步测试的环境波动。没有做网络隔离或 mock，因此不能把它当作 native 优化器 bug。这个案例也说明：对访问外部网络的包必须至少 `--repeats 2 --aa`，否则首轮候选不能进入缺陷表。

## 5. 解释与边界

- 111 包、184 artifact、9,249 test ID 是当前 native 的有效负证据分母；
- 0 个确认候选只说明“这批包/测试/这一轮重复下没有观察到状态差异”；
- 没有 branch/edge 覆盖，也没有随机输入；测试仍是固定断言；
- native 的 `default` 只表示省略 `-O0`，不是显式 `-O2`；
- 正控是 harness 注入，不是优化器缺陷；
- 仍有 28 个包没有 native runtime，4 个 baseline 不绿，未计入零候选；
- 完整 111 包没有全部做 `repeats>=2`；只有候选和 `argparse` 做了 A/A。全量稳定性仍需单独实验。

## 6. repeats=2 + A/A 稳定性复核

对首轮有 artifact 的 111 个包重跑：

```
--target native --four-cell --repeats 2 --aa
111 packages
184 evidence rows
9,249 test IDs
0 candidates
0 changed
```

结果：

- 110/111 包 exit 0；
- `moonbitlang/core/diff` 的 blackbox baseline 仍不绿（与首轮一致，不是候选）；
- `async/http` 的首轮网络候选在 A/A 下消失；
- 没有任何 artifact 在重复 B0L0 之间出现不稳定状态。

这是当前最强的一组 native 负证据：不仅零候选，而且 A/A 没有暴露重复性错误。仍不能证明优化器正确；`diff` 的 blackbox 没有进入有效比较。
