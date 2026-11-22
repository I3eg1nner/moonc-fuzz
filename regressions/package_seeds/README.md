# H4 package seeds

- `single/` — one package (`moon info` / mbti shape);
- `double/` — two packages with an import; missing trait import must be rejected;
- `blackbox/` — a package's own blackbox test; `skip_current_package` warning leakage
  (1294).
