# Discovery K：类型形状生成器与 600 程序

Date: 2026-11-23. Pin 不变。先 push 已有一批 commit，之后不 push。

## K1/K2 生成器与正控

`scripts/gen_type_shapes.sh` 生成独立 `/tmp` 包（moon.mod/moon.pkg/main.mbt），
族：%identity 函数/Ref、Array、struct、tuple、enum、泛型 Box、闭包、trait
object、递归泛型；每个包有 main，测试块触发 wasm 产物。

正控 2 个：

```json
{"generated":2,"build_ok":2,"invalid_artifact":2,
 "buckets":{"local.set|ref<-ref|identity":2}}
```

- 415 构造（函数参数/返回值 `%identity`）命中 identity 桶；
- aitne 构造（`Ref[T]`/Object `%identity`）命中 identity 桶；
- 正控通过，生成器空间覆盖已知根因。

## K3 600 程序

16 workers（实际并发，不是 32，资源限制已记录）：

```json
{"generated":600,"build_ok":525,
 "invalid_artifact":525,
 "buckets":{"local.set|ref<-ref|identity":525}}
```

- 75 个生成程序 build 失败（类型/语法构造不合法），未计 invalid；
- 525 个 build_ok 的产物全部 invalid，全部落 identity 桶；
- 没有不等于 identity 的新桶；
- 无新 candidate。

## K4 结论

- 生成器正控命中已知 identity 桶 2/2；
- 600 个程序：525 build_ok、525 invalid、桶表只有 identity；
- 在这 5 类类型形状里，pin 上静默非法产物只有**一个根因**（415/aitne 族）；
- 下一步建议：换运行时输出差分/类型导向生成，或停这条线；继续生成同族程序
  只会重复命中 identity 桶。
