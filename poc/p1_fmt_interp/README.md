# P1: formatter interpolation complexity

Pinned toolchain: `moonc v0.10.20+65efd5b93` / `moonfmt` same build.

```
cd poc/p1_fmt_interp
./generate.sh 1024 p.mbt
for i in 1 2 3 4 5; do /usr/bin/time -f '%e s %M KB' moonfmt p.mbt -o out.mbt; done
```

Repeat with 2048.  On the recorded host (2026-11-12) the medians were:

| k | interpolation | plain string |
|---:|---:|---:|
| 1024 | 1,576 ms | 7.5 ms |
| 2048 | 15,072 ms | 6.2 ms |

The observed growth from 1024 to 2048 is about 9.7x.  A plain string of
comparable size is the control.  Two points do not establish an asymptotic
complexity class; the claim is limited to the measured inputs.
