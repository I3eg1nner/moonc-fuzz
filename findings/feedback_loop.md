# Fuzz feedback loop: from random multi-entry runs to a closed loop

Date: 2026-11-16. Scope: `moonbit/cmd/fuzz`, `moonbit/trace`,
`moonbit/oracle`, `moonbit/exec`, `run.sh`. This note records the audit findings, the changes, and the checks that
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

### 2.2 Background trace pipeline

The fast path no longer calls QEMU. It submits a frozen `TraceTask`:

- original source and the exact compiled source (with `fn main` for T2);
- stage (`t1`, `t2`, `t3`) and filename;
- content hash and `config_hash`;
- for T3, a private snapshot of the produced `.core` file.

`config_hash` covers the `moonc` binary, `all_pkgs.json`, builtin/prelude
interfaces, target, `-g`, and `-O0`. Trace workers have their own working
directories, so a background task never reads an `in.mbt` that a fast worker is
about to overwrite.

`TraceQueue` is bounded (default 32) and de-duplicates by
`(stage, input_hash, config_hash)`. Submission probabilities default to T2 70%, T1
20%, link 10%, but the scheduler also enforces a 70/20/10 share of trace time
(`t2_ms`/`t1_ms`/`t3_ms`), because a T2 trace costs several times a T1 trace.
In-flight tasks carry an estimated reservation, so three workers cannot all
dequeue the same oversubscribed stage before any completion is recorded. If
no stage is below share and nothing is in flight, the scheduler borrows the
highest-priority queued task; if work is still in flight it returns `Wait`.
`Wait` and `Closed` are distinct, and `Wait` never clears the queue. Baseline
tasks run first; otherwise T2, T3, T1 priority applies, and T1 may only use
half the queue. Three trace workers are the default. The queue records
`completed`, `failed`, `dropped`, `trace_ms`, `trace_bytes`, `baseline_ms`,
`baseline_done`, `baseline_failed`, and `baseline_unresolved`.

`@trace.collect` returns a structured `TraceResult`:

```text
input_hash, config_hash, stage, outcome, complete,
functions, elapsed_ms, trace_bytes, rc, failure, detail
```

`stage` is the closed `TraceStage` enum (`T1`/`T2`/`T3`), not an arbitrary
string. `outcome` is `accepted`, `rejected`, `compiler_abort`, or
`collector_failed`. QEMU timeout, zero log, and log overflow are
`collector_failed` with `complete=false`; they are written to
`trace_failures.jsonl` and never enter a coverage union. A non-zero compiler
exit is `rejected` only when it carries a compiler diagnostic (`[E...]`,
`Error:`, or JSON `"level":"error"`). Wrapper exits 124–127 are checked before
compiler markers, so exit 127 plus OOM-looking stderr is still a collector
failure; moonc's real ICE status 199 remains `compiler_abort`. Undiagnosed
exits and signals are classified separately, and the failure record keeps `rc`
and a machine-readable reason. This removes the old `[]` ambiguity
between “no coverage” and “collection failed”.

Coverage is maintained as `U[config, stage, outcome]`. For a complete result:

```text
Δ = Coverage(x) − U
```

Only `Δ != ∅` updates U, admits the input, and grants coverage energy. Source
bytes are stored once at `corpus/<sha1>.mbt`. Coverage evidence is one file per
`(input_hash, config_hash, stage, outcome)` under
`corpus/coverage/<stage>/<outcome>/`, with the full key and function set in the
body. Behaviour evidence is under `corpus/behavior/<sha1>/`; it cannot overwrite
a coverage record. A repeated trace of an already-rewarded input updates the
coverage record but cannot claim the reward twice. A new behaviour without new
coverage is admitted with lower energy by the fast path. Neither means no
parent and no energy.

A small seed baseline is traced at startup for T1 and T2. Candidate results
are buffered until every submitted baseline task has completed or failed; U0
is then frozen and deltas are computed. `summary.json` reports
`baseline_state` (`disabled`/`pending`/`complete`/`incomplete`),
`baseline_failed`, `baseline_pending`, `baseline_unresolved`, `baseline_funcs`,
`observed_funcs`, `relative_new`, `coverage_adds`, and `coverage_keys`.
`relative_new = |observed − baseline|` is numeric only when
`baseline_state=complete`; disabled, pending, or incomplete baselines emit JSON
`null` while `observed_funcs` remains for diagnosis. A failed or dropped
baseline task makes U0 incomplete: buffered candidates are counted as unresolved
and receive no coverage reward. The 7,916
historical union is not used as the campaign baseline.

`trace_cpu_pct` (default 25) is a soft budget: adaptive tracing stops submitting
once completed trace time exceeds the budget. A single in-flight trace can
overshoot it.

### 2.3 Stage-aware differential verdict### 2.3 Stage-aware differential verdict

`@oracle.DiffClass` has six outcomes:

| verdict | meaning |
|---|---|
| `SAME` | both sides reached `run` and rc/stdout/kind agree |
| `SEMANTIC_DIFF` | both ran and an observable result differs |
| `RUNTIME_DIFF` | both ran but failed with different runtime classes |
| `ACCEPT_DIFF` | one side ran, the other failed before running |
| `COMPILER_ABORT` | ICE/OOM/exception/signal at build or link |
| `INCONCLUSIVE` | both failed before running, timeout, truncation ambiguity, or infrastructure failure |

`classify_diff(BackendResult, BackendResult)` is the only decision function.
`diff_program` and `diff_native` call it; `outcomes_agree` is a run-stage
wrapper. The fuzz driver counts `RUNTIME_DIFF` and `INCONCLUSIVE` separately and
does not write a miscompile finding for either. `cmd/diffprobe --inject`
exercises the same function with build/link failures, truncation, and a native
abort.

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
`[output truncated]` marker. Before truncation it records a SHA-1 of the full
trimmed stdout and its byte length; the oracle compares the digest when either
side is truncated, so a suffix beyond the cap cannot produce a false `SAME`.
The cap is applied after collection, so it bounds evidence and parsing, not the
child's peak RSS.

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
moon test    -> 106/106
cmd/accept   -> 10/10 gates, including 25-template wasm/js differential
```

### 3.2 Signature cardinality

Parser campaign, 2 workers, 3 s, trace disabled:

```text
it=541 t1=541 behavior_sigs=377
```

The old extractor produced 8 signatures for 847 iterations. The new count is
not a defect count; it measures distinguishable diagnostic behaviour.

### 3.3 Coverage feedback

Mixed campaign, 2 fast workers, 2 trace workers, queue 32, 10 s, 25% CPU
budget, 2 baseline seeds:

```text
it=1125 t1=1125 t2=153 t2_ok=15
trace_completed=6 trace_failed=0 trace_dropped=165
baseline_funcs=1539 observed_funcs=1689 relative_new=150
coverage_adds=150 coverage_keys=2
```

T2-only campaign, 1 fast worker, 2 trace workers, 100% T2 sampling:

```text
it=296 t1=296 t2=97 t2_ok=8
trace_completed=3 trace_failed=0 trace_dropped=87
baseline_funcs=1348 observed_funcs=1488 relative_new=140
coverage_adds=140
```

T3 link trace, 100% link sampling, one successful core snapshot:

```text
trace_completed=2 trace_failed=0 trace_dropped=5
observed_funcs=568 relative_new=null coverage_keys=1
```

Fault injection, using a synthetic collector rather than QEMU:

```text
T1-only, 2 s, 100% trace sampling, 2 trace workers
trace_completed=304 trace_failed=0 trace_dropped=0
observed_funcs=1 coverage_adds=1
```

The same T1-only campaign with the collector writing a valid PC and exiting
127:

```text
trace_completed=0 trace_failed=348 trace_accepted=0 trace_rejected=0
coverage_adds=0 observed_funcs=0
trace_failures.jsonl: rc=127 failure="collector_exit=127"
```

Delayed-baseline ordering (four baseline tasks, one held for 3 s while
candidates completed after 1 s):

```text
trace_completed=516 baseline_done=4 baseline_failed=0
baseline_state=complete baseline_funcs=1 observed_funcs=1
relative_new=0 coverage_adds=0
```

An exit-127 collector that also writes `Cannot allocate memory`:

```text
trace_completed=0 trace_failed=368 trace_aborts=0
observed_funcs=0 coverage_adds=0
trace_failures.jsonl: rc=127 failure="collector_exit=127"
```

A real exit-199 ICE:

```text
trace_completed=351 trace_aborts=351 trace_failed=0
observed_funcs=1 coverage_adds=1
```

A partial baseline (T1 baseline succeeded, T2 baseline failed) with later
candidate coverage:

```text
baseline_done=1 baseline_failed=1 baseline_state=incomplete
baseline_funcs=1 observed_funcs=2
relative_new=null coverage_adds=0 baseline_unresolved=305
```

The queue is deliberately allowed to drop under overload; `trace_dropped` and
`trace_failures.jsonl` make that visible. The numbers above are smoke evidence
that T1/T2/T3 each reach the collector, not a claim of optimal sampling.

### 3.3.1 Instrumented calibration

A 60 s, 16-worker hybrid calibration was used only to validate the new
observation fields, not to estimate bug-finding ability:

```text
it=48880 t2=1333 t2_ok=205 unique_t2_ok_inputs=178
diff_attempts=23 diff_complete=23 diff_nonempty=0
t3_ok=23 t3_diff=0 t3_inconclusive=0
unique_inputs=46442 behavior_sigs=36378 diagnostic_families=27998
baseline_state=complete baseline_funcs=2165 observed_funcs=2478 relative_new=313
coverage_adds=798 trace_completed=22 trace_dropped=1245
```

This confirms why short runs cannot answer the capability question: the fast
loop produces many text mutations, but only 205 T2 successes in 60 s, and all
23 differential attempts produced empty output and `SAME`. The new fields make
those limits visible per run; they do not by themselves show whether a longer
campaign reaches new compiler paths.

The calibration also exposed an operational limit. It persisted 88,775 files
(437 MB) and grew the feedback corpus to 45,546 parents in 60 s. Linear
extrapolation to 2 h is about 10.6 million files; the unbounded behavior
persistence and O(parents) parent selection must be capped or sampled before a
multi-hour campaign is meaningful.

### 3.4 Differential fault injection### 3.4 Differential fault injection

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

### 3.5 Second review fixes

```text
$ diffprobe --inject truncated-suffix
verdict=SEMANTIC_DIFF
same=false

$ diffprobe --inject truncated-same
verdict=SAME
same=true

$ diffprobe /tmp/abort.mbt . --native
verdict=RUNTIME_DIFF
same=false
wasm   stage=run         kind=ERR rc=1
native stage=native-run  kind=SIG rc=-6
```

`exec` keeps a SHA-1 of the complete trimmed stdout and its full byte length
before truncation. `classify_diff` compares digests when either side is
truncated, so suffix differences beyond the evidence cap cannot become `SAME`;
an incomparable one-sided truncation is `INCONCLUSIVE`. A real 1.1 MB +
different-suffix injection is covered by `exec_test`.

Native now separates `moon run --build-only` from executing the artifact. An
`abort` is therefore `native-run / SIG`, and comparable runtime failure
classes are `RUNTIME_DIFF`, not a build error or a miscompile finding.

Coverage admission is now driven by `trace_apply`, not by the fast path:
`added == 0` neither admits nor rewards. Source bytes are stored once as
`corpus/<sha1>.mbt`. Behaviour evidence (`behavior`, `behavior_t2`) lives under
`corpus/behavior/<sha1>/`; coverage evidence is keyed by
`(input_hash, config_hash, stage, outcome)` under
`corpus/coverage/<stage>/<outcome>/`. The two evidence kinds cannot overwrite
each other. `--seed-dir <run>/corpus` replays the source files.

The SIGKILL test (`trap '' TERM` + `timeout -k`) reports `timed_out=true`,
`rc=-999`, and strips timeout controller messages from stderr.

## 4. Remaining limits

- Coverage is function-level. Entering the same `camlMoonc*` function through a
  new branch does not increase the set; a compact TB/edge bitmap is future work.
- T3 has no seed baseline in this version, so `relative_new` is not directly
  comparable across T1/T2/T3. If a T1/T2 baseline is requested but any baseline
  task fails or is dropped, U0 is incomplete and that run has no trusted
  coverage-gain result.
- The collector stats the log before reading and rejects oversized files, but
  an accepted log is still read whole; PCs are not streamed/deduplicated before
  symbolization. QEMU `-d exec` is execution-event logging, not
  translation-only logging.
- `trace_cpu_pct` is soft: a long T3 trace already in flight can exceed the
  budget.
- Memory caps are per process group and only on `run_isolated` paths.
- `run_isolated` assumes GNU coreutils (`timeout`, `prlimit`) on Linux.
- Signature cardinality is not coverage. The 7,916/26,611 frozen coverage
  number remains a separate, offline union with its own provenance audit.
