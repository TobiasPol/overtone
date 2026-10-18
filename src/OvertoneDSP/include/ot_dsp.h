#ifndef OT_DSP_H
#define OT_DSP_H

#include <stdint.h>
#include <stdbool.h>
#include <CoreAudio/CoreAudio.h>
#include "ot_params.h"

typedef struct ot_dsp ot_dsp;

ot_dsp *ot_dsp_create(void);
void ot_dsp_destroy(ot_dsp *dsp);

/* Resets all filter/effect state for a new sample rate. Call only while IO is stopped. */
void ot_dsp_prepare(ot_dsp *dsp, float sample_rate);

/* Main thread: publish a complete parameter snapshot (wait-free). */
void ot_dsp_publish(ot_dsp *dsp, const ot_params *params);

/* Processes deinterleaved stereo in place (used by tests and offline rendering). */
void ot_dsp_process(ot_dsp *dsp, float *left, float *right, uint32_t frames);

/* The HAL IO proc. Pass `dsp` as the client data. */
AudioDeviceIOProc ot_io_proc_ptr(void);

/* Copies the newest `count` analyzer samples (mono, post-effects) into `dst`. */
uint32_t ot_dsp_read_analyzer(ot_dsp *dsp, float *dst, uint32_t count);

/* Copies up to `max` detector samples (mono, before preamp/EQ) in order, each exactly once.
   Single consumer thread only. If nobody reads, the queue fills (0.34 s at 48 kHz) and newer
   samples are dropped; nothing is written while `detector_enabled` is off. */
uint32_t ot_dsp_drain_detector(ot_dsp *dsp, float *dst, uint32_t max);

/* Peak output levels since the previous call (linear), reset on read. */
void ot_dsp_read_peaks(ot_dsp *dsp, float *left, float *right);

/* Number of IO cycles processed; useful as a liveness indicator. */
uint64_t ot_dsp_cycle_count(ot_dsp *dsp);

#endif
