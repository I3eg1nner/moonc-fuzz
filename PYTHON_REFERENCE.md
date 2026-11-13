# Python reference branch

This branch preserves the Python fuzzing/analysis stack and the archived
pilots as they existed before the MoonBit migration.  The `main` branch is the
MoonBit-native default path; use this branch only for independent comparison or
historical reproduction.

Typical entry points here:

```bash
python3 harness/mbtfuzz.py --mode mbt --workers 48 --duration 600
python3 harness/cov.py funcs <corpus> --stage build --out out/cov.json
python3 harness/syntax_boundary.py
python3 harness/validate_findings.py
```

Pinned toolchain for the recorded results:

```
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
```
