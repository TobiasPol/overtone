/* Audio Unit chain rendering on the IO thread. */
#include <stdlib.h>
#include <string.h>
#include "dsp_internal.h"

ot_plugin_chain *ot_plugin_chain_create(void) {
    return calloc(1, sizeof(ot_plugin_chain));
}

void ot_plugin_chain_free(ot_plugin_chain *chain) {
    free(chain);
}

bool ot_plugin_chain_append(ot_plugin_chain *chain, AudioUnit unit, bool bypassed) {
    if (chain == NULL || chain->count >= OT_MAX_PLUGINS) return false;
    chain->units[chain->count] = unit;
    chain->bypassed[chain->count] = bypassed ? 1 : 0;
    chain->count++;
    return true;
}

static OSStatus plugin_input_render(void *ref, AudioUnitRenderActionFlags *flags,
                                    const AudioTimeStamp *ts, UInt32 bus, UInt32 frames,
                                    AudioBufferList *io) {
    (void)flags; (void)ts; (void)bus;
    const ot_plugin_input *in = ref;
    if (io == NULL || in == NULL) return kAudioUnitErr_InvalidParameter;
    uint32_t avail = in->frames;
    uint32_t copy_frames = frames < avail ? frames : avail;
    UInt32 req_bytes = frames * (UInt32)sizeof(float);
    UInt32 copy_bytes = copy_frames * (UInt32)sizeof(float);
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        const float *src = (b == 0) ? in->left : (b == 1 ? in->right : NULL);
        AudioBuffer *buf = &io->mBuffers[b];
        if (buf->mData == NULL) {
            if (src == NULL) return kAudioUnitErr_InvalidParameter;
            if (frames > avail) return kAudioUnitErr_TooManyFramesToProcess;
            buf->mData = (void *)src;
            buf->mDataByteSize = copy_bytes;
        } else {
            UInt32 out_bytes = req_bytes < buf->mDataByteSize ? req_bytes : buf->mDataByteSize;
            UInt32 to_copy = src != NULL ? (copy_bytes < out_bytes ? copy_bytes : out_bytes) : 0;
            if (to_copy > 0) memcpy(buf->mData, src, to_copy);
            if (out_bytes > to_copy) memset((uint8_t *)buf->mData + to_copy, 0, out_bytes - to_copy);
            buf->mDataByteSize = out_bytes;
        }
    }
    return noErr;
}

AURenderCallbackStruct ot_dsp_plugin_input_callback(ot_dsp *dsp) {
    AURenderCallbackStruct cb = { plugin_input_render, &dsp->plugin_input };
    return cb;
}

ot_plugin_chain *ot_dsp_swap_plugin_chain(ot_dsp *dsp, ot_plugin_chain *chain) {
    return atomic_exchange(&dsp->chain, chain);
}

bool ot_dsp_plugin_chain_in_use(ot_dsp *dsp, const ot_plugin_chain *chain) {
    if (chain == NULL) return false;
    return atomic_load(&dsp->chain) == chain || atomic_load(&dsp->chain_in_use) == chain;
}

/* Hazard-pointer acquire: announce the chain, then confirm it is still current. */
static ot_plugin_chain *acquire_chain(ot_dsp *dsp) {
    ot_plugin_chain *c;
    do {
        c = atomic_load(&dsp->chain);
        atomic_store(&dsp->chain_in_use, c);
    } while (c != atomic_load(&dsp->chain));
    return c;
}

static void copy_output(float *dst, const AudioBuffer *buf, UInt32 bytes) {
    UInt32 copy = buf->mDataByteSize < bytes ? buf->mDataByteSize : bytes;
    if (buf->mData != dst && copy > 0) memmove(dst, buf->mData, copy);
    if (copy < bytes) memset((uint8_t *)dst + copy, 0, bytes - copy);
}

static void render_unit(ot_dsp *dsp, AudioUnit unit, float *l, float *r, uint32_t n) {
    UInt32 bytes = n * (UInt32)sizeof(float);
    memcpy(dsp->scratch_l, l, bytes);
    memcpy(dsp->scratch_r, r, bytes);
    memcpy(dsp->plugin_in_l, l, bytes);
    memcpy(dsp->plugin_in_r, r, bytes);
    dsp->plugin_input = (ot_plugin_input){ dsp->plugin_in_l, dsp->plugin_in_r, n };

    union {
        AudioBufferList list;
        uint8_t raw[offsetof(AudioBufferList, mBuffers) + 2 * sizeof(AudioBuffer)];
    } abl;
    abl.list.mNumberBuffers = 2;
    AudioBuffer *bufs = abl.list.mBuffers;
    bufs[0] = (AudioBuffer){ 1, bytes, l };
    bufs[1] = (AudioBuffer){ 1, bytes, r };

    AudioTimeStamp ts;
    memset(&ts, 0, sizeof(ts));
    ts.mSampleTime = dsp->plugin_sample_time;
    ts.mFlags = kAudioTimeStampSampleTimeValid;
    AudioUnitRenderActionFlags flags = 0;
    if (AudioUnitRender(unit, &flags, &ts, 0, n, &abl.list) != noErr) {
        memcpy(l, dsp->scratch_l, bytes); /* a failing plugin is skipped, not silenced */
        memcpy(r, dsp->scratch_r, bytes);
        return;
    }
    if ((flags & kAudioUnitRenderAction_OutputIsSilence) != 0) {
        memset(l, 0, bytes);
        memset(r, 0, bytes);
        return;
    }
    if (bufs[0].mData == NULL || bufs[1].mData == NULL) {
        memcpy(l, dsp->scratch_l, bytes);
        memcpy(r, dsp->scratch_r, bytes);
        return;
    }
    /* Units may hand back their own buffers instead of filling ours. */
    copy_output(l, &bufs[0], bytes);
    copy_output(r, &bufs[1], bytes);
}

void ot_plugins_process(ot_dsp *dsp, float *l, float *r, uint32_t n) {
    ot_plugin_chain *chain = acquire_chain(dsp);
    if (chain != NULL) {
        uint32_t count = chain->count > OT_MAX_PLUGINS ? OT_MAX_PLUGINS : chain->count;
        for (uint32_t i = 0; i < count; i++) {
            if (!chain->bypassed[i] && chain->units[i] != NULL) {
                render_unit(dsp, chain->units[i], l, r, n);
            }
        }
    }
    atomic_store(&dsp->chain_in_use, NULL);
    dsp->plugin_sample_time += n;
}
