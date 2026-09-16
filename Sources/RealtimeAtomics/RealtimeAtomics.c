#include "RealtimeAtomics.h"

#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct rt_atomic_float {
    _Atomic(uint32_t) bits;
};

static inline uint32_t to_bits(float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    return bits;
}

static inline float from_bits(uint32_t bits) {
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

rt_atomic_float *rt_atomic_float_create(float initial_value) {
    rt_atomic_float *cell = malloc(sizeof *cell);
    if (cell == NULL) {
        abort();
    }
    atomic_init(&cell->bits, to_bits(initial_value));
    return cell;
}

void rt_atomic_float_destroy(rt_atomic_float *cell) {
    free(cell);
}

void rt_atomic_float_store(rt_atomic_float *cell, float value) {
    atomic_store_explicit(&cell->bits, to_bits(value), memory_order_relaxed);
}

float rt_atomic_float_load(rt_atomic_float *cell) {
    return from_bits(atomic_load_explicit(&cell->bits, memory_order_relaxed));
}

float rt_atomic_float_exchange(rt_atomic_float *cell, float value) {
    return from_bits(atomic_exchange_explicit(&cell->bits, to_bits(value), memory_order_relaxed));
}

void rt_atomic_float_store_max(rt_atomic_float *cell, float value) {
    uint32_t current = atomic_load_explicit(&cell->bits, memory_order_relaxed);
    while (from_bits(current) < value &&
           !atomic_compare_exchange_weak_explicit(&cell->bits, &current, to_bits(value),
                                                  memory_order_relaxed, memory_order_relaxed)) {
    }
}
