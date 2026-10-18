#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "dsp_internal.h"

ot_dsp *ot_dsp_create(void) {
    ot_dsp *d = calloc(1, sizeof(ot_dsp));
    if (d == NULL) return NULL;
    if (!ot_reverb_alloc(&d->reverb)) {
        free(d);
        return NULL;
    }
    ot_params initial;
    ot_params_init(&initial, 48000.0f);
    ot_box_init(&d->box, &initial);
    atomic_init(&d->chain, NULL);
    atomic_init(&d->chain_in_use, NULL);
    atomic_init(&d->peak_l, 0.0f);
    atomic_init(&d->peak_r, 0.0f);
    atomic_init(&d->cycles, 0);
    ot_dsp_prepare(d, 48000.0f);
    return d;
}

void ot_dsp_destroy(ot_dsp *dsp) {
    if (dsp == NULL) return;
    ot_reverb_free(&dsp->reverb);
    free(dsp);
}

void ot_dsp_prepare(ot_dsp *dsp, float sample_rate) {
    float fs = sample_rate > 0 ? sample_rate : 48000.0f;
    dsp->sample_rate = fs;
    ot_eq_reset(&dsp->eq);
    ot_crossfeed_prepare(&dsp->xfeed, fs);
    ot_reverb_prepare(&dsp->reverb, fs);
    ot_limiter_prepare(&dsp->limiter, fs);
    dsp->smooth.coef = 1.0f - expf(-1.0f / (0.008f * fs)); /* ~8 ms parameter glide */
    dsp->smooth.primed = false;
}

void ot_dsp_publish(ot_dsp *dsp, const ot_params *params) {
    ot_box_publish(&dsp->box, params);
}

static void balance_gains(const ot_params *p, float *gl, float *gr) {
    float b = p->balance < -1.0f ? -1.0f : (p->balance > 1.0f ? 1.0f : p->balance);
    *gl = p->volume * (b > 0.0f ? 1.0f - b : 1.0f);
    *gr = p->volume * (b < 0.0f ? 1.0f + b : 1.0f);
}

/* First block after prepare(): jump straight to targets instead of gliding from zero. */
static void prime(ot_smoothers *s, const ot_params *p) {
    if (s->primed) return;
    s->preamp = p->preamp;
    s->width = p->width;
    balance_gains(p, &s->vol_l, &s->vol_r);
    for (uint32_t i = 0; i < OT_MAX_TAPS; i++) {
        s->tap[i] = p->tap_gain[i];
    }
    s->primed = true;
}

static void apply_gain(float *g, float target, float coef, float *l, float *r, uint32_t n) {
    float v = *g;
    for (uint32_t i = 0; i < n; i++) {
        v += (target - v) * coef;
        l[i] *= v;
        r[i] *= v;
    }
    *g = v;
}

static void apply_volume(ot_smoothers *s, const ot_params *p, float *l, float *r, uint32_t n) {
    float tl, tr;
    balance_gains(p, &tl, &tr);
    float vl = s->vol_l, vr = s->vol_r, k = s->coef;
    for (uint32_t i = 0; i < n; i++) {
        vl += (tl - vl) * k;
        vr += (tr - vr) * k;
        l[i] *= vl;
        r[i] *= vr;
    }
    s->vol_l = vl;
    s->vol_r = vr;
}

static float sanitize(float *x, uint32_t n) {
    float peak = 0.0f;
    for (uint32_t i = 0; i < n; i++) {
        float v = x[i];
        if (!isfinite(v)) v = 0.0f;
        v = v > 1.0f ? 1.0f : (v < -1.0f ? -1.0f : v);
        x[i] = v;
        peak = fmaxf(peak, fabsf(v));
    }
    return peak;
}

static void store_peak(_Atomic float *slot, float peak) {
    if (peak > atomic_load_explicit(slot, memory_order_relaxed)) {
        atomic_store_explicit(slot, peak, memory_order_relaxed);
    }
}

void ot_dsp_run_chain(ot_dsp *d, const ot_params *p, float *l, float *r, uint32_t n) {
    ot_smoothers *s = &d->smooth;
    prime(s, p);
    if (p->detector_enabled) {
        ot_fifo_write(&d->detector, l, r, n); /* before any processing, so EQ never feeds back */
    }
    apply_gain(&s->preamp, p->preamp, s->coef, l, r, n);
    ot_eq_process(&d->eq, p, l, r, n);
    ot_width_process(&s->width, p->width, s->coef, l, r, n);
    ot_crossfeed_process(&d->xfeed, p, d->sample_rate, l, r, n);
    ot_reverb_process(&d->reverb, p, d->sample_rate, l, r, n);
    ot_plugins_process(d, l, r, n);
    if (p->analyzer_enabled) {
        ot_ring_write(&d->analyzer, l, r, n);
    }
    apply_volume(s, p, l, r, n);
    ot_limiter_process(&d->limiter, p, d->sample_rate, l, r, n);
    store_peak(&d->peak_l, sanitize(l, n));
    store_peak(&d->peak_r, sanitize(r, n));
}

void ot_dsp_process(ot_dsp *dsp, float *left, float *right, uint32_t frames) {
    const ot_params *p = ot_box_acquire(&dsp->box);
    uint32_t done = 0;
    while (done < frames) {
        uint32_t n = frames - done > OT_MAX_CHUNK ? OT_MAX_CHUNK : frames - done;
        ot_dsp_run_chain(dsp, p, left + done, right + done, n);
        done += n;
    }
}

uint32_t ot_dsp_read_analyzer(ot_dsp *dsp, float *dst, uint32_t count) {
    return ot_ring_read(&dsp->analyzer, dst, count);
}

uint32_t ot_dsp_drain_detector(ot_dsp *dsp, float *dst, uint32_t max) {
    return ot_fifo_read(&dsp->detector, dst, max);
}

void ot_dsp_read_peaks(ot_dsp *dsp, float *left, float *right) {
    *left = atomic_exchange_explicit(&dsp->peak_l, 0.0f, memory_order_relaxed);
    *right = atomic_exchange_explicit(&dsp->peak_r, 0.0f, memory_order_relaxed);
}

uint64_t ot_dsp_cycle_count(ot_dsp *dsp) {
    return atomic_load_explicit(&dsp->cycles, memory_order_relaxed);
}
