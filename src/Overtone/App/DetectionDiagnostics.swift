import AVFoundation
import OvertoneDSP

/// Developer tool: `Overtone --detect [--speed N] <audio file>...` plays the files back to back
/// (2 s of silence between them, like a playlist) through the real DSP core, detector feed,
/// background classifier, voting and switching logic, and prints every switch auto mode would make.
/// Runs at N× speed (default 4); the detector times everything in audio seconds, so results match
/// real time.
@MainActor
enum DetectionDiagnostics {
    private static let gapSeconds = 2.0

    static func runIfRequested() -> Bool {
        var args = Array(CommandLine.arguments.drop { $0 != "--detect" }.dropFirst())
        guard CommandLine.arguments.contains("--detect") else { return false }
        var speed = 4.0
        if let index = args.firstIndex(of: "--speed"), index + 1 < args.count {
            speed = max(1, Double(args[index + 1]) ?? speed)
            args.removeSubrange(index...index + 1)
        }
        let files = args.map { URL(fileURLWithPath: $0) }
        Task {
            await play(files, speed: speed)
            exit(0)
        }
        return true
    }

    private static func play(_ files: [URL], speed: Double) async {
        let rate = 48_000.0
        let dsp = DSPCore()
        dsp.prepare(sampleRate: rate)
        var params = ot_params()
        ot_params_init(&params, Float(rate))
        params.detector_enabled = 1
        dsp.publish(params)
        let detector = MusicTypeDetector(dsp: dsp)
        detector.useMusicApp = false
        let clock = PlaybackClock(sampleRate: rate, speed: speed)
        detector.onDetection = { print(String(format: "  %7.1f s  → %@ (%@)", clock.audioTime, $0.label, $0.detail)) }
        detector.start(sampleRate: rate, speed: speed)
        for url in files {
            guard let samples = load(url, sampleRate: rate) else {
                print("Cannot read \(url.path)")
                continue
            }
            print(String(format: "%7.1f s  ▶ %@", clock.audioTime, url.deletingPathExtension().lastPathComponent))
            await feed(samples, dsp: dsp, clock: clock)
            await feed([Float](repeating: 0, count: Int(rate * gapSeconds)), dsp: dsp, clock: clock)
        }
        print(String(format: "%7.1f s  ■ final: %@", clock.audioTime, detector.detection?.label ?? "no decision"))
        detector.stop()
    }

    /// Pushes mono audio through the DSP in 20 ms blocks, paced at `speed`× real time.
    private static func feed(_ mono: [Float], dsp: DSPCore, clock: PlaybackClock) async {
        let block = Int(clock.sampleRate * 0.02)
        var offset = 0
        while offset < mono.count {
            var left = Array(mono[offset..<min(offset + block, mono.count)])
            var right = left
            ot_dsp_process(dsp.handle, &left, &right, UInt32(left.count))
            offset += left.count
            clock.advance(left.count)
            let wait = clock.wallDeadline - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
    }

    /// Decodes a file to mono Float32 at `sampleRate`.
    private static func load(_ url: URL, sampleRate: Double) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let output = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let converter = AVAudioConverter(from: file.processingFormat, to: output),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil else { return nil }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * sampleRate / file.processingFormat.sampleRate) + 1_024
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        let source = OneShotInput(input)
        let status = converter.convert(to: buffer, error: nil) { _, outStatus in source.next(outStatus) }
        guard status != .error, let data = buffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }

    /// Hands the decoded file to the converter once, then reports the end of the stream. The SDK
    /// marks the input block `@Sendable`, but `convert(to:error:withInputFrom:)` calls it
    /// synchronously, so the unchecked conformance is safe.
    private final class OneShotInput: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            defer { buffer = nil }
            status.pointee = buffer == nil ? .endOfStream : .haveData
            return buffer
        }
    }

    private final class PlaybackClock {
        let sampleRate: Double
        let speed: Double
        private let started = ProcessInfo.processInfo.systemUptime
        private var frames = 0

        init(sampleRate: Double, speed: Double) {
            self.sampleRate = sampleRate
            self.speed = speed
        }

        var audioTime: Double { Double(frames) / sampleRate }
        var wallDeadline: TimeInterval { started + audioTime / speed }
        func advance(_ count: Int) { frames += count }
    }
}
