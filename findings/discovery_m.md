# Discovery M：formatter oracle 与 F13 定案

Date: 2026-11-24. Pin 不变。

## M1 F13 定案：REAL

命令：

```bash
printf 'fn main { println(-(-2147483648)) }\n' > /tmp/f13.mbt
moonfmt /tmp/f13.mbt -o /tmp/f13.fmt.mbt   # rc0
moon check /tmp/f13.fmt.mbt                 # rc1, Error [4095]
```

输出：

```moonbit
///|
fn main {
  println(--2147483648)
}
```

原因：formatter 删除括号后把两个一元 `-` 合并成 `--`，输出不能按原语义
重解析；`-(-1)` 负控 fmt 后可 check rc0。分类 **REAL**，作为 formatter oracle
正控；这不是“更好看”问题。

## M2 检测器

入口：`$HOME/.moon/bin/moonfmt`，即 `moon fmt` 的 formatter binary；
standalone `moonfmt FILE -o OUT`，解析检查 `moon check OUT`。

判据：

- idempotence：fmt(fmt(x)) == fmt(x)；
- token：去掉自动 `///|` 文档行和所有空白后比较；字符串/注释/标识符/数字
  保留；已知 formatter 规范化（`derive`→`#derive`、`Int`→`Int32`）会报 token
  变化，需人工归为非缺陷；
- parse：`moon check` rc0；
- test：本轮未跑包级前后测试（0）。

自检：把 `println` 改成 `print`，token 判据报红；删 `)`，`moon check` 报红。

```json
{"broken_fmt_rc":0,"broken_check_rc":1,"token_diff":1}
```

## M3 语料扫描

实际只完成 **10 files**（400 包扫描因 `moonfmt` 在超大文件上长跑、`moon check`
太慢而超时，未完成；不虚报）：

```json
{"files_attempted":10,"fmt_rc_nonzero":0,
 "idempotence_violations":0,
 "token_violations":6,
 "unparseable":0,
 "test_regressions":0,
 "selftest":{"broken_fmt_rc":0,"broken_check_rc":1,"token_diff":1}}
```

6 个 token 变化均是已知 formatter 规范化（`derive(Show,Eq)`→`#derive(...)`、
`Int`→`Int32`），不是新缺陷；F13 的括号/`--`变化另计。

## M4 结论

- F13 = REAL，formatter 正控成立；
- 检测器自检 token/parse 均报红；
- 10 文件里无 F13 之外的 REAL 违例；无新 candidate；
- 400 文件扫描未完成，是覆盖缺口；下一步需先排除已知规范化并把
  `moon check` 改包级/超时更短，再跑 400。
