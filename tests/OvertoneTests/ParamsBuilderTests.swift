import Foundation
@testable import Overtone
import OvertoneDSP
import Testing

@Suite("Parameter builder")
struct ParamsBuilderTests {
    private let context = EngineContext(
        sampleRate: 48_000,
        tapKeys: [ProcessTap.globalKey, "com.spotify.client"],
        outputLeft: 2,
        outputRight: 3
    )

    @Test func neutralSettingsArePassThrough() {
        let p = ParamsBuilder.make(DSPSettings(), context: context)
        let identity = ot_biquad_identity()
        #expect(p.band_count == 10) // one slot per Advanced band, all bypassed
        #expect(withUnsafeBytes(of: p.bands) { raw in
            raw.bindMemory(to: ot_biquad_coeffs.self).prefix(10).allSatisfy { $0.b0 == identity.b0 && $0.a1 == 0 && $0.b1 == 0 }
        })
        #expect(p.preamp == 1)
        #expect(p.volume == 1 && p.balance == 0 && p.width == 1)
        #expect(p.reverb_mix == 0 && p.crossfeed == 0)
        #expect(p.limiter_enabled == 1)
    }

    @Test func correctionComesBeforeUserEQAndFlatBandsAreSkipped() {
        var s = DSPSettings()
        s.correction = HeadphoneCorrection(
            isEnabled: true,
            profileName: "X",
            preamp: -3,
            filters: [EQBand(type: .lowShelf, frequency: 100, gain: 4, q: 0.7)]
        )
        s.equalizer.mode = .advanced
        s.equalizer.advanced.gains[3] = 2
        s.equalizer.advanced.preamp = -1
        let bands = ParamsBuilder.activeBands(s)
        #expect(bands.count == 2)
        #expect(bands[0].type == .lowShelf)
        #expect(bands[1].frequency == 250)
        let p = ParamsBuilder.make(s, context: context)
        #expect(p.band_count == 11) // 1 correction slot + 10 graphic slots
        #expect(abs(Double(p.preamp) - Decibels.toLinear(-4)) < 1e-6)
    }

    @Test func slotsStayFixedWhenABandCrossesZero() {
        var s = DSPSettings()
        s.equalizer.mode = .basic
        s.equalizer.basic = BasicEQ(bass: 6, mid: 0, treble: 6)
        let before = ParamsBuilder.sections(s, sampleRate: 48_000)
        s.equalizer.basic.mid = 1
        let after = ParamsBuilder.sections(s, sampleRate: 48_000)
        #expect(before.count == 3 && after.count == 3)
        #expect(before[2].b0 == after[2].b0 && before[2].a1 == after[2].a1) // treble keeps slot 2
        #expect(before[1].b0 == 1 && after[1].b0 != 1)
    }

    @Test func disabledEqualizerKeepsCorrection() {
        var s = DSPSettings()
        s.equalizer.isEnabled = false
        s.equalizer.advanced.gains = Array(repeating: 6, count: 10)
        s.correction = HeadphoneCorrection(filters: [EQBand(gain: 3)])
        #expect(ParamsBuilder.activeBands(s).count == 1)
    }

    @Test func autoGainPreventsPositiveResponse() {
        var s = DSPSettings()
        s.equalizer.mode = .basic
        s.equalizer.basic.bass = 9
        s.equalizer.autoGain = true
        let bands = ParamsBuilder.activeBands(s)
        let preamp = ParamsBuilder.preampDB(s, bands: bands)
        let peak = ResponseCurve.peakGain(bands: bands) + preamp
        #expect(preamp < -8)
        #expect(abs(peak) < 0.01)
    }

    @Test func tapGainsFollowTapOrderAndMute() {
        var s = DSPSettings()
        s.tapGains = VolumeMixer.tapGains(settings: MixerSettings(apps: [
            "com.spotify.client": AppVolume(volume: 0.5, isMuted: false),
        ]))
        s.output.isMuted = true
        let p = ParamsBuilder.make(s, context: context)
        #expect(p.tap_count == 2)
        #expect(p.tap_gain.0 == 1 && p.tap_gain.1 == 0.5)
        #expect(p.volume == 0)
        #expect(p.out_left == 2 && p.out_right == 3)
    }

    @Test func spatialOnlyAppliesWhenEnabled() {
        var s = DSPSettings()
        s.spatial.mix = 0.4
        #expect(ParamsBuilder.make(s, context: context).reverb_mix == 0)
        s.spatial.roomEnabled = true
        s.spatial.crossfeedEnabled = true
        let p = ParamsBuilder.make(s, context: context)
        #expect(abs(p.reverb_mix - 0.4) < 1e-6)
        #expect(p.crossfeed > 0)
    }

    @Test func volumeIsClampedToConfiguredBoost() {
        var s = DSPSettings()
        s.output.volume = 9
        s.output.maxBoost = 2
        #expect(ParamsBuilder.make(s, context: context).volume == 2)
    }
}
