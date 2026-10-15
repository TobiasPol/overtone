#include <math.h>
#include <string.h>
#include "dsp_internal.h"

/* Mid/side stereo width with a smoothed width factor. */
void ot_width_process(float *width, float target, float coef, float *l, float *r, uint32_t n) {
    float w = *width;
    if (fabsf(w - 1.0f) < 1e-4f && fabsf(target - 1.0f) < 1e-4f) {
        *width = 1.0f;
        return;
    }
    for (uint32_t i = 0; i < n; i++) {
        w += (target - w) * coef;
        float mid = 0.5f * (l[i] + r[i]);
        float side = 0.5f * (l[i] - r[i]) * w;
        l[i] = mid + side;
        r[i] = mid - side;
    }
    *width = w;
}

void ot_crossfeed_prepare(ot_crossfeed *x, float fs) {
    memset(x, 0, sizeof(*x));
    uint32_t len = (uint32_t)(fs * 0.0003f); /* ~300 µs interaural delay */
    if (len < 1) len = 1;
    if (len >= OT_XFEED_DELAY_MAX) len = OT_XFEED_DELAY_MAX - 1;
    x->delay_len = len;
}

/*
 * Headphone crossfeed in the spirit of Bauer's bs2b: each ear receives a
 * delayed, low-passed copy of the opposite channel, which collapses the
 * unnatural "inside the head" stereo image of hard-panned mixes.
 */
void ot_crossfeed_process(ot_crossfeed *x, const ot_params *p, float fs,
                          float *l, float *r, uint32_t n) {
    if (p->crossfeed <= 0.0f) {
        x->active = false;
        return;
    }
    if (!x->active) {
        memset(x->delay, 0, sizeof(x->delay));
        x->lp[0] = x->lp[1] = 0.0f;
        x->active = true;
    }
    float a = 1.0f - expf(-2.0f * (float)M_PI * p->crossfeed_cutoff / fs);
    float level = p->crossfeed * 0.7f;
    float norm = 1.0f / (1.0f + level);
    for (uint32_t i = 0; i < n; i++) {
        float dl = x->delay[0][x->pos], dr = x->delay[1][x->pos];
        x->delay[0][x->pos] = l[i];
        x->delay[1][x->pos] = r[i];
        if (++x->pos >= x->delay_len) x->pos = 0;
        x->lp[0] += a * (dl - x->lp[0]);
        x->lp[1] += a * (dr - x->lp[1]);
        l[i] = (l[i] + level * x->lp[1]) * norm;
        r[i] = (r[i] + level * x->lp[0]) * norm;
    }
}
