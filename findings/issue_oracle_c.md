# issue→oracle C：L1/L2 灵敏度与 fixed 门禁

Date: 2026-11-22. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. A/B 的 26 条资产见
[`issue_oracle_a_b.md`](issue_oracle_a_b.md)；本文件只做 C。

## 1. L1 判定灵敏度（机器判定，不靠人眼看 stderr）

`scripts/issuecheck.sh` 读 `issues/curated.json` 和
`oracle_cases/<category>/<issue>/`，逐条跑 command，按 `assertion` 的
kind/value 判定，输出 JSONL（issue/status/category/detected/oracle/reason/
evidence/rc）。

```
# 默认（跳过 1366 OOM、1155 256MB 两个 heavy case）
bash scripts/issuecheck.sh /data/audit/mbtfuzz /tmp/ic.jsonl /tmp/ic.json
# 全量（含 heavy）
bash scripts/issuecheck.sh /data/audit/mbtfuzz /tmp/ic.jsonl /tmp/ic.json --heavy
# 正控制：改坏 1328 的 assertion value，必须失败
bash scripts/issuecheck.sh /data/audit/mbtfuzz /tmp/ic_t.jsonl /tmp/ic_t.json --tamper
```

| 运行 | reproduced evaluated | detected | sensitivity | fixed evaluated | fixed pass |
|---|---:|---:|---:|---:|---:|
| 默认（heavy 跳过） | 10 | 10 | **100%** | 9 | 9 |
| `--heavy` | 11 | 11 | **100%** | 10 | 10 |
| `--tamper`（1328 assertion 改成 `1`） | 10 | 10 | 100% | 9 | **8**（按预期失败） |

L1 100% 的含义：11 条 reproduced 的原签名/原行为都能被机器判定识别，且
每条都记录命中的 oracle 与签名；没有一条靠人眼读 stderr。

## 2. L2 重发现灵敏度

预算是 **每条 300 次执行或 300 s，先到为准**，不喂原输入（自定义 mutator
按 sha1 排除原文件；seedfuzz 的 baseline 只用于 known 判定）。

| issue | category | runs | 同签名 hits | L2 rediscovered | 未识别原因 |
|---|---:|---:|---:|---|---|
| 1364 | crash_ice | 300 | 300 | **yes** | — |
| 1365 | crash_ice | 270 | 150 | **yes** | — |
| 1367 | crash_ice | 243 | 92 | **yes** | — |
| 1366 | crash_ice | 0 | 0 | no | `precondition_unavailable`：seedfuzz 在 OOM seed 上崩溃，未产生结果 |
| 1368 | crash_ice | 282 | 0 | no | `precondition_unavailable`：文本变异没有保住 export-closure 包形状 |
| 1340 | crash_ice | 0 | 0 | no | `precondition_unavailable`：seedfuzz 对 package seed SIGSEGV |
| 1344 | crash_ice | 0 | 0 | no | `precondition_unavailable`：seedfuzz 对 package seed SIGSEGV |
| 1322 | crash_ice | 0 | 0 | no | `precondition_unavailable`：seedfuzz 对 script seed SIGSEGV |
| 1369 | formatter | 296 | 0 | no | `no_predicate`：seedfuzz 的 build oracle 不判 formatter reparse |
| 1372 | lsp | 1 | 0 | no | `precondition_unavailable`：seedfuzz 忽略 LSP JSON request |
| 1376 | lsp | 0 | 0 | no | `precondition_unavailable`：seedfuzz 对 LSP framing seed SIGSEGV |

**L2 = 3/11 = 27.3%。** 这是本轮最重要的负结果：L1 100% 而 L2 27.3%，
说明 oracle 会分类，但现有 seedfuzz 只覆盖单文件 `.mbt` 的一部分；package /
LSP / formatter 形态还没有可用的变异 campaign。

原始结果：`issues/l2_results.json`；seedfuzz 日志在 `/tmp/issue_l2/`。

## 3. category × 灵敏度

| category | reproduced | L1 detected | L2 rediscovered | 未识别原因（L1/L2） |
|---|---:|---:|---:|---|
| crash_ice | 8 | 8 | 3 | L1 无；L2 5 条：1366/1368/1340/1344/1322 |
| formatter | 1 | 1 | 0 | L1 无；L2 1369 `no_predicate` |
| lsp | 2 | 2 | 0 | L1 无；L2 1372/1376 `precondition_unavailable` |
| **合计** | **11** | **11** | **3** | — |

## 4. fixed 门禁：`issue_regress`

新增 `cmd/accept` 门禁 `issue_regress`：

- 负控制：默认 `issuecheck` 必须 rc 0；`reproduced_evaluated=10/10`、
  `fixed_evaluated=9/9`（heavy 跳过 1366/1155）。
- 正控制：`--tamper` 把 1328 的 assertion value 改成 `1`，必须 rc != 0。
- 单独跑 heavy：`--heavy` 时 11/11、10/10，不进入默认 gate。
- 1328、1326、1155 上游仍 open，断言是 **pin_expected**：
  - 1328：source line 6（`nz + 0.0`）对应 stdout line 2，值为 `0`；
    依据 IEEE 754-2019 §6.3（(-0)+(+0)=+0）。
  - 1326：native release 三行 `80000001 / 2147483649 / 40000000`；
    依据 JS/unsigned 参考。
  - 1155：`actual length = 268435456`；依据数组长度不截断。
- 1366 的 OOM 与 1155 的 256MB 不进默认路径，必须 `--heavy` 单独跑。

实测：

```
accept: checks=25 ok=true skipped=[]
issue_regress: normal_rc=0 tamper_rc=1
```

## 5. 172 条 triage

`issues/triage_172.md` 是 172 行 keep/drop 理由表。分布：

| decision/reason | 数量 |
|---|---:|
| keep（curated，有可执行 repro + assertion） | 26 |
| drop：feature/performance，无正确性谓词 | 29 |
| drop：crash 形态但无最小/自包含复现 | 36 |
| drop：超出范围或无最小复现 | 59 |
| drop：文档 | 7 |
| drop：LSP feature request，非挂死/崩溃 | 6 |
| drop：环境/工具链/平台 | 9 |

## 6. `.py` 例外更正

主分支实际有 **20 个已跟踪 `.py`**，此前“无 `.py`”的说法是错的。更正为：
MoonBit 实现（`moonbit/**`）与 accept 路径无 `.py`；20 个例外是
15 个 vendored ldif 脚本、3 个 PoC LSP replay、2 个 scratch probe。
清单与证据见 [`python_inventory.md`](python_inventory.md)；`issuecheck` 是新
shell gate，不新增 `.py`。

## 7. 边界

- L1 的 100% 是对 11 条 curated reproduced 的判定，不是对所有 172 条粗筛。
- L2 只做了 3 条自定义变异的正结果；其余是 seedfuzz 的形态/崩溃限制，不能
  外推为“这些缺陷不可变异重发现”。
- 1328/1326/1155 的 `fixed` 是 **pin_expected**，不是 upstream fixed。
- 未发上游 issue/comment，未改 pin。

## Evidence

- `scripts/issuecheck.sh`、`issues/curated.json`
- `oracle_cases/**`（case.json 的 `bug_symptom`/`pin_observed`/`assertion`）
- `issues/l2_results.json`、`issues/triage_172.md`
- `findings/python_inventory.md`
- accept `issue_regress` gate
