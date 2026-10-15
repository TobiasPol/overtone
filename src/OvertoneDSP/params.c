#include <string.h>
#include "dsp_internal.h"

#define OT_BOX_DIRTY 4u
#define OT_BOX_INDEX 3u

void ot_params_init(ot_params *p, float sample_rate) {
    memset(p, 0, sizeof(*p));
    p->sample_rate = sample_rate;
    p->preamp = 1.0f;
    p->width = 1.0f;
    p->crossfeed_cutoff = 700.0f;
    p->reverb_size = 0.5f;
    p->reverb_damping = 0.5f;
    p->reverb_width = 1.0f;
    p->volume = 1.0f;
    p->limiter_ceiling = 0.966f; /* -0.3 dBFS */
    p->limiter_release_ms = 80.0f;
    p->tap_count = 1;
    p->tap_gain[0] = 1.0f;
    p->out_left = 0;
    p->out_right = 1;
}

void ot_params_set_band(ot_params *p, uint32_t index, ot_biquad_coeffs c) {
    if (index < OT_MAX_BANDS) {
        p->bands[index] = c;
    }
}

void ot_params_set_tap_gain(ot_params *p, uint32_t index, float gain) {
    if (index < OT_MAX_TAPS) {
        p->tap_gain[index] = gain;
    }
}

void ot_box_init(ot_param_box *box, const ot_params *initial) {
    for (int i = 0; i < 3; i++) {
        box->slots[i] = *initial;
    }
    box->front = 0;
    box->back = 1;
    atomic_store(&box->middle, 2u);
}

/* Writer: fill the private back slot, then trade it for the shared middle slot. */
void ot_box_publish(ot_param_box *box, const ot_params *p) {
    box->slots[box->back] = *p;
    uint32_t prev = atomic_exchange_explicit(&box->middle, box->back | OT_BOX_DIRTY,
                                             memory_order_acq_rel);
    box->back = prev & OT_BOX_INDEX;
}

/* Reader: if the writer published something new, trade the front slot for it. */
const ot_params *ot_box_acquire(ot_param_box *box) {
    if (atomic_load_explicit(&box->middle, memory_order_relaxed) & OT_BOX_DIRTY) {
        uint32_t prev = atomic_exchange_explicit(&box->middle, box->front, memory_order_acq_rel);
        box->front = prev & OT_BOX_INDEX;
    }
    return &box->slots[box->front];
}
