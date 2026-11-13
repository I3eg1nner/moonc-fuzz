# 证据：编译器公开源码的状态（2026-11-11 采集）

## 1. 仓库与许可证

- 仓库：https://github.com/moonbitlang/moonbit-compiler
- 许可证文件：`LICENSE.TXT` = *MoonBit Public Source License, Version 1, 11 December 2024*
  - 自制许可，非 OSI 认证，正文含 "we chose the relaxed SSPL instead of a fully permissive..."
  - 单独条款："Artifacts produced by the MoonBit compiler may be licensed by the user under any terms"
- 顶层结构：`src/` `dune-project` `moonbit-lang.opam` `install.ts` `README.md` `LICENSE.TXT`

## 2. 源码快照版本（关键）

```
$ curl -L -o main.tgz https://codeload.github.com/moonbitlang/moonbit-compiler/tar.gz/refs/heads/main
$ tar xzf main.tgz && cd moonbit-compiler-main
$ find src -name '*.ml*' | xargs wc -l | tail -1
 202232 total
$ cat src/git_commit.ml
let date = "20250312"
let short_version = "a7a1e9804"
```

- `commits/main.atom` 的最后更新：**2025-09-29T06:05:47Z**
- 文件数：276；`src/*.ml`：263

## 3. release tag 指向旧树

```
$ curl -s https://github.com/moonbitlang/moonbit-compiler/releases.atom | grep -E '<title>|<updated>'
  <updated>2026-11-02T03:48:33Z</updated>
  <title>MoonBit WASM Compiler v0.10.19+97801ee1b</title>
  <updated>2026-10-29T02:21:04Z</updated>
  <title>MoonBit WASM Compiler v0.10.18+6c83a7f62</title>
```

下载 `v0.10.19+97801ee1b` 的源码树：

```
$ curl -L -o tag.tgz "https://codeload.github.com/moonbitlang/moonbit-compiler/tar.gz/refs/tags/v0.10.19+97801ee1b"
$ tar xzf tag.tgz && cat moonbit-compiler-0.10.19-97801ee1b/src/git_commit.ml
let date = "20250312"
let short_version = "a7a1e9804"
```

⇒ 2026-11 的 tag 与 2025-03 的源码树内容一致；release 资产是二进制（`moonbit-wasm.tar.gz` → `moonc.js` / `moonfmt.js`）。

## 4. 二进制属性

```
$ file ~/.moon/bin/moonc
ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, ...,
with debug_info, not stripped

$ readelf -S ~/.moon/bin/moonc | grep -E 'debug|symtab'
 .debug_aranges .debug_info .debug_abbrev .debug_line .debug_str .debug_loc .debug_ranges .symtab

$ nm ~/.moon/bin/moonc | wc -l
74399
$ nm ~/.moon/bin/moonc | grep -c ' T '
30411

$ strings ~/.moon/bin/moonc | grep -i 'opam-switch' | head -3
/root/.opam/idea-dev/.opam-switch/build/ocaml-variants.4.14.1+idea/otherlibs/unix
/root/.opam/idea-dev/.opam-switch/build/ocaml-variants.4.14.1+idea/runtime
/root/.opam/idea-dev/.opam-switch/build/ocaml-variants.4.14.1+idea/stdlib
```

- 实现语言：**OCaml 4.14.1**（不是 Rust）
- 语法分析：**Menhir** 生成的 LR 表，符号里可 dump 出 379 个产生式名，例如
  `arrow_fn_prefix_no_constraint`、`lexscan_case`、`trailing_info_record_defn_single`、
  `list_semis_rev_statement`、`template_object_elem` …
- `OCAMLRUNPARAM=b` + `.debug_line` ⇒ 崩溃时能拿到 `Moonc.<module>.<fn>` 级 backtrace

## 5. 公开快照缺少的东西

```
$ ls src | grep -iE 'js|native|llvm|ccgen'
（只有 runtime_gc_js_string_api.ml / basic_json_utils.ml 之类，没有后端）
```

- 没有 JS / native / LLVM 后端
- 没有 `moonfmt` / `moondoc` / runtime / 覆盖率工具
- 没有测试用例与 CI 配置

## 6. 结论

| 问题 | 答案 |
|------|------|
| 编译器开源吗？ | 部分源码公开，但**不是开源许可**，且**是 2025-03 的历史快照** |
| 当前版本能复现构建吗？ | 不能（tag 与源码树不一致） |
| 当前二进制能分析吗？ | 能，符号/DWARF/backtrace 齐全 |
