# F2: invalid escape in a string literal reaches an ICE

Pinned: `moonc v0.10.20+65efd5b93`; driver `moon 0.1.20261104`.

```
cd poc/f2_lex_escape_ice
rm -rf _build
moon check
echo $?          # 1
```

`cmd/main.mbt` contains `let s = "\中"`.  `moonc syncheck` alone returns 0
(parser accepts it); the driver's check path reaches the typer and emits the
ICE banner with `Invalid_argument("Char.chr")`.  The driver maps the ICE to
rc 1, so the banner is the discriminator.
