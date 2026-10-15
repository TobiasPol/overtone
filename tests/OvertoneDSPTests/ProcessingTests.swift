import Foundation
import OvertoneDSP
import Testing

/// Renders a stereo sine through a fresh DSP instance configured by `configure`.
private func render(
    frequency: Double = 1_000, amplitude: Float = 0.25, frames: Int = 48_000,
    configure: (inout ot_params) -> Void = { _ in }
) -> (left: [Float], right: [Float]) {
    let dsp = ot_dsp_create()!
    defer { ot_dsp_destroy(dsp) }
    ot_dsp_prepare(dsp, 48_000)
    var params = ot_params()
    ot_params_init(&params, 48_000)
    configure(&params)
    ot_dsp_publish(dsp, &params)
    var left = (0..<frames).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / 48_000)) }
    var right = left
    ot_dsp_process(dsp, &left, &right, UInt32(frames))
    return (left, right)
}

private func peak(_ x: ArraySlice<Float>) -> Float { x.map(abs).max() ?? 0 }

@Suite("DSP processing")
struct ProcessingTests {
    @Test func neutralParametersArePassThrough() {
        let input = (0..<4_800).map { 0.25 * Float(sin(2 * .pi * 440 * Double($0) / 48_000)) }
        let out = render(frequency: 440, frames: 4_800)
        for i in stride(from: 0, to: 4_800, by: 97) {
            #expect(abs(out.left[i] - input[i]) < 1e-6)
        }
    }

    @Test func peakingBandBoostsMatchingSine() {
        let out = render { p in
            p.band_count = 1
            ot_params_set_band(&p, 0, ot_biquad_design(OT_FILTER_PEAK, 48_000, 1_000, 6.0206, 1))
        }
        #expect(abs(peak(out.left[24_000...]) - 0.5) < 0.01)
    }

    @Test func limiterHoldsCeiling() {
        let out = render(amplitude: 0.9) { p in
            p.volume = 4
            p.limiter_enabled = 1
            p.limiter_ceiling = 0.5
        }
        #expect(peak(out.left[...]) <= 0.5 + 1e-6)
        #expect(peak(out.right[24_000...]) > 0.45)
    }

    @Test func volumeAndBalance() {
        let out = render { p in
            p.volume = 0.5
            p.balance = 1
        }
        #expect(abs(peak(out.right[1_000...]) - 0.125) < 0.002)
        #expect(peak(out.left[1_000...]) < 1e-4)
    }

    @Test func zeroWidthCollapsesToMono() {
        let dsp = ot_dsp_create()!
        defer { ot_dsp_destroy(dsp) }
        var p = ot_params()
        ot_params_init(&p, 48_000)
        p.width = 0
        ot_dsp_publish(dsp, &p)
        var l = [Float](repeating: 0.5, count: 9_600)
        var r = [Float](repeating: -0.1, count: 9_600)
        ot_dsp_process(dsp, &l, &r, 9_600)
        #expect(abs(l[9_000] - r[9_000]) < 1e-4)
    }

    @Test func reverbAndCrossfeedStayBounded() {
        let out = render(amplitude: 0.8) { p in
            p.reverb_mix = 1
            p.reverb_size = 1
            p.crossfeed = 1
            p.width = 2
        }
        #expect(out.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(peak(out.left[24_000...]) > 0.1)
    }

    @Test func analyzerReceivesProcessedAudio() {
        let dsp = ot_dsp_create()!
        defer { ot_dsp_destroy(dsp) }
        var p = ot_params()
        ot_params_init(&p, 48_000)
        p.analyzer_enabled = 1
        ot_dsp_publish(dsp, &p)
        var l = [Float](repeating: 0.3, count: 4_096)
        var r = l
        ot_dsp_process(dsp, &l, &r, 4_096)
        var snapshot = [Float](repeating: 0, count: 2_048)
        #expect(ot_dsp_read_analyzer(dsp, &snapshot, 2_048) == 2_048)
        #expect(abs(snapshot[2_000] - 0.3) < 1e-6)
    }

    @Test func pluginChainSwapIsTracked() {
        let dsp = ot_dsp_create()!
        defer { ot_dsp_destroy(dsp) }
        let chain = UnsafeMutablePointer<ot_plugin_chain>.allocate(capacity: 1)
        defer { chain.deallocate() }
        chain.initialize(to: ot_plugin_chain())
        #expect(ot_dsp_swap_plugin_chain(dsp, chain) == nil)
        #expect(ot_dsp_plugin_chain_in_use(dsp, chain))
        #expect(ot_dsp_swap_plugin_chain(dsp, nil) == chain)
        #expect(!ot_dsp_plugin_chain_in_use(dsp, chain))
    }
}

@Suite("EQ slot continuity")
struct EQSlotContinuityTests {
    private func params(mid: ot_biquad_coeffs) -> ot_params {
        var p = ot_params()
        ot_params_init(&p, 48_000)
        p.band_count = 3
        ot_params_set_band(&p, 0, ot_biquad_design(OT_FILTER_LOW_SHELF, 48_000, 120, 6, 0.7))
        ot_params_set_band(&p, 1, mid)
        ot_params_set_band(&p, 2, ot_biquad_design(OT_FILTER_HIGH_SHELF, 48_000, 6_000, 6, 0.7))
        return p
    }

    /// Activating a bypassed middle band must not disturb the bands around it (no click).
    @Test func activatingBypassedBandIsSmooth() {
        let dsp = ot_dsp_create()!
        defer { ot_dsp_destroy(dsp) }
        var signal = (0..<19_200).map { 0.3 * Float(sin(2 * .pi * 100 * Double($0) / 48_000)) }
        var right = signal
        var a = params(mid: ot_biquad_identity())
        var b = params(mid: ot_biquad_design(OT_FILTER_PEAK, 48_000, 1_000, 1, 0.7))
        ot_dsp_publish(dsp, &a)
        for start in stride(from: 0, to: signal.count, by: 512) {
            if start == 9_728 { ot_dsp_publish(dsp, &b) }
            let n = min(512, signal.count - start)
            signal.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    ot_dsp_process(dsp, l.baseAddress! + start, r.baseAddress! + start, UInt32(n))
                }
            }
        }
        let steps = zip(signal.dropFirst(), signal).map { abs($0 - $1) }
        let steady = steps[4_800..<9_600].max()!
        let around = steps[9_600..<10_400].max()!
        #expect(around < steady * 1.2)
    }
}
