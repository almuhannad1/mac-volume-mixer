#ifndef REALTIME_ATOMICS_H
#define REALTIME_ATOMICS_H

// Lock-free float cells shared between the Core Audio IO thread and the main thread.
// The struct is opaque so Swift only ever sees a pointer.

#pragma clang assume_nonnull begin

typedef struct rt_atomic_float rt_atomic_float;

rt_atomic_float *rt_atomic_float_create(float initial_value);
void rt_atomic_float_destroy(rt_atomic_float *cell);

void rt_atomic_float_store(rt_atomic_float *cell, float value);
float rt_atomic_float_load(rt_atomic_float *cell);
float rt_atomic_float_exchange(rt_atomic_float *cell, float value);

/// Raises the stored value to `value` if it is larger (used to accumulate peaks).
void rt_atomic_float_store_max(rt_atomic_float *cell, float value);

#pragma clang assume_nonnull end

#endif
