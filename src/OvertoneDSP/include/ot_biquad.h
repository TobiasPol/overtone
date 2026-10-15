#ifndef OT_BIQUAD_H
#define OT_BIQUAD_H

#include "ot_params.h"

typedef enum {
    OT_FILTER_PEAK = 0,
    OT_FILTER_LOW_SHELF = 1,
    OT_FILTER_HIGH_SHELF = 2,
    OT_FILTER_LOW_PASS = 3,
    OT_FILTER_HIGH_PASS = 4,
    OT_FILTER_BAND_PASS = 5,
    OT_FILTER_NOTCH = 6,
    OT_FILTER_ALL_PASS = 7,
} ot_filter_type;

/* RBJ "Audio EQ Cookbook" designs. Frequency and Q are clamped to safe ranges. */
ot_biquad_coeffs ot_biquad_design(ot_filter_type type, double sample_rate,
                                  double freq, double gain_db, double q);
ot_biquad_coeffs ot_biquad_identity(void);

/* Magnitude response of one section at `freq`, in dB. */
double ot_biquad_magnitude_db(ot_biquad_coeffs c, double freq, double sample_rate);

#endif
