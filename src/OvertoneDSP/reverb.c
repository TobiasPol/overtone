/* Room simulation based on Jezar's public-domain Freeverb, plus a pre-delay. */
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "dsp_internal.h"

static const uint32_t kCombTuning[OT_REVERB_COMBS] = { 1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617 };
static const uint32_t kAllpassTuning[OT_REVERB_ALLPASSES] = { 556, 441, 341, 225 };
static const uint32_t kStereoSpread = 23;

bool ot_reverb_alloc(ot_reverb *r) {
    memset(r, 0, sizeof(*r));
    size_t per_channel = OT_COMB_MAX * OT_REVERB_COMBS + OT_ALLPASS_MAX * OT_REVERB_ALLPASSES;
    r->pool_len = per_channel * 2 + OT_PREDELAY_MAX;
    r->pool = calloc(r->pool_len, sizeof(float));
    if (!r->pool) return false;
    float *cursor = r->pool;
    for (int ch = 0; ch < 2; ch++) {
        for (int i = 0; i < OT_REVERB_COMBS; i++) { r->comb[ch][i].buf = cursor; cursor += OT_COMB_MAX; }
        for (int i = 0; i < OT_REVERB_ALLPASSES; i++) { r->ap[ch][i].buf = cursor; cursor += OT_ALLPASS_MAX; }
    }
    r->predelay = cursor;
    return true;
}

void ot_reverb_free(ot_reverb *r) {
    free(r->pool);
    r->pool = NULL;
}

static uint32_t scaled_len(uint32_t base, float scale, uint32_t max) {
    uint32_t len = (uint32_t)((float)base * scale);
    if (len < 1) len = 1;
    return len > max ? max : len;
}

void ot_reverb_prepare(ot_reverb *r, float fs) {
    float scale = fs / 44100.0f;
    for (uint32_t ch = 0; ch < 2; ch++) {
        for (int i = 0; i < OT_REVERB_COMBS; i++) {
            ot_comb *c = &r->comb[ch][i];
            c->len = scaled_len(kCombTuning[i] + ch * kStereoSpread, scale, OT_COMB_MAX);
            c->idx = 0;
            c->store = 0.0f;
        }
        for (int i = 0; i < OT_REVERB_ALLPASSES; i++) {
            ot_allpass *a = &r->ap[ch][i];
            a->len = scaled_len(kAllpassTuning[i] + ch * kStereoSpread, scale, OT_ALLPASS_MAX);
            a->idx = 0;
        }
    }
    memset(r->pool, 0, r->pool_len * sizeof(float));
    r->pre_pos = 0;
    r->wet = 0.0f;
    r->active = false;
}

static inline float comb_tick(ot_comb *c, float in, float feedback, float damp) {
    float out = c->buf[c->idx];
    c->store = out * (1.0f - damp) + c->store * damp;
    c->buf[c->idx] = in + c->store * feedback;
    if (++c->idx >= c->len) c->idx = 0;
    return out;
}

static inline float allpass_tick(ot_allpass *a, float in) {
    float buffered = a->buf[a->idx];
    a->buf[a->idx] = in + buffered * 0.5f;
    if (++a->idx >= a->len) a->idx = 0;
    return buffered - in;
}

/* Always records, even with zero delay, so raising the pre-delay never replays stale audio. */
static inline float predelay_tick(ot_reverb *r, float in, uint32_t delay) {
    r->predelay[r->pre_pos] = in;
    uint32_t read = (r->pre_pos + OT_PREDELAY_MAX - delay) % OT_PREDELAY_MAX;
    if (++r->pre_pos >= OT_PREDELAY_MAX) r->pre_pos = 0;
    return delay == 0 ? in : r->predelay[read];
}

static void tank(ot_reverb *r, float in, float feedback, float damp, float *ol, float *or_) {
    float a = 0.0f, b = 0.0f;
    for (int i = 0; i < OT_REVERB_COMBS; i++) {
        a += comb_tick(&r->comb[0][i], in, feedback, damp);
        b += comb_tick(&r->comb[1][i], in, feedback, damp);
    }
    for (int i = 0; i < OT_REVERB_ALLPASSES; i++) {
        a = allpass_tick(&r->ap[0][i], a);
        b = allpass_tick(&r->ap[1][i], b);
    }
    *ol = a;
    *or_ = b;
}

void ot_reverb_process(ot_reverb *r, const ot_params *p, float fs, float *l, float *rr, uint32_t n) {
    if (p->reverb_mix <= 0.0f && r->wet < 1e-4f) {
        r->active = false;
        r->wet = 0.0f;
        return;
    }
    if (!r->active) { /* drop stale tails from the last time the room was enabled */
        memset(r->pool, 0, r->pool_len * sizeof(float));
        r->active = true;
    }
    float feedback = p->reverb_size * 0.28f + 0.7f;
    float damp = p->reverb_damping * 0.4f;
    float pre_f = p->reverb_predelay_ms * 0.001f * fs;
    uint32_t pre = pre_f <= 0 ? 0 : (pre_f >= OT_PREDELAY_MAX ? OT_PREDELAY_MAX - 1 : (uint32_t)pre_f);
    float k = 1.0f - expf(-1.0f / (0.02f * fs));
    float width = p->reverb_width;
    for (uint32_t i = 0; i < n; i++) {
        r->wet += (p->reverb_mix - r->wet) * k;
        float wet = r->wet * 3.0f, dry = 1.0f - r->wet * 0.5f;
        float wet1 = wet * (width * 0.5f + 0.5f), wet2 = wet * ((1.0f - width) * 0.5f);
        float in = predelay_tick(r, (l[i] + rr[i]) * 0.015f, pre);
        float ol, orr;
        tank(r, in, feedback, damp, &ol, &orr);
        float nl = ol * wet1 + orr * wet2 + l[i] * dry;
        rr[i] = orr * wet1 + ol * wet2 + rr[i] * dry;
        l[i] = nl;
    }
}
