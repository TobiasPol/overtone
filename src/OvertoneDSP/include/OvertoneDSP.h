/*
 * OvertoneDSP — real-time audio processing core for Overtone.
 *
 * Everything reachable from ot_io_proc() is lock-free and allocation-free so it
 * can run on the Core Audio HAL IO thread. Configuration happens on the main
 * thread and is handed over through a wait-free triple buffer (parameters) or a
 * hazard-pointer swap (Audio Unit chain).
 */
#ifndef OVERTONE_DSP_H
#define OVERTONE_DSP_H

#include "ot_params.h"
#include "ot_biquad.h"
#include "ot_dsp.h"
#include "ot_plugins.h"

#endif
