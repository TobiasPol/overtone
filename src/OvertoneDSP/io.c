/*
 * HAL IO proc for the private aggregate device. Input buffers carry the
 * process taps (global tap first, then per-app taps); output buffers belong
 * to the real output device that the aggregate wraps.
 */
#include <string.h>
#include "dsp_internal.h"
#if defined(__x86_64__)
#include <xmmintrin.h>
#endif

static inline void enable_flush_to_zero(void) {
#if defined(__aarch64__)
    uint64_t fpcr;
    __asm__ __volatile__("mrs %0, fpcr" : "=r"(fpcr));
    __asm__ __volatile__("msr fpcr, %0" : : "r"(fpcr | (1ULL << 24)));
#elif defined(__x86_64__)
    _mm_setcsr(_mm_getcsr() | 0x8040);
#endif
}

static uint32_t buffer_frames(const AudioBuffer *b) {
    uint32_t ch = b->mNumberChannels ? b->mNumberChannels : 1;
    return b->mDataByteSize / (uint32_t)(sizeof(float) * ch);
}

static uint32_t output_frames(const AudioBufferList *out) {
    if (out == NULL || out->mNumberBuffers == 0) return 0;
    return buffer_frames(&out->mBuffers[0]);
}

static void mix_tap(float *gain, float target, float coef, const AudioBuffer *b,
                    uint32_t offset, uint32_t n, float *l, float *r) {
    uint32_t ch = b->mNumberChannels;
    uint32_t avail = buffer_frames(b);
    if (b->mData == NULL || ch == 0 || offset >= avail) return;
    uint32_t count = avail - offset < n ? avail - offset : n;
    const float *src = (const float *)b->mData + (size_t)offset * ch;
    float g = *gain;
    for (uint32_t i = 0; i < count; i++) {
        g += (target - g) * coef;
        float sl = src[i * ch];
        float sr = ch > 1 ? src[i * ch + 1] : sl;
        l[i] += g * sl;
        r[i] += g * sr;
    }
    *gain = g;
}

/* Taps are always the trailing input streams of the aggregate device. */
static void mix_inputs(ot_dsp *d, const ot_params *p, const AudioBufferList *in,
                       uint32_t offset, uint32_t n) {
    memset(d->left, 0, n * sizeof(float));
    memset(d->right, 0, n * sizeof(float));
    if (in == NULL) return;
    uint32_t taps = p->tap_count < in->mNumberBuffers ? p->tap_count : in->mNumberBuffers;
    uint32_t first = in->mNumberBuffers - taps;
    for (uint32_t t = 0; t < taps && t < OT_MAX_TAPS; t++) {
        mix_tap(&d->smooth.tap[t], p->tap_gain[t], d->smooth.coef, &in->mBuffers[first + t],
                offset, n, d->left, d->right);
    }
}

static void write_channel(float *dst, uint32_t stride, const float *src, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        dst[i * stride] = src ? src[i] : 0.0f;
    }
}

static void write_outputs(ot_dsp *d, const ot_params *p, AudioBufferList *out,
                          uint32_t offset, uint32_t n) {
    const float *mono = NULL;
    if (p->out_left == p->out_right) { /* mono device: fold down */
        for (uint32_t i = 0; i < n; i++) d->scratch_l[i] = 0.5f * (d->left[i] + d->right[i]);
        mono = d->scratch_l;
    }
    uint32_t base = 0;
    for (uint32_t b = 0; b < out->mNumberBuffers; b++) {
        AudioBuffer *buf = &out->mBuffers[b];
        uint32_t ch = buf->mNumberChannels;
        if (buf->mData != NULL && offset < buffer_frames(buf)) {
            float *dst = (float *)buf->mData + (size_t)offset * ch;
            for (uint32_t c = 0; c < ch; c++) {
                uint32_t flat = base + c;
                const float *src = mono && flat == p->out_left ? mono
                                 : flat == p->out_left ? d->left
                                 : flat == p->out_right ? d->right : NULL;
                write_channel(dst + c, ch, src, n);
            }
        }
        base += ch;
    }
}

static OSStatus io_proc(AudioObjectID device, const AudioTimeStamp *now,
                        const AudioBufferList *input, const AudioTimeStamp *input_time,
                        AudioBufferList *output, const AudioTimeStamp *output_time,
                        void *client) {
    (void)device; (void)now; (void)input_time; (void)output_time;
    ot_dsp *d = client;
    if (d == NULL || output == NULL) return noErr;
    enable_flush_to_zero();
    const ot_params *p = ot_box_acquire(&d->box);
    if (!d->smooth.primed) {
        for (uint32_t i = 0; i < OT_MAX_TAPS; i++) d->smooth.tap[i] = p->tap_gain[i];
    }
    uint32_t frames = output_frames(output);
    uint32_t done = 0;
    while (done < frames) {
        uint32_t n = frames - done > OT_MAX_CHUNK ? OT_MAX_CHUNK : frames - done;
        mix_inputs(d, p, input, done, n);
        ot_dsp_run_chain(d, p, d->left, d->right, n);
        write_outputs(d, p, output, done, n);
        done += n;
    }
    atomic_fetch_add_explicit(&d->cycles, 1, memory_order_relaxed);
    return noErr;
}

AudioDeviceIOProc ot_io_proc_ptr(void) {
    return io_proc;
}
