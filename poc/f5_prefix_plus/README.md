# F5: prefix `+` becomes the unlexable name `~+`

Pinned: `moonc`/`moonfmt` v0.10.20+65efd5b93 (2026-11-05).

```
moonc syncheck u.mbt            # 0 (parses)
moonfmt u.mbt                   # prints ~+(y)
moonfmt u.mbt -o u1.mbt
moonc syncheck u1.mbt           # 2, E3001 unrecognized character "~"
moon check u.mbt                # "The value identifier ~+ is unbound"
```

Matrix (`out/f5_matrix.json`): `+1` folds to `1` and typechecks; `+(1)`, `+y`,
`+(y)`, `x ++ y`, `x + ++y` all fail typecheck with unbound `~+` and format to
unparseable `~+(...)`; unary minus controls (`-y`, `-(y)`, `-1`, `x + -y`) are
clean.  Real corpus 662/662 formats and re-parses; the 43/467 failing
parse-accepted mutants are all this one signature.

P1 (formatter interpolation complexity) repro: generate a string with 2,048
`\{i}` segments in a package and time `moon fmt`; see
`findings/syntax_boundary.md` for the measured curve.
