#ifndef OT_PLUGINS_H
#define OT_PLUGINS_H

#include <stdbool.h>
#include <AudioToolbox/AudioToolbox.h>
#include "ot_params.h"
#include "ot_dsp.h"

/* An immutable list of Audio Units, rendered in order on the IO thread. */
typedef struct {
    uint32_t count;
    AudioUnit units[OT_MAX_PLUGINS];
    uint32_t bypassed[OT_MAX_PLUGINS];
} ot_plugin_chain;

ot_plugin_chain *ot_plugin_chain_create(void);
void ot_plugin_chain_free(ot_plugin_chain *chain);
/* Appends a unit; returns false when the chain is full. */
bool ot_plugin_chain_append(ot_plugin_chain *chain, AudioUnit unit, bool bypassed);

/*
 * Installs `chain` (may be NULL) and returns the previous chain. The previous
 * chain must not be freed, nor its units disposed, until
 * ot_dsp_plugin_chain_in_use() reports false for it.
 */
ot_plugin_chain *ot_dsp_swap_plugin_chain(ot_dsp *dsp, ot_plugin_chain *chain);
bool ot_dsp_plugin_chain_in_use(ot_dsp *dsp, const ot_plugin_chain *chain);

/* Render callback that feeds a hosted unit with the current chain input. */
AURenderCallbackStruct ot_dsp_plugin_input_callback(ot_dsp *dsp);

#endif
