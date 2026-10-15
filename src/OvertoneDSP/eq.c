#include <math.h>
#include <stdbool.h>
#include <string.h>
#include "dsp_internal.h"

void ot_eq_reset(ot_eq *eq) {
    memset(eq, 0, sizeof(*eq));
}

static void finish_state(ot_bq_state *s, float z1, float z2) {
    /* An unstable or NaN-poisoned section must not keep ringing forever. */
    if (!isfinite(z1) || !isfinite(z2)) {
        z1 = 0.0f;
        z2 = 0.0f;
    }
    s->z1 = z1;
    s->z2 = z2;
}

static void run_static(ot_biquad_coeffs c, ot_bq_state *s, float *x, uint32_t n) {
    float z1 = s->z1, z2 = s->z2;
    for (uint32_t i = 0; i < n; i++) {
        float in = x[i];
        float out = c.b0 * in + z1;
        z1 = c.b1 * in - c.a1 * out + z2;
        z2 = c.b2 * in - c.a2 * out;
        x[i] = out;
    }
    finish_state(s, z1, z2);
}

/* Linearly interpolates coefficients across the block to avoid zipper noise. */
static void run_ramp(ot_biquad_coeffs from, ot_biquad_coeffs to, ot_bq_state *s,
                     float *x, uint32_t n) {
    float inv = 1.0f / (float)n;
    float d0 = (to.b0 - from.b0) * inv, d1 = (to.b1 - from.b1) * inv;
    float d2 = (to.b2 - from.b2) * inv, d3 = (to.a1 - from.a1) * inv;
    float d4 = (to.a2 - from.a2) * inv;
    ot_biquad_coeffs c = from;
    float z1 = s->z1, z2 = s->z2;
    for (uint32_t i = 0; i < n; i++) {
        c.b0 += d0; c.b1 += d1; c.b2 += d2; c.a1 += d3; c.a2 += d4;
        float in = x[i];
        float out = c.b0 * in + z1;
        z1 = c.b1 * in - c.a1 * out + z2;
        z2 = c.b2 * in - c.a2 * out;
        x[i] = out;
    }
    finish_state(s, z1, z2);
}

static bool is_identity(const ot_biquad_coeffs *c) {
    return c->b0 == 1.0f && c->b1 == 0.0f && c->b2 == 0.0f && c->a1 == 0.0f && c->a2 == 0.0f;
}

void ot_eq_process(ot_eq *eq, const ot_params *p, float *l, float *r, uint32_t n) {
    uint32_t count = p->band_count > OT_MAX_BANDS ? OT_MAX_BANDS : p->band_count;
    /* Newly appearing sections start settled at their target with clean history. */
    for (uint32_t b = eq->count; b < count; b++) {
        eq->cur[b] = p->bands[b];
        memset(&eq->state[0][b], 0, sizeof(ot_bq_state));
        memset(&eq->state[1][b], 0, sizeof(ot_bq_state));
    }
    eq->count = count;
    for (uint32_t b = 0; b < count; b++) {
        ot_biquad_coeffs target = p->bands[b];
        bool settled = memcmp(&eq->cur[b], &target, sizeof(target)) == 0;
        if (settled && is_identity(&target)) {
            /* Bypassed slot: an identity section's steady state is all zeros, so
               clearing it lets the band re-enter later without a discontinuity. */
            memset(&eq->state[0][b], 0, sizeof(ot_bq_state));
            memset(&eq->state[1][b], 0, sizeof(ot_bq_state));
        } else if (settled) {
            run_static(target, &eq->state[0][b], l, n);
            run_static(target, &eq->state[1][b], r, n);
        } else {
            run_ramp(eq->cur[b], target, &eq->state[0][b], l, n);
            run_ramp(eq->cur[b], target, &eq->state[1][b], r, n);
            eq->cur[b] = target;
        }
    }
}
