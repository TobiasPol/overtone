/* Mono sample buffers fed by the IO thread: an overwriting ring for the spectrum analyzer (it only
   wants the newest samples) and a non-overwriting queue for the music type detector. */
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

/* Producer (IO thread). Never writes a slot the consumer has not released, so a stalled consumer
   can't see samples change under it; when the queue is full the newest samples are dropped
   instead, and the IO thread never waits. */
void ot_fifo_write(ot_fifo *q, const float *l, const float *r, uint32_t n) {
    uint32_t w = atomic_load_explicit(&q->write, memory_order_relaxed);
    uint32_t space = OT_ANALYZER_SIZE - (w - atomic_load_explicit(&q->read, memory_order_acquire));
    if (n > space) {
        n = space;
    }
    for (uint32_t i = 0; i < n; i++) {
        q->data[(w + i) & OT_RING_MASK] = 0.5f * (l[i] + r[i]);
    }
    atomic_store_explicit(&q->write, w + n, memory_order_release);
}

/* Consumer. Copies up to `max` samples in order, then releases their slots to the producer. */
uint32_t ot_fifo_read(ot_fifo *q, float *dst, uint32_t max) {
    uint32_t rd = atomic_load_explicit(&q->read, memory_order_relaxed);
    uint32_t count = atomic_load_explicit(&q->write, memory_order_acquire) - rd;
    if (count > max) {
        count = max;
    }
    for (uint32_t i = 0; i < count; i++) {
        dst[i] = q->data[(rd + i) & OT_RING_MASK];
    }
    atomic_store_explicit(&q->read, rd + count, memory_order_release);
    return count;
}
