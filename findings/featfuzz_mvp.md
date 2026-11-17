# featfuzz MVP: native layout generator and staged oracle

Status: implemented, verified, unmerged. Branch `agent/featfuzz`.

Host/toolchain: Linux x86_64, `moon 0.1.20261104 (940aa18)`,
`moonc v0.10.20+65efd5b93`. All runs below were made with `--jobs 2` (the host
was recently overloaded; no wider parallelism was used).

Deliverables:

| path | role |
|---|---|
| `moonbit/featuregen/` | pure data model, curated matrix, source renderer, 12 tests |
| `moonbit/cmd/featfuzz/` | staged oracle driver; JSONL records + summary |
| `findings/featfuzz_mvp.md` | this report |

Nothing outside those paths is modified. The generated packages are written to
an absolute `--out` directory outside the repo, so no build artifacts are
committed and `moonbit/.mooncakes` is never staged.

## 1. Design and package layout

### `featuregen` (data + renderer, no I/O)

The package is deliberately side-effect free. Its public surface:

- `FieldType` (`IntT`, `Int64T`, `BoolT`, `StringT`, `ArrayIntT`, `EnumStringT`,
  `EnumArrayIntT`) and `LayoutOp` (`Push`, `Makei`, `Map`, `Filter`, `Slice`);
- `LayoutCase { id, index, valtype, fields, op, suite }`;
- `layout_cases()` / `matrix_size()` — the deterministic enumeration;
- `render_package(case) -> { moon_mod, moon_pkg, lib_mbt, main_mbt, main_test_mbt }`;
- `expected_checksum(case)` — an independently written evaluator of the
  generated `checksum()`;
- `f7_seed()` / `f7_control()` — the built-in A/B pair for the known F7 shape;
- `features_json(case)` — the feature object embedded in every JSONL record.

The renderer is a pure function: the same case always produces byte-identical
files. A whitebox test asserts that, which is what makes the stable IDs and
one-axis reduction meaningful.

Each generated package is a complete, hermetic MoonBit module:

```
moon.mod          name = "featfuzz/generated"      (no dependencies)
moon.pkg          pkgtype(kind: "executable")
lib.mbt           enum payload types, struct Entry, entry/score/collect, pub fn checksum()
main.mbt          fn main { println(checksum()) }
main_test.mbt     test "checksum is deterministic" { a=b; assert_eq(a, <constant>) }
```

`lib.mbt` is a real library: `main.mbt` and the blackbox test both call the
`pub fn checksum`, so the `test --build-only` stage has to compile the public
interface and link a second driver, not merely type-check one file set.

The generated test is not a tautology: the expected constant comes from
`expected_checksum`, which is written separately from the renderer (same field
scoring but by evaluating the case, not by string-building). When a case links
and runs, a mismatch means the generated program computed something other than
what the model says it should, which is the semantic half of the oracle.

### `cmd/featfuzz` (driver)

Imports `featuregen`, `corpus` (paths/JSON escaping), and `exec`
(`run_isolated` with timeouts and output caps). Per case it creates
`<out>/cases/<case-id>/`, writes the five files, then walks the stage ladder,
stopping at the first non-OK stage. It records one JSONL line per case
(`id`, `features`, `stage`, `rc`, `class`, `signature`, `dir`, `stderr_short`,
`ms`, `candidate`) and a `summary.json` with per-class counts and deduplicated
candidate signatures.

Tests: `featuregen` has 12 whitebox tests (enumeration determinism, unique IDs,
exact size, F7 seed/control identity, renderer contents, zero-field
construction, checksum cardinality for push/filter/slice, all-160 render
completeness, feature JSON). Full module: `moon test --target native` =
**171 passed / 171** (2026-11-17, this branch).

## 2. Matrix size and why it is curated

Exact size: **16 field suites × 2 valtype settings × 5 operations = 160 cases**.
`matrix_size()` and `layout_cases().length()` both return 160 and a test pins
that. IDs are `L%04d-{vt|plain}-{op}-{suite_tag}`, e.g.
`L0080-vt-push-int_enum_string`; the index is the enumeration position, so IDs
are stable across runs. Enumeration order is suite → valtype → operation, which
means the first occurrence of a signature is also the smallest field suite that
triggers it.

Suite field counts are 0–4 over a 7-type alphabet: the empty
struct, each scalar/aggregate alone, each enum payload alone, and mixed
`Int`/`Int64` + `Bool` + `String` + `Array[Int]` + enum layouts. Suite 8 is the
F7 shape (`Int` + enum with a `String` payload); suite 9 is its
array-payload sibling; suite 10 (`Int` + `String`) is the discriminating
control that keeps the GC reference *outside* the enum.

Why curated rather than random:

1. **Every case must be a valid, linkable, runnable program.** Random
   field/type sampling mostly yields packages that fail to compile or collapse
   to the same layout, which burns budget without adding signal. The curated
   suites guarantee that a failure is attributable to the layout axis.
2. **One-axis reduction.** Because only `valtype`, `op`, or the field list
   changes between neighbouring cases, a hit can be reduced by moving exactly
   one axis while every other byte of the generated source stays fixed. That is
   how the F7 control set (`L0085`–`L0089`, same fields/op without `#valtype`)
   exists for free.
3. **The interesting space is small and discrete.** The native aggregate/GC-ref
   lowering space named by the existing F7 PoC has four conditions (target,
   `#valtype`, a non-null GC payload, array construction). Sampling that space
   would under-sample the one corner that matters, whereas a fixed matrix
   covers it by construction.
4. **Reproducibility.** Fixed IDs make runs comparable, and a candidate can be
   handed to a human as one directory name.

The price is explicit: 160 is a feature matrix, not a random corpus. It says
nothing about the frequency of a defect in the wild, and 16 suites are not a
coverage claim over MoonBit's layout space.

Important: `--limit N` takes a deterministic **prefix** of the enumeration, not
a sample. A 100-case run therefore covers `L0000`–`L0099`, i.e. suites 0–9 only
(the six richer suites 10–15, indices 100–159, are not exercised). This matters
when reading the counts in §4.

## 3. Stage semantics

| stage | command | what it actually does | failure class |
|---|---|---|---|
| `check` | `moon check --target native` | parses/type-checks; no native codegen, no link | `CHECK_FAIL` |
| `build` | `moon build --target native` | native codegen + `moonc link-core` of the executable | `BUILD_FAIL` / `ICE` |
| `test-build` | `moon test --target native --build-only` | compiles the blackbox test package and links the test driver with `-test-mode` and test-driver exports | `TEST_LINK_FAIL` / `ICE` |
| `test` | `moon test --target native` | builds (again, incrementally) and executes the test binary | `RUN_FAIL` / `ICE` |

`moon build` success is **not** sufficient:

- `moon build` links `main`; `moon test --build-only` compiles an additional
  blackbox test package against the library's public interface and performs a
  *second* link with a different entry point and a different export set
  (`-test-mode`, `moonbit_test_driver_*`). Linker/lowering defects can be
  sensitive to exactly that difference.
- This repo already has a case where it matters: the F9 verification
  (`findings/codex_open_ice_review.md`) records `check`/`build` succeeding while
  `moon test --build-only` fails with the same `finish_stub_wrapper_shell`
  `Machine_error`. A driver that stops at `build` would call that case OK.
- The 90 OK cases in this run are the positive evidence that the extra stage is
  real work: they pass `test-build` and then actually execute, i.e. the test
  driver was produced and ran, rather than the stage being skipped.

The `test-build`/`test` split also gives a clean attribution: a candidate that
reaches `test` but fails there is a runtime/semantic problem (`RUN_FAIL`), not a
compile/link problem.

## 4. Observed F7 hit

Reproduced identically in every run that included the F7 cases:

| run | selected | OK | ICE | other classes |
|---|---|---|---|---|
| `--limit 20 --jobs 2` | 20 | 20 | 0 | 0 |
| `--limit 100 --jobs 2` | 100 | 90 | 10 | 0 |
| `--limit 110 --jobs 2` (supplementary) | 110 | 100 | 10 | 0 |

The 20-case run covers suites 0–1 (two suites, ten cases each) and is all OK.
The 100-case run produced exactly **one** normalized candidate signature, with
**10 occurrences**:

```
Machine_error(kind=unsupported;
              who=Machine_of_clam_lower.lower_array_make;
              message=uninitialized non-null GC ref arrays are not lowered)
```

- **stage: `build`** (not `test-build`, not `check`)
- **rc: 255**
- **first case ID: `L0080-vt-push-int_enum_string`**
- all 10 IDs: `L0080`–`L0084` (`vt`, suite `[Int, EnumString]`, all five ops)
  and `L0090`–`L0094` (`vt`, suite `[Int, EnumArrayInt]`, all five ops)
- `check` for `L0080` returns rc=0; `build` returns rc=255 with
  `Error: failed to link featfuzz/generated (native): ... moonc link-core ...`
  followed by `Oops, the compiler has encountered an unexpected situation.` and
  the `Machine_error` banner.
- the raw banner also carries
  `function="@_M0MPB18UninitializedArray23unsafe__make__and__blitGRP28featfuzz9generated5EntryE"`;
  the normalizer **drops** the `function` field because it embeds case-specific
  symbols and would defeat deduplication.

Plain-struct controls pass: `L0085`–`L0089` (`plain`, same fields, same ops,
no `#valtype`) are all **OK**, as are `L0095`–`L0099` (plain sibling of suite
9). This is the A/B that makes the hit attributable to `#valtype` rather than
to the fields or the operation.

Two useful refinements over the existing PoC write-up, both observed here:

- The operation is **not** the discriminator. All five ops ICE for the two
  GC-ref suites, because `push`, `Array::makei`, `map`, `filter` and
  `slice(...).to_owned()` all end up constructing `Array[Entry]` through the
  same `UninitializedArray::unsafe_make_and_blit` lowering. The op axis is
  therefore uninformative for F7, while it is still useful for the other
  suites.
- `L0100`–`L0104` (`vt`, suite `[Int, String]`, all five ops) are **OK**. A
  non-null GC reference alone is not enough; it has to be the payload of an
  enum field, exactly as the PoC's minimal-trigger table says. This is a
  genuine discrimination result produced by the matrix, not a restatement.

**This is the known F7 signature, not a new defect.** It matches
`poc/f7_valtype_array_ice/` on the same pinned toolchain and upstream
moonbit-docs issue #1322. The driver found it independently from a generated
package, which is evidence that the generator/oracle pipeline works, not
evidence for an additional bug.

## 5. What the zero/non-zero candidates prove

Zero, and what it does **not** prove:

- Zero `CHECK_FAIL`, `BUILD_FAIL`, `TEST_LINK_FAIL`, `RUN_FAIL`, `INFRA`,
  `TIMEOUT` in 100 cases. That is a real positive result: for the 90 OK cases
  the generated packages type-checked, compiled, linked **both** the executable
  and the blackbox test driver, executed, and produced the exact checksum the
  independent evaluator predicted. So the pipeline has a working happy path and
  the OK count is not "the oracle never gets far enough to fail".
- It does **not** prove there are no other defects. Suites 10–15 were never
  run at 100 cases; only `native`/`debug` was exercised; the oracle is one
  `Int64` per case over arrays of 4–6 elements.
- It does **not** prove the absence of miscompiles. A miscompile that preserves
  the checksum (or that the coarse checksum cannot see) is invisible to this
  oracle. The 90 OK cases are a smoke test of the codegen/runtime path, not a
  semantic equivalence proof.

Non-zero, and what it does **not** prove:

- 10 ICE records collapsing to **1** signature is evidence that normalization
  and deduplication work, and that failures group by mechanism rather than by
  case ID. It also shows the failure is systematic: every `vt` case in the two
  GC-ref suites fails, so this is a shape gate, not a flaky case.
- 10 case IDs with 1 signature is **not** 10 defects; it is one mechanism.
  Conversely, "zero candidates" in some future run would not by itself mean the
  matrix is clean — it could mean the toolchain rejects the generated package
  earlier (that would show up as `CHECK_FAIL`/`INFRA`, which is exactly why
  those classes are counted separately and `candidate` is set only for ICE).

## 6. Limitations

- **Native, debug only.** `--target` and `--mode` are configurable and passed
  through, but only `native` + `debug` was run. F7 is known to pass in
  `--release` and on js/wasm/wasm-gc, so this matrix as run is blind to
  release-only and other-backend defects.
- **One curated layout family.** `--family` currently accepts only `layout`;
  the generator is not a mutator. No random field sampling, no generics, no
  recursion, no nested aggregates beyond one enum level.
- **No async/FFI here.** Generated packages contain no `async fn`, no
  `raise?`, no `extern`/`@ffi` types. The F8/F9 async link-ICE shapes are
  therefore unreachable, even though `test-build` exists precisely for that
  class of defect.
- **F7 fires at `build`, so the driver never reached `test-build` for that
  case.** The stage is exercised by the 90 OK cases, and a manual re-run of
  `moon test --target native --build-only` on the kept `L0080` directory
  returns rc=1 with the *same* `Machine_error`, then `moon test` likewise
  rc=1 — so the new stage does not change F7's attribution; it would matter for
  a defect that only fails at test link (F9). Do not cite this run as proof
  that `test-build` catches things `build` misses; the F9 PoC is that proof.
- **Timeouts.** One per-case budget (default 120000 ms, floored at 1000 ms) is
  shared across all four stages by a wall-clock deadline; a stage gets the
  remaining budget. Exhaustion is classified `TIMEOUT` with `rc=-999` and
  signature `timeout`. With `--jobs > 1`, concurrent `moon` invocations inflate
  per-stage wall time, so a tight budget can produce false `TIMEOUT`s. 0 were
  observed here (jobs 2, 100 cases in ~53 s wall clock, median OK case
  ~1.1 s of stage time).
- **Warning noise.** Every generated package emits
  `Warning: Main package 'featfuzz/generated' uses blackbox-only test inputs
  (_test.mbt files) ... will stop generating blackbox tests in a future
  release.` It is stored in `stderr_short` for OK cases and ignored for
  classification. It is harmless today but is toolchain-version dependent:
  a future `moon` may stop generating blackbox tests for main packages, which
  would silently weaken the `test-build` stage. Pinning the toolchain, or
  moving the test into a non-main package, is the follow-up.
- **`--keep` behavior.** Default: `run_case` deletes the case directory for
  every non-candidate after recording, so `dir` in the JSONL for OK cases is a
  dead path (only ICE candidates are retained). `--keep` retains all 160 dirs
  and all build trees — useful for reduction, but it costs disk and makes the
  next run delete and rebuild them anyway (`rm_rf` at case start). Two runs
  into the same `--out` overwrite `results.jsonl` and `summary.json`, so use
  distinct output roots.
- **Infrastructure detection is textual.** `INFRA` is keyed on strings such as
  "package not found" / "Connection refused"; `ICE` is keyed on banners such as
  `Machine_error(` anywhere in stdout+stderr. A source-level diagnostic that
  happened to contain one of those strings would be misclassified. Generated
  packages declare no dependencies, so normal runs do not touch the network or
  `moonbit/.mooncakes`.
- **Prefix, not sample.** All conclusions about "100 cases" are conclusions
  about the first 10 suites. The remaining 60 cases are simply unmeasured.

## 7. Next axes

1. **ABI/FFI.** `extern` types, C structs passed by value, `@ffi` calls and
   callbacks; this is where native lowering has the most unexercised surface
   and where the F9 "stub wrapper" family lives.
2. **Async.** `async fn`, `raise?` after suspension, coroutine resume; the
   F8/F9 shapes, and the reason the `test-build` stage exists.
3. **Cross-package.** Generated module with 2–3 packages: `#valtype` crossing a
   package boundary, `.mbti` visibility, separate `core` files linked together,
   private-type leakage. This also tests the driver's package writer, which
   currently emits a single package.
4. Smaller follow-ups: finish suites 10–15 (indices 100–159); add a `release`
   arm and a `wasm-gc` arm to the same matrix; add a randomized many-field
   suite as a second family once the curated one is green; make the warning
   handling explicit (treat known warnings as expected output rather than
   noise) so a future toolchain change is caught rather than silently absorbed.

## Appendix: reproduction commands

```sh
cd /tmp/mbtfuzz_feat_agent/moonbit
moon build cmd/featfuzz --target native

# 20-case confirmation (all OK)
./_build/native/debug/build/cmd/featfuzz/featfuzz.exe \
  --out /tmp/ff_confirm20 --limit 20 --jobs 2 --target native --mode debug

# 100-case confirmation: 90 OK / 10 ICE / 1 signature
./_build/native/debug/build/cmd/featfuzz/featfuzz.exe \
  --out /tmp/ff_confirm100 --limit 100 --jobs 2 --target native --mode debug

# supplementary probe: 110 cases adds suite 10 (vt Int+String), all OK
./_build/native/debug/build/cmd/featfuzz/featfuzz.exe \
  --out /tmp/ff_probe110 --limit 110 --jobs 2 --target native --mode debug

# kept F7 case, manual stage replay
cd /tmp/ff_confirm100/cases/L0080-vt-push-int_enum_string
moon check --target native                      # rc=0
moon build --target native                      # rc=255, ICE
moon test  --target native --build-only         # rc=1, same ICE
moon test  --target native                      # rc=1, same ICE
```

`summary.json` of the 100-case run:

```json
{"family":"layout","target":"native","mode":"debug","matrix_size":160,
 "selected":100,"limit":100,"jobs":2,"keep":false,
 "counts":{"OK":90,"CHECK_FAIL":0,"BUILD_FAIL":0,"TEST_LINK_FAIL":0,
           "RUN_FAIL":0,"ICE":10,"INFRA":0,"TIMEOUT":0},
 "distinct_candidate_signatures":1,
 "candidates":[{"signature":"Machine_error(kind=unsupported; who=Machine_of_clam_lower.lower_array_make; message=uninitialized non-null GC ref arrays are not lowered)","class":"ICE","stage":"build","rc":255,"first_id":"L0080-vt-push-int_enum_string","dir":"/tmp/ff_confirm100/cases/L0080-vt-push-int_enum_string","occurrences":10}]}
```

(The `signature` value above is the exact stored form: quotes around `who` and
`message` are stripped, and the case-specific `function=` field is dropped
before storing. The `dir` is only meaningful for candidates, which are kept.)
