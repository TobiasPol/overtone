import AVFoundation
import OvertoneDSP
import SoundAnalysis

/// Streams the pre-EQ detector feed into Apple's built-in sound classifier on a background
/// queue and reports label confidences per window, plus gaps of silence (likely track changes).
/// Event times are seconds of audio since `start`, so decisions don't depend on how fast audio arrives.
final class SoundClassifier: @unchecked Sendable {
    enum Event: Sendable {
        case window([String: Double], time: TimeInterval)
        case gap(time: TimeInterval)
    }

    static let windowSeconds = 3.0
    /// Audio handed to the analyzer per call.
    private static let chunkSeconds = 0.25

    private let dsp: DSPCore
    private let handler: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "com.tobiaspol.overtone.classifier", qos: .utility)

    // Everything below is confined to `queue`.
    private var timer: DispatchSourceTimer?
    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: Observer?
    private var format: AVAudioFormat?
    private var pending: [Float] = []
    private var position: AVAudioFramePosition = 0
    private var scratch = [Float](repeating: 0, count: Int(OT_ANALYZER_SIZE) / 2)
    private var gate = SilenceGate()
    private var sampleRate = 48_000.0
    /// Drain interval: 0.1 s, shorter at high sample rates so a drain never exceeds the
    /// half ring (8192 samples) `ot_dsp_drain_detector` returns per call.
    private var tick = 0.1

    init(dsp: DSPCore, handler: @escaping @Sendable (Event) -> Void) {
        self.dsp = dsp
        self.handler = handler
    }

    /// `speed` is how much faster than real time audio arrives (1 when listening live).
    func start(sampleRate: Double, speed: Double = 1) {
        queue.async { self.begin(sampleRate: sampleRate, speed: speed) }
    }

    func stop() {
        queue.async { self.end() }
    }

    private func begin(sampleRate rate: Double, speed: Double) {
        end()
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: Self.windowSeconds, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
            let analyzer = SNAudioStreamAnalyzer(format: format)
            let observer = Observer(handler: handler)
            try analyzer.add(request, withObserver: observer)
            (self.analyzer, self.observer, self.format, sampleRate) = (analyzer, observer, format, rate)
            tick = min(0.1, Double(OT_ANALYZER_SIZE) * 0.3 / (rate * max(speed, 1)))
        } catch {
            Log.detection.error("Sound classifier unavailable: \(error.localizedDescription, privacy: .public)")
            return
        }
        _ = dsp.drainDetector(into: &scratch) // drop anything left from an earlier run
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + tick, repeating: tick, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in self?.drain() }
        timer.resume()
        self.timer = timer
    }

    private func end() {
        timer?.cancel()
        timer = nil
        analyzer?.completeAnalysis()
        (analyzer, observer, format) = (nil, nil, nil)
        pending.removeAll()
        position = 0
        gate = SilenceGate()
    }

    private func drain() {
        var count = 0
        repeat {
            count = dsp.drainDetector(into: &scratch)
            consume(count)
        } while count == scratch.count // a late tick: keep going until the ring is empty
    }

    private func consume(_ count: Int) {
        let samples = scratch[0..<count]
        let rms = count > 0 ? sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(count)) : 0
        let duration = count > 0 ? Double(count) / sampleRate : tick
        if gate.feed(rms: rms, duration: duration) {
            handler(.gap(time: Double(position + AVAudioFramePosition(pending.count + count)) / sampleRate))
        }
        pending.append(contentsOf: samples)
        let chunk = Int(sampleRate * Self.chunkSeconds)
        while pending.count >= chunk {
            analyze(pending[0..<chunk])
            pending.removeFirst(chunk)
        }
    }

    /// Hands one chunk to the analyzer in a fresh buffer (the analyzer may keep a reference).
    private func analyze(_ samples: ArraySlice<Float>) {
        guard let analyzer, let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        analyzer.analyze(buffer, atAudioFramePosition: position)
        position += AVAudioFramePosition(samples.count)
    }

    private final class Observer: NSObject, SNResultsObserving {
        let handler: @Sendable (Event) -> Void

        init(handler: @escaping @Sendable (Event) -> Void) {
            self.handler = handler
        }

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            var scores: [String: Double] = [:]
            for item in result.classifications where SoundCategory.labels.contains(item.identifier) {
                scores[item.identifier] = item.confidence
            }
            handler(.window(scores, time: CMTimeRangeGetEnd(result.timeRange).seconds))
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            Log.detection.error("Sound classification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
