#include <stdbool.h>
#include <math.h>
#include "ot_biquad.h"

typedef struct { double b0, b1, b2, a0, a1, a2; } raw_coeffs;

static double clampd(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static ot_biquad_coeffs normalise(raw_coeffs r) {
    ot_biquad_coeffs c;
    c.b0 = (float)(r.b0 / r.a0);
    c.b1 = (float)(r.b1 / r.a0);
    c.b2 = (float)(r.b2 / r.a0);
    c.a1 = (float)(r.a1 / r.a0);
    c.a2 = (float)(r.a2 / r.a0);
    return c;
}

ot_biquad_coeffs ot_biquad_identity(void) {
    ot_biquad_coeffs c = { 1.0f, 0.0f, 0.0f, 0.0f, 0.0f };
    return c;
}

static raw_coeffs shelf(bool high, double a, double cw, double alpha) {
    double sa = 2.0 * sqrt(a) * alpha;
    double s = high ? -1.0 : 1.0; /* high shelf mirrors the cosine terms */
    raw_coeffs r;
    r.b0 = a * ((a + 1) - s * (a - 1) * cw + sa);
    r.b1 = s * 2 * a * ((a - 1) - s * (a + 1) * cw);
    r.b2 = a * ((a + 1) - s * (a - 1) * cw - sa);
    r.a0 = (a + 1) + s * (a - 1) * cw + sa;
    r.a1 = -s * 2 * ((a - 1) + s * (a + 1) * cw);
    r.a2 = (a + 1) + s * (a - 1) * cw - sa;
    return r;
}

static raw_coeffs pass_filters(ot_filter_type type, double cw, double alpha) {
    raw_coeffs r = { 1, 0, 0, 1 + alpha, -2 * cw, 1 - alpha };
    switch (type) {
    case OT_FILTER_LOW_PASS:
        r.b0 = (1 - cw) / 2; r.b1 = 1 - cw; r.b2 = (1 - cw) / 2;
        break;
    case OT_FILTER_HIGH_PASS:
        r.b0 = (1 + cw) / 2; r.b1 = -(1 + cw); r.b2 = (1 + cw) / 2;
        break;
    case OT_FILTER_BAND_PASS:
        r.b0 = alpha; r.b1 = 0; r.b2 = -alpha;
        break;
    case OT_FILTER_NOTCH:
        r.b0 = 1; r.b1 = -2 * cw; r.b2 = 1;
        break;
    default: /* all-pass */
        r.b0 = 1 - alpha; r.b1 = -2 * cw; r.b2 = 1 + alpha;
        break;
    }
    return r;
}

ot_biquad_coeffs ot_biquad_design(ot_filter_type type, double sample_rate,
                                  double freq, double gain_db, double q) {
    if (sample_rate <= 0) {
        return ot_biquad_identity();
    }
    double f0 = clampd(freq, 1.0, sample_rate * 0.49);
    double qq = clampd(q, 0.025, 40.0);
    double a = pow(10.0, clampd(gain_db, -48.0, 48.0) / 40.0);
    double w0 = 2.0 * M_PI * f0 / sample_rate;
    double cw = cos(w0);
    double alpha = sin(w0) / (2.0 * qq);

    switch (type) {
    case OT_FILTER_PEAK: {
        raw_coeffs r = { 1 + alpha * a, -2 * cw, 1 - alpha * a,
                         1 + alpha / a, -2 * cw, 1 - alpha / a };
        return normalise(r);
    }
    case OT_FILTER_LOW_SHELF:
        return normalise(shelf(false, a, cw, alpha));
    case OT_FILTER_HIGH_SHELF:
        return normalise(shelf(true, a, cw, alpha));
    default:
        return normalise(pass_filters(type, cw, alpha));
    }
}

double ot_biquad_magnitude_db(ot_biquad_coeffs c, double freq, double sample_rate) {
    double w = 2.0 * M_PI * freq / sample_rate;
    double c1 = cos(w), c2 = cos(2 * w), s1 = sin(w), s2 = sin(2 * w);
    double nr = c.b0 + c.b1 * c1 + c.b2 * c2;
    double ni = -(c.b1 * s1 + c.b2 * s2);
    double dr = 1.0 + c.a1 * c1 + c.a2 * c2;
    double di = -(c.a1 * s1 + c.a2 * s2);
    double num = nr * nr + ni * ni;
    double den = dr * dr + di * di;
    if (den <= 0 || num <= 0) {
        return -120.0;
    }
    return 10.0 * log10(num / den);
}
