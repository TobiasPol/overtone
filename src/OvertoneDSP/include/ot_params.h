#ifndef OT_PARAMS_H
#define OT_PARAMS_H

#include <stdint.h>

#define OT_MAX_BANDS 64
#define OT_MAX_TAPS 32
#define OT_MAX_PLUGINS 16
#define OT_MAX_CHUNK 1024
#define OT_ANALYZER_SIZE 16384

/* Normalised biquad coefficients (a0 == 1). */
typedef struct {
    float b0, b1, b2, a1, a2;
} ot_biquad_coeffs;

/*
 * Complete snapshot of everything the audio thread needs. The main thread
 * always publishes a full snapshot, so the audio thread never sees a
 * half-updated configuration.
 */
typedef struct {
    float sample_rate;

    /* Equaliser: preamp (linear) followed by a biquad cascade. */
    float preamp;
    uint32_t band_count;
    ot_biquad_coeffs bands[OT_MAX_BANDS];

    /* Spatial audio. */
    float width;              /* 1 = unchanged, 0 = mono, 2 = extra wide */
    float crossfeed;          /* 0..1, 0 disables */
    float crossfeed_cutoff;   /* Hz */
    float reverb_mix;         /* 0..1, 0 disables */
    float reverb_size;        /* 0..1 */
    float reverb_damping;     /* 0..1 */
    float reverb_predelay_ms; /* 0..200 */
    float reverb_width;       /* 0..1 */

    /* Output stage. */
    float volume;             /* linear software gain; > 1 boosts */
    float balance;            /* -1 (left) .. 1 (right) */
    uint32_t limiter_enabled;
    float limiter_ceiling;    /* linear peak ceiling */
    float limiter_release_ms;

    /* Sources: one gain per process tap, in aggregate tap order. */
    uint32_t tap_count;
    float tap_gain[OT_MAX_TAPS];

    /* Routing: flattened output channel indices for left/right. */
    uint32_t out_left;
    uint32_t out_right;

    uint32_t analyzer_enabled;
    uint32_t detector_enabled; /* pre-EQ feed for music type detection */
} ot_params;

/* Fills a neutral (pass-through) configuration with a single unity tap. */
void ot_params_init(ot_params *p, float sample_rate);
void ot_params_set_band(ot_params *p, uint32_t index, ot_biquad_coeffs c);
void ot_params_set_tap_gain(ot_params *p, uint32_t index, float gain);

#endif
