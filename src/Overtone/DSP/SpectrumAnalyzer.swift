import Accelerate
import Foundation
import Observation

/// Turns the post-effects analyzer feed into log-spaced bars and output meters at 30 fps.
@MainActor @Observable
final class SpectrumAnalyzer {
    static let barCount = 72
    static let floorDB: Float = -84

    /// Bar heights normalised to 0…1, log-spaced from 20 Hz to 20 kHz.
    private(set) var levels = [Float](repeating: 0, count: SpectrumAnalyzer.barCount)
    /// Output peak meters, normalised to 0…1 over a 60 dB range.
    private(set) var meters: (left: Float, right: Float) = (0, 0)

    var sampleRate = 48_000.0 { didSet { if sampleRate != oldValue { buildBands() } } }

    @ObservationIgnored private let dsp: DSPCore
    @ObservationIgnored private let log2n: vDSP_Length = 12
    @ObservationIgnored private var size: Int { 1 << Int(log2n) }
    @ObservationIgnored private let setup: FFTSetup
    @ObservationIgnored private var samples: [Float]
    @ObservationIgnored private let window: [Float]
    @ObservationIgnored private var real: [Float]
    @ObservationIgnored private var imag: [Float]
    @ObservationIgnored private var power: [Float]
    @ObservationIgnored private var bands: [Range<Int>] = []
    @ObservationIgnored private var timer: Timer?

    init(dsp: DSPCore) {
        self.dsp = dsp
        let n = 1 << 12
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        samples = [Float](repeating: 0, count: n)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        power = [Float](repeating: 0, count: n / 2)
        buildBands()
    }

    func setRunning(_ running: Bool) {
        guard running != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard running else {
            levels = [Float](repeating: 0, count: Self.barCount)
            meters = (0, 0)
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        _ = dsp.readAnalyzer(into: &samples)
        computePower()
        let binHz = Float(sampleRate) / Float(size)
        var next = levels
        for (index, band) in bands.enumerated() {
            let peak = band.reduce(Float(0)) { max($0, power[$1]) }
            let centre = Float(band.lowerBound + band.upperBound) * 0.5 * binHz
            // +3 dB/octave tilt around 1 kHz so typical music reads as roughly flat.
            let db = 10 * log10(max(peak, 1e-12)) + 3 * log2(max(centre, 20) / 1_000)
            let target = max(0, min(1, (db - Self.floorDB) / -Self.floorDB))
            next[index] = target > next[index] ? target : next[index] * 0.86 + target * 0.14
        }
        levels = next
        let peaks = dsp.readPeaks()
        meters = (meterLevel(peaks.left, previous: meters.left), meterLevel(peaks.right, previous: meters.right))
    }

    private func meterLevel(_ peak: Float, previous: Float) -> Float {
        let level = max(0, min(1, (20 * log10(max(peak, 1e-6)) + 60) / 60))
        return level > previous ? level : previous * 0.9
    }

    /// Hann-windowed real FFT; power[k] is the squared amplitude of bin k.
    private func computePower() {
        let n = size
        vDSP.multiply(samples, window, result: &samples)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                samples.withUnsafeBufferPointer { sp in
                    sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }
        // zrip output is 2x the DFT; a Hann window halves amplitude: A = sqrt(p) * 2 / N.
        var scale = Float(4) / Float(n * n)
        vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(n / 2))
    }

    private func buildBands() {
        let binHz = sampleRate / Double(size)
        let edges = ResponseCurve.frequencies(count: Self.barCount + 1)
        bands = (0..<Self.barCount).map { i in
            let lo = max(1, Int(edges[i] / binHz))
            let hi = min(size / 2, max(lo + 1, Int(edges[i + 1] / binHz)))
            return lo..<hi
        }
    }
}
