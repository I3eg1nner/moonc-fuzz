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
