/* Single-producer/single-consumer ring of mono samples for the spectrum analyzer. */
#include "dsp_internal.h"

#define OT_RING_MASK (OT_ANALYZER_SIZE - 1)

void ot_ring_write(ot_ring *ring, const float *l, const float *r, uint32_t n) {
    uint32_t w = atomic_load_explicit(&ring->write, memory_order_relaxed);
    for (uint32_t i = 0; i < n; i++) {
        ring->data[(w + i) & OT_RING_MASK] = 0.5f * (l[i] + r[i]);
    }
    atomic_store_explicit(&ring->write, w + n, memory_order_release);
}

uint32_t ot_ring_read(ot_ring *ring, float *dst, uint32_t count) {
    if (count > OT_ANALYZER_SIZE / 2) {
        count = OT_ANALYZER_SIZE / 2;
    }
    uint32_t w = atomic_load_explicit(&ring->write, memory_order_acquire);
    uint32_t start = w - count;
    for (uint32_t i = 0; i < count; i++) {
        dst[i] = ring->data[(start + i) & OT_RING_MASK];
    }
    return count;
}
