# Syntax boundary campaign (codex option 2)

Harness: `harness/syntax_boundary.py` (subcommands `gen / run / scale / probe /
fmt / fmtcorpus / rt / report`).  Raw data: `out/sb_cases.jsonl`,
`out/sb_results.jsonl`, `out/sb_scale.json`, `out/sb_probe.json`,
`out/sb_fmt.jsonl`, `out/sb_fmtcorpus.json`, `out/sb_roundtrip.json`,
`out/f5_matrix.json`, aggregate `out/sb_report.md`.

Three bounded questions: (A) does mutating only *grammatical boundary tokens*
of valid programs produce a new failure class; (B) does any boundary dimension
scale super-linearly; (C) does `moonfmt` round-trip (format → re-parse →
re-format, and format → run → same stdout).

## Method

* 12 valid bases: operator precedence/bitwise, newline vs semicolon, string
  interpolation, patterns/guards/or-patterns, nested delimiters, escapes,
  generics, loops/blocks, lambdas, pipe/arrow, labelled/optional arguments,
  nested match.  All parse clean under `moonc syncheck`.
* Boundary alphabet: `=> -> |> || && == != <= >= << >> ..< .. ( ) { } [ ] , ; | : = < > + - * / % . @ ! ? \ " ' ~ & ^`.
  Mutations: delete / duplicate / replace-by-confusion partner, prefix
  truncation at every boundary, unterminated string/brace/comment/escape, and
  seeded multi-mutation combinations.
* Each case runs `moonc syncheck` under `fork`+`wait4` with a 5 s timeout,
  `RLIMIT_AS = 4 GiB`, and peak RSS from `rusage`.  Total **19,935 unique
  cases** (1,118 single-token, 368 prefix, 48 unterminated, 18,401
  multi-mutation), 258 s wall.
* Scaling: 9 dimensions, k = 4…4096 for eight of them (match arms stop at
  k=512); the same measurement for `moonc syncheck` and `moonfmt`; a focused
  probe isolates interpolation vs plain string vs concatenation (median of 3).
* Formatter: every parse-accepted mutant is formatted, re-parsed, formatted
  again; the 662-file real corpus gets format→re-parse; the 12 bases
  additionally run through `moon run` before/after `moon fmt`.

### Measurement caveat (RSS)

The harness forks the Python parent, then `exec`s the tool.  `ru_maxrss`
survives the exec and therefore has a **floor of ≈8,048 KiB** (measured with
`/bin/true` under the same harness); numbers below that floor are not
resolvable.  For `moonc syncheck` the harness value was cross-checked against
`/usr/bin/time -v` (17,408–17,416 KiB vs 17,416 KiB), so that absolute value
is real.  For `moonfmt` at large sizes the harness value (22,864 KiB) also
matches `/usr/bin/time -v` (22,864 KiB); at small sizes it sits on the floor.

## A. Boundary mutation: 19,935 cases, zero anomalies

| status | n | share |
|---|---:|---:|
| parse error (`E30xx`) | 19,468 | 97.66 % |
| parse-accepted | 467 | 2.34 % |
| ICE / crash / timeout / silent failure | **0** | 0 % |

* **70** non-OK normalized message templates plus the `OK` bucket (71 buckets
  total); **57** of the templates are `E3002` variants, 4 are `E3001` lexing
  errors, the rest one-off codes (`E3004/E3003/E3010/E0005/E3800/E4027/
  E0012/E0022`) plus the `E0051 ambiguous_precedence` warning (exit 0).
  Messages are truncated to 120 characters by the normalizer.
* No case took >126 ms or >42,488 KiB RSS (41.5 MiB / 43.5 MB).
* Acceptance by base: 0.6 % (`matchnest`) … 4.8 % (`str`).
* Systematic acceptances, corrected:
  * `+` duplicated **15/15**: `x ++ y` parses as `x + (+y)`, prefix plus
    (rejected at typecheck, see F5).
  * `+` confused with `-` **15/15**: `x +- y` is plain binary minus applied
    to unary minus and is genuinely valid.
  * `.` duplicated (`..`, range) **12/17**; `.` confused with `,` **13/17**
    (comma/tuple reinterpretation) — these are different results and the
    range explanation belongs to the former.
  * `\` deleted/duplicated inside string literals **7/9** stays lexable.
* Stop-rule caveat: new *message templates* still appeared late — the last
  one on the **19,521st** case (zero-based index 19,520).  By **failure class**
  (ICE, crash, timeout, silent failure) the count is zero for the whole run.

## B. Size scaling: no super-linear parser growth, formatter interpolation anomaly

`moonc syncheck` shows no super-linear growth in the tested range on any of
the nine dimensions: time 8–19 ms, RSS 17.4 MB (k=4…4096 for eight dimensions,
match arms to k=512).

`moonfmt` is cheap on every dimension except string interpolation:

| k (segments) | `moonfmt` time | output bytes | RSS (harness) |
|---:|---:|---:|---:|
| 512 | 129.5 ms | 2,993 | 22.4 MB |
| 1,024 | 1,591.3 ms | 6,089 | 21.1 MB |
| 2,048 | 15,198.8 ms | 13,257 | 22.9 MB |
| 4,096 | >25,000 ms (timeout) | – | 26.8 MB |

Probe per-doubling ratios (median of 3): distinct indices
**12.2× / 12.2× / 9.8×**; repeated `\{x}` 2.4× / 37× / 10.6×; repeated
`\{0}` 2.5× / 34.9× / 10.2×.  This is severe super-linear behaviour in the
tested range (implied effective exponent ≈3.3–3.6); finite measurements do
not establish an asymptotic class.

Controls and confound checks:

* Fixed-width segments (`\{00000000}` repeated, no digit-length growth):
  k=512 0.35 s, 1,024 3.17 s (9.1×), 2,048 **26.89 s** (8.5×) — same
  explosion, so decimal digit length is not the cause.
* Output size is linear in k (13,250 B in → 13,257 B out at k=2,048), so the
  cost is not output-driven.
* CPU-bound: at k=2,048 `/usr/bin/time -v` reports 10.24 s user + 16.64 s
  sys ≈ 26.9 s CPU for the fixed-width variant; harness wall tracks it.
* `moon check` on the same 2,048-segment source: **0.08 s** — the front end
  is fast; the cost is specific to the formatter.
* Plain 2,048-char string formats in 6.1 ms; 2,048-term concatenation grows
  from 7.4 ms (k=128) to 18.0 ms (k=2,048) — cheap and sub-linear in k, not
  flat, but nowhere near the interpolation curve.  No width/line-length flag
  is exposed by `moonfmt`, so the layout-threshold hypothesis could not be
  toggled.
* End-to-end `moon fmt` CLI: 6,082 B / 1,024 segments → 1.56 s; 13,250 B /
  2,048 segments → 14.8–15.1 s, ≈22 MB RSS.  k=4,096 was measured only as
  “>25 s”; k=8,192 (“≈25 min”) is an **extrapolation**, not a measurement.

`if_depth` shows 3.3× time and 3.4× RSS per doubling, but its formatted
output grows 4.0× per doubling (indentation is quadratic in nesting depth), so
that is output-size-driven and **not** reported as a defect.

## C. Formatter round-trip

| population | n | fmt exit 0 | idempotent | formatted output re-parses |
|---|---:|---:|---:|---:|
| parse-accepted mutants | 467 | 467 | 467 | **424** |
| real corpus (`seeds_real`) | 662 | 662 | – | **662** |
| 12 valid bases, run before/after | 12 | 12 | – | 12/12 identical stdout |

The 43 failing mutants (9.2 % of accepted mutants) all share one signature:
`E3001 Lexing error: unrecognized character "~" (U+007E)`, and every one
contains a mutation-introduced *prefix* `+` (`+x`, `x ++ y`, `x + +y`); the
formatter prints `~+(y)`, which cannot be lexed back.  This establishes the
bounded statement “662 real files and 12 valid bases round-trip”; it does not
establish semantic preservation for all well-typed programs.

## Defects

### F5 (new, low severity, tooling/diagnostics): prefix `+` desugars to the unlexable internal identifier `~+`

Minimal repro (27 B):

```
$ printf 'fn f(y : Int) -> Int { +y }\n' > u.mbt
$ moonc syncheck u.mbt ; echo $?        # 0  (parses)
$ moonfmt u.mbt                          # prints:  ~+(y)
$ moonfmt u.mbt -o u1.mbt
$ moonc syncheck u1.mbt ; echo $?        # 2  E3001 unrecognized character "~"
```

Small matrix (`out/f5_matrix.json`; syn = `moonc syncheck`, check = `moon check`):

| source | syn | check | fmt output | re-parse |
|---|---:|---:|---|---:|
| `+1` | 0 | 0 | `1` (literal folded) | 0 |
| `+(1)` | 0 | 1 (`~+` unbound) | `~+(1)` | 2 |
| `+y` | 0 | 1 | `~+(y)` | 2 |
| `+(y)` | 0 | 1 | `~+(y)` | 2 |
| `x ++ y` | 0 | 1 | `x + ~+(y)` | 2 |
| `x + ++y` | 0 | 1 | `x + ~+(~+(y))` | 2 |
| `-y`, `-(y)`, `-1`, `x + -y` | 0 | **0** | unchanged/`-y` | 0 |

Two faces of one root cause (hypothesis: legacy unary-`+` parse path with no
typechecking operation):

1. **Diagnostics leak an internal name.**  `moon check` / `moon run` report
   `The value identifier ~+ is unbound` — a name the lexer rejects, so the
   message cannot be acted on.  The parser should reject unary `+` as
   unsupported, or lower it to a real prelude operation.  `+1` is folded and
   accepted, so this is not “all unary plus is broken”.
2. **Formatter output is not re-parseable.**  `moonfmt` prints the `~+` node,
   violating format→parse.  This is the 43/467 mutant population.

Not a miscompile; not reachable from valid source in the tested corpus
(662/662 clean).  Reproduce the formatter face from any of the 43 ids in
`out/sb_fmt.jsonl` (e.g. `0564afeede6b84f1`).

### P1 (new, low severity, resource): severe super-linear `moonfmt` interpolation-formatting time

k interpolation segments: 0.13 s (512), 1.6 s (1,024), 14.8–15.2 s (2,048),
>25 s (4,096); 8.5–12× per doubling with fixed-width segments ruling out digit
length, linear output size, CPU-bound.  A 13 KB source stalls `moon fmt` for
~15 s; the compiler front end accepts the same file in 0.08 s.  P1 is a
performance-finding identifier, not a priority level.

## Verdict against the stop rule

The literal option-2 rule was **not** satisfied: fewer than 20,000 cases
(19,935), one new defect class (F5), one reproducible scaling anomaly (P1),
and no measurement of “<20 new functions”.  The message-template count (last
new at case 19,521) also shows that template novelty was not saturated.

Following the external review, this run is closed as **“bounded campaign
completed; two findings triaged”**, and the prospective family-level rule is
adopted: stop a boundary family after a rolling 20,000 unique cases with no
new *defect signature* (minimized trigger, failing subsystem/stack, violated
invariant, or scaling behaviour), <20 new functions, and no untriaged scaling
anomaly; diagnostic templates are exploration hints only.  Extending to
configuration/document boundaries (`moon.pkg`, `moon.mod`, `.mbtx`, `.mbt.md`)
requires evidence of a distinct parser/recovery path, not just a new
extension.

Next: the gated four-hour old-compiler pilot (option 3); if its gates fail,
interface-consistency (`build-interface`, source vs interface client check)
and `gen-test-info` metadata consistency are the fallbacks.

## Reproduce

```
python3 harness/syntax_boundary.py selftest
python3 harness/syntax_boundary.py gen --n 20000
python3 harness/syntax_boundary.py run --budget 2400
python3 harness/syntax_boundary.py scale
python3 harness/syntax_boundary.py probe --reps 3
python3 harness/syntax_boundary.py fmt
python3 harness/syntax_boundary.py rt
python3 harness/syntax_boundary.py report
```

Timings on the 128-core host: gen 0.7 s, run 258 s, scale ≈ 6 min (dominated
by the deliberate 25 s interpolation timeout), probe 118 s, fmt 16 s,
rt ≈ 40 s.  F5 matrix and P1 confound checks are ad-hoc commands recorded in
`findings/codex_review_2.md`.
