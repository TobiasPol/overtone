import Foundation
import OvertoneDSP

/// One parametric filter section.
struct EQBand: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var type: FilterType = .peak
    var frequency: Double = 1_000
    var gain: Double = 0
    var q: Double = 1
    var isEnabled = true

    static let frequencyRange = 20.0...20_000.0
    static let gainRange = -24.0...24.0
    static let qRange = 0.1...20.0

    /// True when the section has no audible effect and can be skipped.
    var isNeutral: Bool {
        !isEnabled || (type.usesGain && abs(gain) < 0.001)
    }

    func coefficients(sampleRate: Double) -> ot_biquad_coeffs {
        ot_biquad_design(type.cValue, sampleRate, frequency, gain, q)
    }

    func clamped() -> EQBand {
        var copy = self
        copy.frequency = frequency.clamped(to: Self.frequencyRange)
        copy.gain = gain.clamped(to: Self.gainRange)
        copy.q = q.clamped(to: Self.qRange)
        return copy
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum Decibels {
    static func toLinear(_ db: Double) -> Double { pow(10, db / 20) }
    static func fromLinear(_ value: Double) -> Double { 20 * log10(max(value, 1e-9)) }
}
