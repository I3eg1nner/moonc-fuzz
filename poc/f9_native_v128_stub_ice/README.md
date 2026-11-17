# F9: native debug ICE for an `extern "C"` stub taking `V128`

Pinned: `moonc v0.10.20+65efd5b93` / `moon 0.1.20261104`.
Host: Linux x86_64.

## Reproduce

```
cd poc/f9_native_v128_stub_ice
moon test --target native
```

Expected (and observed): `moon check` and `moon test --build-only` are fine, but
the native **debug** link fails with:

```
Error: Machine_error(kind=unsupported;
  who="Machine_of_clam_lower.finish_stub_wrapper_shell";
  message="aggregate stub wrapper arguments are not lowered in this batch")
```

`moon test --target native --release` succeeds. The package has a native stub
(`stub.c`) and calls it with a `V128` argument produced by
`@v128.f32x4_const`.

## Trigger shape

- `pkgtype`/`options` declares a native stub;
- an `extern "C"` function takes a `V128` argument;
- the caller passes a vector value;
- target `native`, debug (`-g -O0`), test-mode link.

This is a compiler/link-time ICE, not a miscompile. The expected behavior is
either a working debug link or a source-level unsupported diagnostic.

## Upstream

Matches open upstream report
[#1344](https://github.com/moonbitlang/moonbit-docs/issues/1344)
(`aggregate stub wrapper arguments are not lowered` for an `extern "C"` taking
`V128`). Reproduced here on the pinned Linux toolchain, not claimed as a new
upstream root cause.
