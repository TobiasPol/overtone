import OvertoneDSP
import Testing

@Suite("Biquad design")
struct BiquadTests {
    let fs = 48_000.0

    @Test func peakFilterHitsTargetGainAtCentre() {
        let c = ot_biquad_design(OT_FILTER_PEAK, fs, 1_000, 6, 1.41)
        #expect(abs(ot_biquad_magnitude_db(c, 1_000, fs) - 6) < 0.01)
        #expect(abs(ot_biquad_magnitude_db(c, 20, fs)) < 0.1)
        #expect(abs(ot_biquad_magnitude_db(c, 20_000, fs)) < 0.2)
    }

    @Test func lowShelfBoostsBassOnly() {
        let c = ot_biquad_design(OT_FILTER_LOW_SHELF, fs, 100, 9, 0.7)
        #expect(abs(ot_biquad_magnitude_db(c, 10, fs) - 9) < 0.2)
        #expect(abs(ot_biquad_magnitude_db(c, 10_000, fs)) < 0.1)
    }

    @Test func highShelfCutsTrebleOnly() {
        let c = ot_biquad_design(OT_FILTER_HIGH_SHELF, fs, 8_000, -6, 0.7)
        #expect(abs(ot_biquad_magnitude_db(c, 20_000, fs) + 6) < 0.5)
        #expect(abs(ot_biquad_magnitude_db(c, 100, fs)) < 0.1)
    }

    @Test func passFiltersAttenuateStopBand() {
        let lp = ot_biquad_design(OT_FILTER_LOW_PASS, fs, 1_000, 0, 0.707)
        let hp = ot_biquad_design(OT_FILTER_HIGH_PASS, fs, 1_000, 0, 0.707)
        #expect(ot_biquad_magnitude_db(lp, 10_000, fs) < -30)
        #expect(ot_biquad_magnitude_db(hp, 100, fs) < -30)
        #expect(abs(ot_biquad_magnitude_db(lp, 1_000, fs) + 3.01) < 0.05)
    }

    @Test func notchRemovesCentreFrequency() {
        // Float32 coefficients limit null depth, so test well above the bass region.
        let c = ot_biquad_design(OT_FILTER_NOTCH, fs, 1_000, 0, 10)
        #expect(ot_biquad_magnitude_db(c, 1_000, fs) < -40)
        #expect(abs(ot_biquad_magnitude_db(c, 10_000, fs)) < 0.1)
    }

    @Test func allPassIsFlat() {
        let c = ot_biquad_design(OT_FILTER_ALL_PASS, fs, 2_000, 0, 1)
        for f in [30.0, 300, 3_000, 15_000] {
            #expect(abs(ot_biquad_magnitude_db(c, f, fs)) < 0.01)
        }
    }

    @Test func invalidInputsAreClampedNotNaN() {
        let c = ot_biquad_design(OT_FILTER_PEAK, fs, 90_000, 200, 0)
        #expect(ot_biquad_magnitude_db(c, 1_000, fs).isFinite)
        let id = ot_biquad_design(OT_FILTER_PEAK, 0, 1_000, 6, 1)
        #expect(id.b0 == 1 && id.a1 == 0)
    }
}
