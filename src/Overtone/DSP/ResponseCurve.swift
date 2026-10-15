import Foundation
import OvertoneDSP

/// Frequency response math for drawing curves and for clipping protection.
enum ResponseCurve {
    static let displaySampleRate = 48_000.0

    /// Logarithmically spaced frequencies between `low` and `high`.
    static func frequencies(count: Int, low: Double = 20, high: Double = 20_000) -> [Double] {
        guard count > 1 else { return [low] }
        let a = log10(low), b = log10(high)
        return (0..<count).map { pow(10, a + (b - a) * Double($0) / Double(count - 1)) }
    }

    /// Total response in dB (including preamp) at each frequency.
    static func magnitudes(
        bands: [EQBand], preampDB: Double = 0, frequencies: [Double],
        sampleRate: Double = displaySampleRate
    ) -> [Double] {
        let coefficients = bands.filter { !$0.isNeutral }.map { $0.coefficients(sampleRate: sampleRate) }
        return frequencies.map { f in
            coefficients.reduce(preampDB) { $0 + ot_biquad_magnitude_db($1, f, sampleRate) }
        }
    }

    /// Response of a single band, for drawing its individual contribution.
    static func magnitudes(of band: EQBand, frequencies: [Double], sampleRate: Double = displaySampleRate) -> [Double] {
        let c = band.coefficients(sampleRate: sampleRate)
        return frequencies.map { ot_biquad_magnitude_db(c, $0, sampleRate) }
    }

    /// Highest gain of the filter cascade across the audible range.
    static func peakGain(bands: [EQBand], sampleRate: Double = displaySampleRate) -> Double {
        guard bands.contains(where: { !$0.isNeutral }) else { return 0 }
        return magnitudes(bands: bands, frequencies: frequencies(count: 256), sampleRate: sampleRate).max() ?? 0
    }
}
