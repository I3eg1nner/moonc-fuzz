# 快照冻结（2026-11-11）

所有数字都基于下面这组版本与语料指纹；换版本后必须重测，不能直接比。

## 工具链

| 项 | 值 |
|---|---|
| moon | `moon 0.1.20261104 (940aa18 2026-11-04)` |
| moonc | `v0.10.20+65efd5b93 (2026-11-05)` |
| moonc sha256 | `ec9d278bc212bf47e9ae38457e53635c2d9590aeb3ff1db18356afc8a2872f4f` |
| moonc size | 23432224 bytes |
| moonrun | `moonrun 0.1.20261104 (940aa18 2026-11-04)` |
| AFL++ | `afl-fuzz++5.04a` |
| QEMUAFL | `c05ba961db` |

## 语料指纹（sha256 前 16 位）

| 语料 | 文件数 | 字节 | digest |
|---|---:|---:|---|
| `seeds_real` | 662 | 3929927 | `a1e426d96e41cece` |
| `out/mix300` | 232 | 772266 | `39de95cde6851963` |
| `templates` | 25 | 5872 | `9b1e358ee861db70` |
| `out/boot_real/gen0` | 218 | 714591 | `f09ab19ef5e5bed7` |
| `out/boot_real/gen1` | 244 | 728202 | `61b34dd7d3cce150` |

## harness 包

```
$ sha256sum out/harness_snapshot_2026-11-11.tar.gz
00e52dbf928c6293598f4abc5cdb035a4bd3b4f21924e80f061e3a21c3cc1d5d  out/harness_snapshot_2026-11-11.tar.gz
```

## 随机性

* 所有变异都由 `random.Random(seed)` 驱动，seed 在代码里写死（如 bootstrap 用 `0xB007+i`、
  difftpl 用行号派生），没有用系统熵；
* AFL 的 `-s` 固定种子在 `run.sh` 里；QEMU 覆盖率本身无随机性；
* 因此同版本 + 同语料 + 同 seed 应可逐位复现（唯一例外是 `diag.py` 的 `hash(path)`，
  受 Python 字符串哈希随机化影响，复现时需设 `PYTHONHASHSEED=0`）。
