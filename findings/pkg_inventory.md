# 可构建包清单（时间盒 60 分钟）

Date: 2026-11-21. 工具链 pin 未改。

| 包 | 可构建 | 配置 | 备注 |
|---|---|---|---|
| f8 夹具（去触发） | 是 | `moon test --target js --build-only` | 多文件 + async 依赖 |
| f9 | 是 | `moon test --target native --release` | 2 文件 + stub.c |
| moonldif（`poc/f6_native_export_closure/moonldif`） | **是（wasm-gc）** | `moon build --target wasm-gc` | native 链接失败，wasm-gc 可构建；capsule 1 iter 通过、replay 一致 |
| f6_min | **否** | — | 不是缺 stub：`#export_name` 导出含闭包的类型触发真实 ICE `Machine_error(unsupported; who="Machine_of_clam_lower.reject_export_type_containing_unsupported_callback"; message="the Native backend cannot export types containing closures")` |

结论：**3 个可构建包**（f8 夹具、f9、moonldif），达到 3–4 的下限。f6_min
的阻塞是编译器能力/ICE，不是可以补 C stub 解决的链接错误；具体符号/阶段
已记录（link-core，导出 `Handle` 含 `(Int32)->Int32` 闭包）。
