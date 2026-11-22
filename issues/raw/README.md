# Raw issue snapshot

Source: `moonbitlang/moonbit-docs` issues, `state=all`, fetched 2026-11-22
with authenticated `gh` (not curl), paginated 100/page.

- file: `moonbit-docs-issues-2026-11-22.json`
- rows: 561 issues (57 open, 504 closed; PRs filtered out)
- rows with a fenced code block: 292
- sha256: `0d80d3dcfe8333f9350056c5e9aaf62dd7fdd94c3761dc83a9b37f772cd46af9`

Fetch command (does not modify upstream):

```bash
gh api --paginate --slurp \
  "repos/moonbitlang/moonbit-docs/issues?state=all&per_page=100" \
  > /tmp/moonbit_docs_issues_pages.json
# flatten pages, drop pull_request rows, write this file
```

The curated subset and statuses are in `issues/curated.json`; derived minimal
repros are in `oracle_cases/<category>/<issue>/`.


## Other repos (E4 snapshot, 2026-11-22)

`moonbit-docs` is the canonical public ICE/bug entry (the compiler repo
`moonbitlang/moonbit-compiler` has `has_issues=false`). Other repos do have
issues; their snapshots are stored separately and are **not** merged into the
561-issue `moonbit-docs` recall denominator:

| repo | file | issues | open |
|---|---|---:|---:|
| `moonbitlang/core` | `moonbit-core-issues-2026-11-22.json` | 755 | 149 |
| `moonbitlang/moon` | `moonbit-moon-issues-2026-11-22.json` | 513 | 134 |
| `moonbitlang/async` | `moonbit-async-issues-2026-11-22.json` | 88 | 25 |

Hashes:

```text
issues/raw/moonbit-core-issues-2026-11-22.json  51fabf3c2a409d61c3d7fe9c228ab4696a9a9df3a47bfa612f13c89a590e6dfa
issues/raw/moonbit-moon-issues-2026-11-22.json  4ea5d3c32c07b933f51ba34f97a26e81695048547d12b9c71dd27c857bceb6ad
issues/raw/moonbit-async-issues-2026-11-22.json  60af419930292128e3c7763351567747fcd8746325c14167a7721fc4e0838ccb
```

`core` 303 / `moon` 157 / `async` 58 title+body keyword-defect hits, but they are
library/build-system/async-runtime repos, not the closed-source compiler entry;
they are listed as E4 scope, not silently folded into moonbit-docs.
