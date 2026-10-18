/* Private state shared between the DSP translation units. Not exported to Swift. */
#ifndef OT_DSP_INTERNAL_H
#define OT_DSP_INTERNAL_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include "ot_params.h"
#include "ot_plugins.h"

#define OT_XFEED_DELAY_MAX 128
#define OT_LIMITER_LOOKAHEAD_MAX 256
#define OT_REVERB_COMBS 8
#define OT_REVERB_ALLPASSES 4
#define OT_COMB_MAX 7400       /* longest comb at 192 kHz */
#define OT_ALLPASS_MAX 2600
#define OT_PREDELAY_MAX 38400  /* 200 ms at 192 kHz */

typedef struct { float z1, z2; } ot_bq_state;

typedef struct {
    ot_biquad_coeffs cur[OT_MAX_BANDS];
    ot_bq_state state[2][OT_MAX_BANDS];
    uint32_t count;
} ot_eq;

typedef struct {
    float lp[2];
    float delay[2][OT_XFEED_DELAY_MAX];
    uint32_t pos;
    uint32_t delay_len;
    bool active;
} ot_crossfeed;

typedef struct { float *buf; uint32_t len, idx; float store; } ot_comb;
typedef struct { float *buf; uint32_t len, idx; } ot_allpass;

typedef struct {
    ot_comb comb[2][OT_REVERB_COMBS];
    ot_allpass ap[2][OT_REVERB_ALLPASSES];
    float *predelay;
    uint32_t pre_pos;
    float wet;               /* smoothed wet amount */
    bool active;
    float *pool;
    size_t pool_len;
} ot_reverb;

typedef struct {
    float delay[2][OT_LIMITER_LOOKAHEAD_MAX];
    float target[OT_LIMITER_LOOKAHEAD_MAX];
    uint32_t pos, len;
    float env, attack, release, release_ms;
    bool active;
} ot_limiter;

typedef struct {
    float data[OT_ANALYZER_SIZE];
    _Atomic uint32_t write;
} ot_ring;

/* Single-producer/single-consumer queue: the producer never overwrites unread samples. */
typedef struct {
    float data[OT_ANALYZER_SIZE];
    _Atomic uint32_t write; /* advanced by the IO thread */
    _Atomic uint32_t read;  /* advanced by the consumer */
} ot_fifo;

/* Wait-free triple buffer: one writer (main thread), one reader (IO thread). */
typedef struct {
    ot_params slots[3];
    _Atomic uint32_t middle;
    uint32_t back;
    uint32_t front;
} ot_param_box;

typedef struct { const float *left, *right; } ot_plugin_input;

typedef struct {
    float preamp, vol_l, vol_r, width;
    float tap[OT_MAX_TAPS];
    float coef;
    bool primed;
} ot_smoothers;

struct ot_dsp {
    ot_param_box box;
    float sample_rate;
    ot_smoothers smooth;
    ot_eq eq;
    ot_crossfeed xfeed;
    ot_reverb reverb;
    ot_limiter limiter;
    ot_ring analyzer;
    ot_fifo detector;
    _Atomic(ot_plugin_chain *) chain;
    _Atomic(ot_plugin_chain *) chain_in_use;
    ot_plugin_input plugin_input;
    double plugin_sample_time;
    _Atomic float peak_l, peak_r;
    _Atomic uint64_t cycles;
    float left[OT_MAX_CHUNK], right[OT_MAX_CHUNK];
    float scratch_l[OT_MAX_CHUNK], scratch_r[OT_MAX_CHUNK];
};

/* params.c */
void ot_box_init(ot_param_box *box, const ot_params *initial);
void ot_box_publish(ot_param_box *box, const ot_params *p);
const ot_params *ot_box_acquire(ot_param_box *box);

/* eq.c */
void ot_eq_reset(ot_eq *eq);
void ot_eq_process(ot_eq *eq, const ot_params *p, float *l, float *r, uint32_t n);

/* spatial.c */
void ot_width_process(float *width, float target, float coef, float *l, float *r, uint32_t n);
void ot_crossfeed_prepare(ot_crossfeed *x, float fs);
void ot_crossfeed_process(ot_crossfeed *x, const ot_params *p, float fs, float *l, float *r, uint32_t n);

/* reverb.c */
bool ot_reverb_alloc(ot_reverb *r);
void ot_reverb_free(ot_reverb *r);
void ot_reverb_prepare(ot_reverb *r, float fs);
void ot_reverb_process(ot_reverb *r, const ot_params *p, float fs, float *l, float *r_, uint32_t n);

/* limiter.c */
void ot_limiter_prepare(ot_limiter *l, float fs);
void ot_limiter_process(ot_limiter *l, const ot_params *p, float fs, float *left, float *right, uint32_t n);

/* analyzer.c */
void ot_ring_write(ot_ring *ring, const float *l, const float *r, uint32_t n);
uint32_t ot_ring_read(ot_ring *ring, float *dst, uint32_t count);
void ot_fifo_write(ot_fifo *q, const float *l, const float *r, uint32_t n);
uint32_t ot_fifo_read(ot_fifo *q, float *dst, uint32_t max);

/* plugins.c */
void ot_plugins_process(struct ot_dsp *dsp, float *l, float *r, uint32_t n);

/* dsp.c */
void ot_dsp_run_chain(struct ot_dsp *dsp, const ot_params *p, float *l, float *r, uint32_t n);

#endif
