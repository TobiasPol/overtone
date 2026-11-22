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
    @ObservationIgnored private var runSpectrum = false
    @ObservationIgnored private var lastCycleCount: UInt64 = 0
    @ObservationIgnored private var staleTicks = 0

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

    deinit {
        timer?.invalidate()
        vDSP_destroy_fftsetup(setup)
    }

    /// Screenshot support (`--snapshot`): displays a fixed spectrum and meter level.
    func showSnapshotLevels(_ demo: [Float], meter: Float) {
        levels = demo
        meters = (meter, meter * 0.94)
    }

    func setRunning(meters: Bool, spectrum: Bool) {
        runSpectrum = spectrum
        if !spectrum {
            levels = [Float](repeating: 0, count: Self.barCount)
            staleTicks = 0
        }
        guard meters else {
            timer?.invalidate()
            timer = nil
            levels = [Float](repeating: 0, count: Self.barCount)
            self.meters = (0, 0)
            staleTicks = 0
            return
        }
        guard timer == nil else { return }
        lastCycleCount = dsp.cycleCount
        staleTicks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.tick()
            }
        }
    }

    private func tick() {
        if runSpectrum {
            let cycles = dsp.cycleCount
            if cycles != lastCycleCount {
                lastCycleCount = cycles
                staleTicks = 0
                updateSpectrum()
            } else {
                staleTicks += 1
                if staleTicks >= 3 {
                    levels = levels.map {
                        let decayed = $0 * 0.86
                        return decayed < 0.002 ? 0 : decayed
                    }
                }
            }
        }
        let peaks = dsp.readPeaks()
        meters = (meterLevel(peaks.left, previous: meters.left), meterLevel(peaks.right, previous: meters.right))
    }

    private func updateSpectrum() {
        guard !bands.isEmpty, sampleRate > 0 else { return }
        _ = dsp.readAnalyzer(into: &samples)
        computePower()
        let binHz = Float(sampleRate) / Float(size)
        var next = levels
        for (index, band) in bands.enumerated() {
            let peak = band.isEmpty ? Float(0) : band.reduce(Float(0)) { max($0, power[$1]) }
            let centre = Float(band.lowerBound + band.upperBound) * 0.5 * binHz
            // +3 dB/octave tilt around 1 kHz so typical music reads as roughly flat.
            let db = 10 * log10(max(peak, 1e-12)) + 3 * log2(max(centre, 20) / 1_000)
            let target = max(0, min(1, (db - Self.floorDB) / -Self.floorDB))
            next[index] = target > next[index] ? target : next[index] * 0.86 + target * 0.14
        }
        levels = next
    }

    private func meterLevel(_ peak: Float, previous: Float) -> Float {
        let level = max(0, min(1, (20 * log10(max(peak, 1e-6)) + 60) / 60))
        return level > previous ? level : previous * 0.9
    }

    /// Hann-windowed real FFT; power[k] is the squared amplitude of bin k.
    private func computePower() {
        let n = size
        samples.withUnsafeMutableBufferPointer { sp in
            vDSP_vmul(sp.baseAddress!, 1, window, 1, sp.baseAddress!, 1, vDSP_Length(n))
        }
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
        power.withUnsafeMutableBufferPointer { pp in
            vDSP_vsmul(pp.baseAddress!, 1, &scale, pp.baseAddress!, 1, vDSP_Length(n / 2))
        }
    }

    private func buildBands() {
        guard sampleRate > 0 else {
            bands = []
            return
        }
        let maxBin = size / 2
        let binHz = sampleRate / Double(size)
        let edges = ResponseCurve.frequencies(count: Self.barCount + 1)
        bands = (0..<Self.barCount).map { i in
            let lo = min(maxBin, max(1, Int(edges[i] / binHz)))
            if lo >= maxBin { return maxBin..<maxBin }
            let hi = min(maxBin, max(lo + 1, Int(edges[i + 1] / binHz)))
            return lo..<hi
        }
    }
}
