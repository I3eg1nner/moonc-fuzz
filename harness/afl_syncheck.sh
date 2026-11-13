#!/bin/bash
# 参考：正确的 AFL++ QEMU 调用方式。
#
# 不要用 bash 包装 moonc（本文件早期版本就是包装脚本）：
#   QEMU 模式默认只插桩"主可执行文件"的地址区间，bash exec moonc 之后
#   新映像不在插桩范围内，覆盖率会从 ~25k 槽掉到 ~3.2k 槽（实测）。
#
# 正确做法（直接以 moonc 为目标）：
#   AFL_QEMU_MAP_SIZE=262144 AFL_MAP_SIZE=262144 \
#   AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
#   afl-fuzz -Q -i seeds -o out -m none -t 5000 \
#     -- ~/.moon/bin/moonc syncheck -error-format json @@
#
# ICE 的退出码是 199，超出 AFL_CRASH_EXITCODE 允许范围（-127..128），
# 因此跑完后需回放队列自行筛 rc=199 的样本（或 `python3 harness/cov.py` 配套脚本）。
exit 0
