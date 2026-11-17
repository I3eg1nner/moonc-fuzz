#include "moonbit.h"
#include <stdint.h>
#include <string.h>
static unsigned char sink[16];
void repro_store_v128(uint64_t address, moonbit_v128_t value) { (void)address; memcpy(sink, &value, 16); }
