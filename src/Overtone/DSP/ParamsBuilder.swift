import Foundation
import OvertoneDSP

/// Everything that shapes the sound, as a value type the builder can be tested with.
struct DSPSettings {
    var equalizer = EqualizerSettings()
    var correction = HeadphoneCorrection()
    var spatial = SpatialSettings()
    var output = OutputSettings()
    /// Linear gain per tap key; missing keys play at unity.
    var tapGains: [String: Double] = [:]
    var analyzerEnabled = false
}

/// Translates user settings into the flat C parameter snapshot.
enum ParamsBuilder {
    static func make(_ s: DSPSettings, context: EngineContext) -> ot_params {
        var p = ot_params()
        ot_params_init(&p, Float(context.sampleRate))
        let slots = sections(s, sampleRate: context.sampleRate)
        p.band_count = UInt32(slots.count)
        for (index, coefficients) in slots.enumerated() {
            ot_params_set_band(&p, UInt32(index), coefficients)
        }
        p.preamp = Float(Decibels.toLinear(preampDB(s, bands: activeBands(s))))
        applySpatial(s.spatial, to: &p)
        applyOutput(s.output, context: context, to: &p)
        applyTaps(s.tapGains, keys: context.tapKeys, to: &p)
        p.analyzer_enabled = s.analyzerEnabled ? 1 : 0
        return p
    }

    /// Fixed filter slots: every correction filter, then every band of the active EQ mode.
    /// Silent or disabled bands become identity sections (skipped by the DSP) instead of being
    /// removed, so the other bands keep their slot and filter state when one crosses 0 dB.
    static func sections(_ s: DSPSettings, sampleRate: Double) -> [ot_biquad_coeffs] {
        let correction = s.correction.filters.map { (band: $0, live: s.correction.isEnabled) }
        let equalizer = s.equalizer.activeBands.map { (band: $0, live: s.equalizer.isEnabled) }
        return (correction + equalizer).prefix(Int(OT_MAX_BANDS)).map { item in
            item.live && !item.band.isNeutral ? item.band.coefficients(sampleRate: sampleRate) : ot_biquad_identity()
        }
    }

    /// Bands that actually shape the sound (for curves, auto-gain and export).
    static func activeBands(_ s: DSPSettings) -> [EQBand] {
        var bands: [EQBand] = []
        if s.correction.isActive { bands += s.correction.filters }
        if s.equalizer.isEnabled { bands += s.equalizer.activeBands }
        return Array(bands.filter { !$0.isNeutral }.prefix(Int(OT_MAX_BANDS)))
    }

    static func preampDB(_ s: DSPSettings, bands: [EQBand]) -> Double {
        var db = 0.0
        if s.correction.isActive { db += s.correction.preamp }
        if s.equalizer.isEnabled { db += s.equalizer.preampDB }
        if s.equalizer.isEnabled && s.equalizer.autoGain {
            let peak = ResponseCurve.peakGain(bands: bands) + db
            if peak > 0 { db -= peak }
        }
        return db
    }

    private static func applySpatial(_ spatial: SpatialSettings, to p: inout ot_params) {
        p.width = Float(spatial.width.clamped(to: 0...2))
        if spatial.crossfeedEnabled {
            p.crossfeed = Float(spatial.crossfeed.clamped(to: 0...1))
            p.crossfeed_cutoff = Float(spatial.crossfeedCutoff.clamped(to: 300...2_000))
        }
        if spatial.roomEnabled {
            p.reverb_mix = Float(spatial.mix.clamped(to: 0...1))
            p.reverb_size = Float(spatial.roomSize.clamped(to: 0...1))
            p.reverb_damping = Float(spatial.damping.clamped(to: 0...1))
            p.reverb_predelay_ms = Float(spatial.predelayMs.clamped(to: 0...200))
            p.reverb_width = Float(spatial.roomWidth.clamped(to: 0...1))
        }
    }

    private static func applyOutput(_ output: OutputSettings, context: EngineContext, to p: inout ot_params) {
        p.volume = output.isMuted ? 0 : Float(output.volume.clamped(to: 0...output.maxBoost))
        p.balance = Float(output.balance.clamped(to: -1...1))
        p.limiter_enabled = output.limiterEnabled ? 1 : 0
        p.limiter_ceiling = Float(Decibels.toLinear(output.limiterCeilingDB.clamped(to: -12...0)))
        p.out_left = UInt32(max(0, context.outputLeft))
        p.out_right = UInt32(max(0, context.outputRight))
    }

    private static func applyTaps(_ gains: [String: Double], keys: [String], to p: inout ot_params) {
        let count = min(keys.count, Int(OT_MAX_TAPS))
        p.tap_count = UInt32(max(count, 1))
        for (index, key) in keys.prefix(count).enumerated() {
            ot_params_set_tap_gain(&p, UInt32(index), Float(gains[key] ?? 1))
        }
    }
}
