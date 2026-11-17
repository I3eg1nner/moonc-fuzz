# Reusable candidate verifier (`cmd/verify`)

A MoonBit-native command that answers one narrow question: **does this
candidate package still fail in the same way when the check/build/test pipeline
is repeated from a fresh copy?** It does not fuzz, minimize, or diagnose root
cause.

Pinned environment for every result in this note:

- `moon 0.1.20261104 (940aa18 2026-11-04)`
- `moonc v0.10.20+65efd5b93 (2026-11-05)`
- Linux x86_64, one host.

## Usage

From `moonbit/`:

```sh
moon run cmd/verify -- \
  --dir /abs/package/dir \
  --target native \
  --mode debug \
  --repeats 3 \
  --timeout-ms 120000 \
  --out /tmp/verify.json \
  [--control-dir /abs/control/package/dir]
```

`--` is needed because `moon run` otherwise consumes the verifier's flags.

| Flag | Meaning |
| --- | --- |
| `--dir` | Absolute candidate package directory. Must contain `moon.mod`. |
| `--target` | `native`, `wasm`, `wasm-gc`, or `js`. |
| `--mode` | `debug` (default) or `release`. |
| `--repeats` | Number of fresh-copy repeats, `1..50` (default `3`). |
| `--timeout-ms` | Per-stage wall-clock timeout, `1000..1800000` (default `120000`). |
| `--out` | Absolute path for the JSON report. |
| `--control-dir` | Optional second package run through the same stages. |

Exit status is `0` when the verification completed (including
`reproduced`, `not_reproduced`, and `control_failed`), and `2` for usage,
infrastructure, or unwritable-output failures. The JSON is written before the
exit decision.

The command never writes to the candidate directory. `MBTFUZZ_VERIFY_TMP`
overrides the default temporary root (`/tmp/mbtfuzz_verify`).

## Fresh-copy and stage semantics

For every repeat the verifier:

1. Removes the deterministic run root for `(package, target, mode, role)`.
2. Copies the package recursively into `repeat_<n>`, excluding exactly
   `_build`, `.mooncakes`, and `.git` (contents are skipped at any depth).
3. Runs the stages below in order, stopping at the first non-`ok` stage.
4. Deletes nothing afterwards; the repeat directories are kept for inspection.

Stages, exactly:

| Stage id | Command |
| --- | --- |
| `check` | `moon check --target T --frozen [--release]` |
| `build` | `moon build --target T --frozen [--release]` |
| `test_build_only` | `moon test --target T --frozen [--release] --build-only` |
| `test` | `moon test --target T --frozen [--release]` |

`--frozen` is added so the verifier does not start a dependency sync / network
fetch. Dependencies must already be resolvable from the toolchain's offline
cache; otherwise the failure is reported as an ordinary stage failure rather
than `infra`. The verifier itself performs no network I/O.

Each stage runs under GNU `timeout` in its own process group (via the existing
`exec.run_isolated`), so a native link that leaves `cc` behind is killed too.
Wall-clock `ms` is recorded per stage and summed for the run.

## Classification

| Terminal | Rule |
| --- | --- |
| `ok` | All four stages exited `0`. |
| `check_fail` | `check` failed without an ICE marker. |
| `build_fail` | `build` failed without an ICE marker. |
| `test_link_fail` | `test --build-only` failed, or full `test` failed with a link marker (`failed to link`, `link-core`). |
| `run_fail` | Full `test` failed after the tests built, without a link marker. |
| `ice` | Any stage emitted `Oops, the compiler...`, `Machine_error(`, `Assertion_failure`/`Assert_failure`, or `moonc.ml`. ICE dominates the stage label. |
| `timeout` | The per-stage timeout fired. |
| `infra` | Copy/source/spawn failure, missing `moon.mod`, or no output from a failed spawn. |

The failing stage id (`check`, `build`, `test_build_only`, `test`, or `none`)
is reported separately from the terminal class.

## Signature normalization

The signature is the low-cardinality identity of the failure. It is built from
the sanitized stage output (package roots are replaced with `<PKG>`):

1. `Machine_error(kind=...; who=...; message=...)` — line wrapping removed,
   quoted fields unquoted, canonical one-line form.
2. `moonc.ml:<line>:assertion` — character ranges and source context dropped.
3. `ICE: <first following Error: detail>` when the `Oops, the compiler...`
   banner is present.
4. `signal:SIGSEGV` / `SIGABRT` / ... when the process died by signal and no
   diagnostic was emitted.
5. Otherwise `Error: <first Error: line>` (or `error: ...`), then the first
   non-empty diagnostic line, then `rc:<n>`.

Temporary paths do not appear in the signature. `diagnostics` keeps the first
few actual error lines for humans (the ASCII-art banner and `Compiler args:`
replay are filtered out).

## `stable` and `verdict`

`stable` is `true` only when **every** repeat has the same terminal class,
failing stage, normalized signature, and rc class (`ok`, `error`, `signal`,
`timeout`). Exact rc values are reported but are not required to match.

| Verdict | Meaning |
| --- | --- |
| `reproduced` | Candidate is stable and non-`ok`, and either no control was requested or the control is stable and `ok`. |
| `not_reproduced` | Candidate is `ok` or unstable. |
| `control_failed` | Candidate is stable and non-`ok`, but the control is not stable/`ok` (including control `infra`). The comparison did not isolate the defect. |
| `infra` | At least one candidate repeat failed for infrastructure reasons. No reproduction claim is made. |

## Real smoke run on F9

This is a smoke test of the verifier, **not a new finding**. F9 already exists
and is documented in `poc/f9_native_v128_stub_ice/README.md`; its upstream
report is moonbit-docs#1344. The verifier confirms the existing staged shape
3/3 on this host.

Candidate copy: `/tmp/f9copy` (copy of
`poc/f9_native_v128_stub_ice/`, `_build` removed).

### Debug candidate: stable failure 3/3

```sh
moon run cmd/verify -- --dir /tmp/f9copy --target native --mode debug \
  --repeats 3 --timeout-ms 120000 --out /tmp/verify_f9.json
```

Observed:

```
[verify] candidate=/tmp/f9copy target=native mode=debug repeats=3
  repeat 0: ice at test_build_only rc=1 ms=901 sig=Machine_error(kind=unsupported; who=Machine_of_clam_lower.finish_stub_wrapper_shell; message=aggregate stub wr...
  repeat 1: ice at test_build_only rc=1 ms=831 sig=Machine_error(...)
  repeat 2: ice at test_build_only rc=1 ms=809 sig=Machine_error(...)
[verify] stable=true verdict=reproduced
```

All three repeats: `check` rc0, `build` rc0, `test_build_only` rc1 with the
same normalized signature:

```
Machine_error(kind=unsupported; who=Machine_of_clam_lower.finish_stub_wrapper_shell; message="aggregate stub wrapper arguments are not lowered in this batch")
```

(quotes are removed in the signature; the raw diagnostic keeps them).

### Release control: passes 3/3

Same copy, release mode:

```sh
moon run cmd/verify -- --dir /tmp/f9copy --target native --mode release \
  --repeats 3 --timeout-ms 120000 --out /tmp/verify_f9_release.json
```

Observed: `repeat 0/1/2: ok at none rc=0`, `stable=true`,
`verdict=not_reproduced`. This is the expected `--release` control pass: the
debug-only link ICE does not reproduce in release mode.

### Control package path exercised

To exercise `--control-dir`, a second copy was made under `/tmp/f9control`
with the `extern "C"` stub no longer taking `V128` (so its debug test link
works). Running the debug candidate with that control:

```
[verify] stable=true verdict=reproduced
[verify] control=/tmp/f9control terminal=ok stable=true
```

This shows the control comparison path, not a second F9 result.

## JSON shape

Actual abbreviated output from `/tmp/verify_f9.json`:

```json
{
  "candidate_dir": "/tmp/f9copy",
  "target": "native",
  "mode": "debug",
  "repeats": 3,
  "runs": [
    {
      "repeat": 0,
      "work_dir": "/tmp/mbtfuzz_verify/f9copy-f36210eb6be4-cand/repeats/repeat_0",
      "stages": [
        {"stage": "check", "args": ["check", "--target", "native", "--frozen"],
         "rc": 0, "ms": 128, "timed_out": false, "signature": "", "diagnostics": []},
        {"stage": "build", "args": ["build", "--target", "native", "--frozen"],
         "rc": 0, "ms": 95, "timed_out": false, "signature": "", "diagnostics": []},
        {"stage": "test_build_only",
         "args": ["test", "--target", "native", "--frozen", "--build-only"],
         "rc": 1, "ms": 678, "timed_out": false,
         "signature": "Machine_error(kind=unsupported; who=Machine_of_clam_lower.finish_stub_wrapper_shell; message=aggregate stub wrapper arguments are not lowered in this batch)",
         "diagnostics": ["Error: failed to link repro/v128stub ...", "Oops, the compiler has encountered an unexpected situation."]}
      ],
      "terminal": "ice",
      "stage": "test_build_only",
      "signature": "Machine_error(kind=unsupported; who=Machine_of_clam_lower.finish_stub_wrapper_shell; message=aggregate stub wrapper arguments are not lowered in this batch)",
      "rc": 1,
      "rc_class": "error",
      "ms": 901,
      "diagnostics": ["Error: failed to link repro/v128stub ...", "Oops, the compiler has encountered an unexpected situation."]
    }
  ],
  "stable": true,
  "control": null,
  "verdict": "reproduced"
}
```

With `--control-dir`, `control` is an object with `dir`, `terminal`, `stable`,
and the control's own `runs` array. The candidate `repeats` count is echoed,
and candidate/control run directories are retained under the deterministic
temp root printed by the summary.

## Tests

`cmd/verify/verify_wbtest.mbt` covers:

- `Machine_error` multiline normalization;
- `moonc.ml:<line>` assertion normalization;
- generic `Error:` normalization;
- `Oops` + following `Error:` pairing;
- package-root path replacement (`<PKG>`);
- signal fallback;
- synthetic `RunResult` stage classification (`check_fail`, `build_fail`,
  `test_link_fail`, `run_fail`, `ice`, `timeout`, `ok`);
- copy exclude rules (`_build`, `.mooncakes`, `.git` absent; `moon.mod`,
  `moon.pkg`, sources, nested native stubs preserved);
- stability comparison over synthetic `RepeatRun` values.

The whole module's `moon test --target native`, `moon check`, and
`moon fmt --check` are run separately as validation.

## Limitations

- **One host, one pinned toolchain.** Reproducibility is measured against this
  machine and these exact binaries; it is not a portability claim.
- **An ICE reproduction is not root cause.** The verifier proves the staged
  failure recurs with a stable signature. It does not minimize the input, find
  the faulty compiler pass, or prove that two equal signatures have the same
  underlying cause.
- **Heuristic signatures.** New ICE shapes fall back to the first `Error:` line
  or the first diagnostic line. Diagnostic ordering changes can change the
  signature without changing the bug.
- **Output is capped at 1 MiB per stage.** A marker emitted after the cap can
  be lost. Normal compiler/test output is far below this.
- **Copy policy is narrow.** Only `_build`, `.mooncakes`, and `.git` are
  excluded. Symlinks are followed as files/directories and file permissions are
  not preserved. Candidate packages that require executable bits or unusual
  file metadata may behave differently after copying.
- **Offline dependency assumption.** `--frozen` prevents the verifier from
  triggering a dependency sync. A missing dependency therefore looks like a
  normal `check_fail`/`build_fail`, not `infra`.
- **Serialized temp root.** The root is deterministic per
  `(package, target, mode, role)`. Concurrent verifier runs for the same tuple
  would delete each other's repeat directories; use `MBTFUZZ_VERIFY_TMP` or
  serialize.
- **GNU `timeout` required.** The process-group timeout relies on
  `/usr/bin/timeout` (Linux). On a host without it, stage spawns report
  `infra`.
- **Control is only a discriminator.** A passing control shows the harness and
  environment can build/test a similar package; it does not prove the
  candidate failure is caused by the candidate's specific source change.
- **No minimization or fuzzing.** Runs are bounded by `--repeats` and
  `--timeout-ms`; there is no search loop.
