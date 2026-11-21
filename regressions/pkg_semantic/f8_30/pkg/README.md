# F8: link-core assertion for `raise?` callback after an async suspension

Pinned: `moonc v0.10.20+65efd5b93` / `moon 0.1.20261104`.
Dependency: `moonbitlang/async@0.22.9`.

## Reproduce

```
cd poc/f8_async_raise_ice
moon test --target js       # also wasm, native
```

`moon check` succeeds. The failure happens in `moonc link-core` while linking
the generated blackbox test:

```
Error: File "moonc.ml", line 125623, characters 29-35: Assertion failed
```

The same package fails on `js`, `wasm`, and `native`; no test body is executed.
`moon test --target wasm-gc` is not part of the reproducer's supported targets.

## Minimal trigger

The four-line function is enough:

```moonbit
pub async fn[T] pick(select : (Int) -> T? raise?) -> T? {
  @aio.pause()
  select(1)
}
```

It needs the combination of:

1. an `async` function;
2. a suspension point (`@aio.pause()`);
3. a call to a `raise?` function parameter after the suspension;
4. a caller/test that forces link.

Removing the suspension, changing the callback from `raise?` to `raise`, or
removing the error from the callback makes the reproducer link (per the
upstream report and the variants tried there).

This is a link-time compiler crash, not a miscompile. A normal diagnostic or a
working link is expected.

## Upstream

Matches open upstream report
[#1340](https://github.com/moonbitlang/moonbit-docs/issues/1340)
(`link-core assertion when an async function calls a raise? parameter after a
suspension`). It is reproduced here against the pinned toolchain and
`moonbitlang/async@0.22.9`, not claimed as a new upstream root cause.
