# Candidate F13：formatter 删除一元负号必需括号

Date: 2026-11-24. Pin: `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. **未提交上游**；只读查重。

## 最小 repro

```moonbit
fn main { println(-(-2147483648)) }
```

## 复现 3 次

命令：

```bash
printf 'fn main { println(-(-2147483648)) }\n' > /tmp/f13.mbt
moonfmt /tmp/f13.mbt -o /tmp/f13.fmt.mbt
moon check /tmp/f13.fmt.mbt
```

结果 3/3：

```text
moonfmt rc=0
moon check rc=1
Error: [4095]
```

输出：

```moonbit
///|
fn main {
  println(--2147483648)
}
```

`moon check` 文本以 `Error: [4095]` 开头；fmtted 源码把两个一元 `-` 合并为
`--`，不能按原语义重解析。

## 查重

- `issues/curated.json`：无 formatter/unary minus/F13 条目；
- GitHub search（只读，未评论/未发 issue）：
  - query `repo:moonbitlang/moon formatter unary`
  - query `repo:moonbitlang/moonbit-docs formatter unary`
  - 结果只命中 1369 “unary plus 打成 `~+`”，无 unary minus 括号删除；
- 与 1369 关系：同 formatter 子系统，但症状不同（1369 是 unary plus 打印成
  `~+`；F13 是去掉必需括号导致 `--`、重解析 4095），因此是**独立条目**。

## 状态

候选：REAL、pin 上 3/3、不在 curated/已查上游重复。未提交上游。
