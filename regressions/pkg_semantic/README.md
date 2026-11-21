# Package semantic regressions (f8 fixture)

These are **user-code semantic changes**, not moonc defects: the mutation edits
the fixture's own `pick` implementation and a test observes the difference.

Replay: `scripts/replay_pkg_regressions.sh` (baseline must pass; every witness
must fail with the assertion recorded in `manifest.json`).
