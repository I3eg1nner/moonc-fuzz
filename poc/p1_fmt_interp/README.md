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

The exact defect claim is **superlinear growth ~10x per doubling**, not a
single absolute time.  A plain string of the same size is the control.
