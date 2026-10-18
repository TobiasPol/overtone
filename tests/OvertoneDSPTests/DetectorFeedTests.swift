import OvertoneDSP
import Testing

@Suite("Detector feed")
struct DetectorFeedTests {
    private func process(_ dsp: OpaquePointer, ramp range: Range<Int>, configure: (inout ot_params) -> Void) {
        var params = ot_params()
        ot_params_init(&params, 48_000)
        configure(&params)
        ot_dsp_publish(dsp, &params)
        var left = range.map { Float($0) / 100_000 }
        var right = left
        ot_dsp_process(dsp, &left, &right, UInt32(left.count))
    }

    @Test func feedIsTakenBeforePreampAndEQ() {
        let dsp = ot_dsp_create()!
        defer { ot_dsp_destroy(dsp) }
        ot_dsp_prepare(dsp, 48_000)
        process(dsp, ramp: 0..<2_000) { p in
            p.detector_enabled = 1
            p.preamp = 0.25
            p.band_count = 1
            ot_params_set_band(&p, 0, ot_biquad_design(OT_FILTER_PEAK, 48_000, 1_000, 12, 1))
        }
        var out = [Float](repeating: 0, count: 4_096)
        let count = Int(ot_dsp_drain_detector(dsp, &out, UInt32(out.count)))
        #expect(count == 2_000)
        for i in stride(from: 0, to: count, by: 37) {
            #expect(abs(out[i] - Float(i) / 100_000) < 1e-7)
        }
    }

    @Test func drainReturnsEachSampleOnce() {
        let dsp = ot_dsp_create()!
        defer { ot_dsp_destroy(dsp) }
        ot_dsp_prepare(dsp, 48_000)
        var out = [Float](repeating: 0, count: 1_500)
        process(dsp, ramp: 0..<1_000) { $0.detector_enabled = 1 }
        #expect(ot_dsp_drain_detector(dsp, &out, 600) == 600)
        #expect(ot_dsp_drain_detector(dsp, &out, 1_500) == 400)
        #expect(abs(out[0] - 600 / 100_000) < 1e-7)
        #expect(ot_dsp_drain_detector(dsp, &out, 1_500) == 0)
    }

    @Test func disabledFeedWritesNothingAndOverrunKeepsNewest() {
        let dsp = ot_dsp_create()!
        defer { ot_dsp_destroy(dsp) }
        ot_dsp_prepare(dsp, 48_000)
        var out = [Float](repeating: 0, count: Int(OT_ANALYZER_SIZE))
        process(dsp, ramp: 0..<1_000) { _ in }
        #expect(ot_dsp_drain_detector(dsp, &out, UInt32(out.count)) == 0)
        process(dsp, ramp: 0..<40_000) { $0.detector_enabled = 1 }
        let count = Int(ot_dsp_drain_detector(dsp, &out, UInt32(out.count)))
        #expect(count == Int(OT_ANALYZER_SIZE) / 2)
        #expect(abs(out[count - 1] - 39_999 / 100_000) < 1e-6)
    }
}
