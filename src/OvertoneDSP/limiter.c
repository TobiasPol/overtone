/*
 * Look-ahead peak limiter. The gain computer looks at the incoming signal
 * while the audio itself is delayed by the look-ahead window, so gain
 * reduction is already in place when a peak reaches the output.
 */
#include <math.h>
#include <string.h>
#include "dsp_internal.h"

static void clear_history(ot_limiter *l) {
    memset(l->delay, 0, sizeof(l->delay));
    for (uint32_t i = 0; i < OT_LIMITER_LOOKAHEAD_MAX; i++) {
        l->target[i] = 1.0f;
    }
    l->env = 1.0f;
    l->pos = 0;
}

void ot_limiter_prepare(ot_limiter *l, float fs) {
    memset(l, 0, sizeof(*l));
    uint32_t len = (uint32_t)(fs * 0.001f); /* 1 ms look-ahead */
    if (len < 1) len = 1;
    if (len >= OT_LIMITER_LOOKAHEAD_MAX) len = OT_LIMITER_LOOKAHEAD_MAX - 1;
    l->len = len;
    clear_history(l);
    l->attack = 1.0f - expf(-4.0f / (float)len);
    l->release_ms = -1.0f;
}

static inline float window_min(const float *v, uint32_t len) {
    float m = v[0];
    for (uint32_t i = 1; i < len; i++) {
        m = v[i] < m ? v[i] : m;
    }
    return m;
}

static inline float clampf(float v, float limit) {
    return v > limit ? limit : (v < -limit ? -limit : v);
}

void ot_limiter_process(ot_limiter *l, const ot_params *p, float fs,
                        float *left, float *right, uint32_t n) {
    if (!p->limiter_enabled) {
        l->active = false;
        return;
    }
    if (!l->active) { /* re-enabled: don't replay audio or gain from the last time it ran */
        clear_history(l);
        l->active = true;
    }
    if (p->limiter_release_ms != l->release_ms) {
        float ms = p->limiter_release_ms < 1.0f ? 1.0f : p->limiter_release_ms;
        l->release = 1.0f - expf(-1.0f / (ms * 0.001f * fs));
        l->release_ms = p->limiter_release_ms;
    }
    float ceiling = p->limiter_ceiling > 0.0f ? p->limiter_ceiling : 1.0f;
    for (uint32_t i = 0; i < n; i++) {
        float peak = fmaxf(fabsf(left[i]), fabsf(right[i]));
        l->target[l->pos] = peak > ceiling ? ceiling / peak : 1.0f;
        float dl = l->delay[0][l->pos], dr = l->delay[1][l->pos];
        l->delay[0][l->pos] = left[i];
        l->delay[1][l->pos] = right[i];
        if (++l->pos >= l->len) l->pos = 0;
        float goal = window_min(l->target, l->len);
        l->env += (goal - l->env) * (goal < l->env ? l->attack : l->release);
        left[i] = clampf(dl * l->env, ceiling);
        right[i] = clampf(dr * l->env, ceiling);
    }
}
