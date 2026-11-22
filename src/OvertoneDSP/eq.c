#include <math.h>
#include <stdbool.h>
#include <string.h>
#include "dsp_internal.h"
#include "ot_biquad.h"

void ot_eq_reset(ot_eq *eq) {
    memset(eq, 0, sizeof(*eq));
}

static void finish_state(ot_bq_state *s, double z1, double z2) {
    /* An unstable or NaN-poisoned section must not keep ringing forever. */
    if (!isfinite(z1) || !isfinite(z2)) {
        z1 = 0.0;
        z2 = 0.0;
    }
    s->z1 = z1;
    s->z2 = z2;
}

static void run_static(ot_biquad_coeffs c, ot_bq_state *s, float *x, uint32_t n) {
    double z1 = s->z1, z2 = s->z2;
    for (uint32_t i = 0; i < n; i++) {
        double in = x[i];
        double out = (double)c.b0 * in + z1;
        z1 = (double)c.b1 * in - (double)c.a1 * out + z2;
        z2 = (double)c.b2 * in - (double)c.a2 * out;
        x[i] = (float)out;
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
    double z1 = s->z1, z2 = s->z2;
    for (uint32_t i = 0; i < n; i++) {
        c.b0 += d0; c.b1 += d1; c.b2 += d2; c.a1 += d3; c.a2 += d4;
        double in = x[i];
        double out = (double)c.b0 * in + z1;
        z1 = (double)c.b1 * in - (double)c.a1 * out + z2;
        z2 = (double)c.b2 * in - (double)c.a2 * out;
        x[i] = (float)out;
    }
    finish_state(s, z1, z2);
}

/* Smoothly crossfades a removed filter's output back to dry so its poles never sweep. */
static void fade_out(ot_biquad_coeffs c, ot_bq_state *s, float *x, uint32_t n) {
    double z1 = s->z1, z2 = s->z2;
    float inv = 1.0f / (float)n;
    for (uint32_t i = 0; i < n; i++) {
        double in = x[i];
        double out = (double)c.b0 * in + z1;
        z1 = (double)c.b1 * in - (double)c.a1 * out + z2;
        z2 = (double)c.b2 * in - (double)c.a2 * out;
        float t = (float)(n - 1 - i) * inv;
        x[i] = (float)(in + (double)t * (out - in));
    }
    finish_state(s, z1, z2);
}

static bool is_identity(const ot_biquad_coeffs *c) {
    return c->b0 == 1.0f && c->b1 == 0.0f && c->b2 == 0.0f && c->a1 == 0.0f && c->a2 == 0.0f;
}

void ot_eq_process(ot_eq *eq, const ot_params *p, float *l, float *r, uint32_t n) {
    if (n == 0) return;
    uint32_t count = p->band_count > OT_MAX_BANDS ? OT_MAX_BANDS : p->band_count;
    uint32_t prev_count = eq->count;
    ot_biquad_coeffs id = ot_biquad_identity();
    /* Newly appearing sections start settled on the first block, or ramp from identity live. */
    for (uint32_t b = prev_count; b < count; b++) {
        eq->cur[b] = eq->primed ? id : p->bands[b];
        memset(&eq->state[0][b], 0, sizeof(ot_bq_state));
        memset(&eq->state[1][b], 0, sizeof(ot_bq_state));
    }
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
    /* Removed trailing sections crossfade to dry after retained sections to keep cascade order intact. */
    for (uint32_t b = count; b < prev_count; b++) {
        if (!is_identity(&eq->cur[b])) {
            fade_out(eq->cur[b], &eq->state[0][b], l, n);
            fade_out(eq->cur[b], &eq->state[1][b], r, n);
        }
        eq->cur[b] = id;
        memset(&eq->state[0][b], 0, sizeof(ot_bq_state));
        memset(&eq->state[1][b], 0, sizeof(ot_bq_state));
    }
    eq->count = count;
    eq->primed = true;
}
