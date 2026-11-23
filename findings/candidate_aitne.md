# aitne invalid wasm：CONFIRMED 但同 415 根因，不列新候选

最小 repro（14 行）：

```moonbit
type Object

fn[T] Object::of(value : T) -> Object = "%identity"
fn[T] Object::to(self : Object) -> T = "%identity"

fn[T] try_cast(a : Object) -> T? {
  let r : Ref[T] = Object::of(Ref(a)).to()
  Some(r.val)
}

fn main {
  let x : Int? = try_cast(Object::of(1))
  ignore(x)
}
```

命令：

```bash
moon build --target wasm-gc   # rc0
moon build --target js        # rc0
node _build/js/debug/build/repro.js  # rc0
```

`new WebAssembly.Module(route.wasm)`：

```text
Compiling function #659 ... failed: local.set[0] expected type (ref 284), found call of type (ref 431) @+70143
```

最小 repro 3 次重编均 rc0，产物均 invalid；`counter.wasm` 同 validator valid，
排除 validator 不支持 wasm-gc 特性。

判定：**CONFIRMED invalid module**；构造是 `%identity` 类型擦除 + `Ref[T]`/
`Any` 转换，和 415 的 `%identity` function-typed coercion 属同一根因类，因此
**不作为新候选**，不写成新发现。
