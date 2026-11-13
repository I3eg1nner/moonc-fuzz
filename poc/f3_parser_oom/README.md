# F3: 19-byte parser input exhausts memory

Pinned: `moonc v0.10.20+65efd5b93`.

```
cd poc/f3_parser_oom
prlimit --as=6442450944 -- moonc syncheck cmd/main.mbt
echo $?          # 134 (SIGABRT), stderr: Fatal error: out of memory
```

Input: `fn r(){y(for in ]\n[` (19 B).  With a 6 GiB address-space cap it hits
5.2–5.7 GiB and aborts.  **Do not run uncapped** on a shared host: the
uncapped control was observed earlier at 8.2 GiB in 20 s and was still
growing; that control was not re-run for this review.
