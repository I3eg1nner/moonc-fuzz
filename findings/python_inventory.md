# Tracked `.py` inventory (correcting the old "no .py" invariant)

Date: 2026-11-22. Pin unchanged.

The earlier claim "main branch contains no `.py`" is **false**. The repository
has 20 tracked `.py` files. The corrected invariant is narrower:

> The MoonBit implementation (`moonbit/**`) and the accept path contain no
> `.py`. The remaining files are vendored third-party code, PoC/manual replay,
> or scratch-only probe scripts. No new `.py` may be added to the build/accept
> path; new gates/harness code must be MoonBit or shell.

| category | count | paths |
|---|---:|---|
| vendored third-party package (`moonldif@0.7.6`) | 15 | `regressions/pkg_semantic/ldif_30/pkg/scripts/*.py` + `pkg/verification/.../paging-recheck-074.py` |
| PoC/manual LSP replay | 3 | `poc/f10_lsp_format_nth_hang/replay.py`, `poc/f11_lsp_scalar_params_deadlock/replay.py`, `poc/f12_lsp_frame_wedge/replay.py` |
| scratch-only feature probes | 2 | `scripts/probe/native_feature_probe.py`, `scripts/probe/async_cancel_probe.py` |

Exact list:

```text
poc/f10_lsp_format_nth_hang/replay.py
poc/f11_lsp_scalar_params_deadlock/replay.py
poc/f12_lsp_frame_wedge/replay.py
regressions/pkg_semantic/ldif_30/pkg/scripts/baseline-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/cli-consumer.py
regressions/pkg_semantic/ldif_30/pkg/scripts/openldap-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/package-cli.py
regressions/pkg_semantic/ldif_30/pkg/scripts/package-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/pinned_download.py
regressions/pkg_semantic/ldif_30/pkg/scripts/prepare-moonldap.py
regressions/pkg_semantic/ldif_30/pkg/scripts/publication-privacy.py
regressions/pkg_semantic/ldif_30/pkg/scripts/reference-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/registry-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/rfc-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/sdk-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/snapshot-verify.py
regressions/pkg_semantic/ldif_30/pkg/scripts/test_pinned_download.py
regressions/pkg_semantic/ldif_30/pkg/verification/2026-09-28-v0.7.4/paging-recheck-074.py
scripts/probe/native_feature_probe.py
scripts/probe/async_cancel_probe.py
```

Evidence:

```bash
git ls-files | grep '\.py$' | wc -l   # 20
git ls-files -- 'moonbit/**/*.py'   # empty
```

The C-phase `issuecheck` gate is `scripts/issuecheck.sh` (shell); it does not
add a `.py`. The PoC replay and scratch probes are not invoked by
`cmd/accept`; vendored ldif scripts are part of the imported regression fixture.
