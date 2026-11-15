# Fuzz feedback loop: from random multi-entry runs to a closed loop

Date: 2026-11-15. Scope: `moonbit/cmd/fuzz`, `moonbit/oracle`, `moonbit/exec`,
`run.sh`. This note records the audit findings, the changes, and the checks that
were run; it does not claim new compiler defects.

## 1. Audit findings reproduced

| finding | observed before | consequence |
|---|---|---|
| T1 JSON signature | `-error-format json` emits `{"error_code":3002,...}`, extractor searched for `[E3002]` | all diagnostics collapsed to `ERR`; a 4-worker, 847-iteration smoke produced only 8 signatures |
| differential verdict | real path compared rc/stdout/kind directly | wasm `stage=link kind=ERR`, js `stage=build kind=ERR` was reported `same=true` |
| launcher | `run.sh` built only when the release binary was absent | stale binary could be executed after source edits |
| parent selection | fixed seed array; new inputs only entered a 400-entry splice pool | new behaviour did not steer the next mutation |
| execution budget | wall-clock timeout only | no output cap; no address-space rlimit; descendant cleanup unverified |

The trace/cov packages were already usable; the missing piece was the in-loop
connection.

## 2. Changes

### 2.1 Diagnostic signature

`behavior_sig(stage, result)` parses each JSON diagnostic line with
`@json.parse` and keeps:

- `level` and `error_code` (rendered as `E####` / `W####`);
- `message` (first 160 code points);
- `loc`.

Non-JSON output falls back to the legacy `[E####]` extractor, then to
`rc=<n>`. The signature includes the T1 stage prefix. Unit tests cover two
different messages with the same `error_code` and different locations.

### 2.2 Dynamic corpus and parent energy

A campaign-wide `Feedback` object now holds:

- content-hash-indexed `Parent` entries;
- each parent's observed `FuncSet`, energy, and use count;
- the union cover set.

Only a new T1 behaviour or a coverage-adding input is admitted. A coverage
addition grants energy 32; a new behaviour grants 1. Selection is weighted by
`1 + energy`, and energy decays by one per selection, so newly discovered
coverage dominates briefly instead of permanently. The splice pool still has a
400-entry cap, but now replaces a random slot when full instead of dropping new
inputs.

`--cov-every N` runs T1 under
`afl-qemu-trace -d exec -D <trace> -- moonc ...`, symbolizes with the `nm -n`
table loaded once per campaign, unions `camlMoonc`-reachable functions, and
returns new-function counts to the shared corpus. Default is 64; `0` disables
it. A trace larger than 128 MiB is skipped.

### 2.3 Stage-aware differential verdict

`@oracle.DiffClass` has five outcomes:

| verdict | meaning |
|---|---|
| `SAME` | both sides reached `run` and rc/stdout/kind agree |
| `SEMANTIC_DIFF` | both ran, observable results differ |
| `ACCEPT_DIFF` | one side ran, the other failed before running |
| `COMPILER_ABORT` | ICE/OOM/exception/signal at build or link |
| `INCONCLUSIVE` | both failed before running, timeout, or infrastructure failure |

`classify_diff` is the only decision function. `diff_program` and
`diff_native` call it; `outcomes_agree` is now a run-stage wrapper. The fuzz
driver counts `INCONCLUSIVE` separately and does not write a finding for it.
`cmd/diffprobe --inject` exercises the same function with a link/build failure
and an ICE/build failure.

### 2.4 Launcher and run identity

`run.sh` always runs the incremental `moon build` and supports explicit
campaigns:

| campaign | T2 | T3 |
|---|---|---|
| `parser` | 0% | 0% |
| `typer` | 100% | 0% |
| `semantic-diff` | 100% | 100% |
| `hybrid` (default) | 50% | 10% |

Every launch prints and persists a plan. The run directory is
`out/<base>/<UTC>-<pid>/` with `manifest.json`, `summary.json`, and
`stats.jsonl` snapshots every 2 s. Worker temp directories are keyed by
`run_id`, so concurrent runs sharing an output base do not delete each other.

### 2.5 Execution budget

`@exec.run` accepts an optional `max_output_bytes`. The differential run stage
caps retained stdout/stderr at 1 MiB with an explicit
`[output truncated]` marker. The cap is applied after collection, so it bounds
evidence and parsing, not the child's peak RSS.

`@exec.run_isolated` wraps the command in GNU `timeout` (own process group,
kill-after 1 s) and optional `prlimit --as`. The campaign uses it for T1
(2 GiB), T2 (6 GiB), QEMU tracing (4 GiB), and T3 execution (4–6 GiB). A
grandchild probe (`/bin/sh -c 'sleep 30 & wait'`, 200 ms) now leaves no live
`sleep`. Raw `@exec.run` call sites, including formatter checks, remain
unisolated.

## 3. Checks

All commands were run after the changes.

### 3.1 Build and tests

```text
moon check   -> 0 errors, 0 warnings
moon test    -> 86/86
cmd/accept   -> 10/10 gates, including 25-template wasm/js differential
```

### 3.2 Signature cardinality

Parser campaign, 2 workers, 3 s, `--cov-every 0`:

```text
it=541 t1=541 behavior_sigs=377
```

The old extractor produced 8 signatures for 847 iterations. The new count is
not a defect count; it measures distinguishable diagnostic behaviour.

### 3.3 Coverage feedback

Parser campaign, 2 workers, 3 s, `--cov-every 32`:

```text
it=128 t1=128 cov_samples=4 cov_funcs=969 coverage_adds=969
```

Hybrid campaign, 2 workers, 5 s, `--cov-every 0`:

```text
it=682 t1=682 t2=80 t2_ok=9 t3_ok=3 t3_diff=0 t3_inconclusive=0
```

### 3.4 Differential fault injection

```text
$ diffprobe --inject wasm-link-vs-js-build
verdict=INCONCLUSIVE
same=false

$ diffprobe --inject wasm-run-vs-js-build
verdict=ACCEPT_DIFF
same=false

$ diffprobe --inject wasm-ice-vs-js-build
verdict=COMPILER_ABORT
same=false
```

A normal template still reports `verdict=SAME`, `same=true`:

```text
$ diffprobe templates/01_int_ops.mbt .
verdict=SAME
same=true
```

## 4. Remaining limits

- Coverage sampling currently instruments T1 only. T2 and T3 are driven by T1
  behaviour and T2 success, not by their own trace feedback. Tracing
  `build-package` or `link-core` is substantially more expensive and needs a
  separate sampling policy.
- The QEMU sample costs about one second and ~17 MiB of trace for a tiny input.
  It improves direction, not throughput.
- Memory caps are per process group and only on `run_isolated` paths. Formatting
  and direct `@exec.run` probes are not covered.
- `run_isolated` assumes GNU coreutils (`timeout`, `prlimit`) on Linux; it is not
  portable to macOS/Windows. The raw runner remains available for those hosts.
- Signature cardinality is not coverage. The 7,916/26,611 frozen coverage
  number remains a separate, offline union with its own provenance audit.
