import CoreAudio
import Foundation

/// Processes that should get their own tap so their volume can be set independently.
struct AppTapRequest: Equatable {
    let key: String
    let processes: [AudioObjectID]
}

/// Where the output's preferred stereo pair lives: the device stream to tap and the pair's
/// channel indices inside that stream (device-bound taps carry the whole stream).
struct TapSource: Equatable {
    var stream: Int
    var left: Int
    var right: Int

    static let firstPair = TapSource(stream: 0, left: 0, right: 1)

    /// `layout` is channels per output stream; `left`/`right` are flattened channel indices.
    static func locate(layout: [Int], left: Int, right: Int) -> TapSource {
        var base = 0
        for (index, count) in layout.enumerated() {
            let channels = base..<(base + count)
            if channels.contains(left) {
                // A pair split across streams can't be tapped as one; read the left side twice.
                let inStreamRight = channels.contains(right) ? right - base : left - base
                return TapSource(stream: index, left: left - base, right: inStreamRight)
            }
            base += count
        }
        return .firstPair
    }
}

/// One running capture → DSP → playback graph for a single output device.
///
/// Layout: tap 0 is the global tap (everything except Overtone and the
/// per-app taps), taps 1…n are per-app taps. The C IO proc mixes them using
/// the tap gains in the published parameters, in this same order.
final class AudioPipeline {
    let output: AudioDevice
    let sampleRate: Double
    let outputChannels: (left: Int, right: Int)
    let tapSource: TapSource
    private let taps: [ProcessTap]
    private let aggregate: AggregateDevice
    private let dsp: DSPCore
    private let ownProcess: AudioObjectID
    private var procID: AudioDeviceIOProcID?

    var tapKeys: [String] { taps.map(\.key) }

    init(output: AudioDevice, ownProcess: AudioObjectID, appTaps: [AppTapRequest], dsp: DSPCore) throws {
        self.output = output
        self.dsp = dsp
        self.ownProcess = ownProcess
        let channels = output.id.preferredStereoChannels(channelCount: output.outputChannels)
        let source = TapSource.locate(
            layout: output.id.bufferLayout(scope: kAudioObjectPropertyScopeOutput),
            left: channels.left, right: channels.right
        )
        var created: [ProcessTap] = []
        do {
            let exclusions = Self.exclusions(own: ownProcess, appTaps: appTaps)
            try created.append(.global(excluding: exclusions, deviceUID: output.uid, stream: source.stream))
            for request in appTaps {
                try created.append(
                    .app(key: request.key, processes: request.processes, deviceUID: output.uid, stream: source.stream)
                )
            }
            aggregate = try AggregateDevice(output: output, taps: created)
        } catch {
            created.forEach { $0.destroy() }
            throw error
        }
        taps = created
        let rate = aggregate.id.nominalSampleRate
        sampleRate = rate > 0 ? rate : max(output.id.nominalSampleRate, 44_100)
        outputChannels = channels
        tapSource = source
        let inputs = aggregate.id.bufferLayout(scope: kAudioObjectPropertyScopeInput)
        let outputs = aggregate.id.bufferLayout(scope: kAudioObjectPropertyScopeOutput)
        let (finalRate, keys) = (sampleRate, tapKeys)
        Log.engine.info("""
        Pipeline for \(output.name, privacy: .public) @ \(finalRate) Hz; taps \(keys, privacy: .public); \
        aggregate in \(inputs, privacy: .public) out \(outputs, privacy: .public); stereo channels \(channels.left),\(channels.right); \
        tap stream \(source.stream) channels \(source.left),\(source.right)
        """)
    }

    func start() throws {
        guard procID == nil else { return }
        var proc: AudioDeviceIOProcID?
        try checkAudio(
            AudioDeviceCreateIOProcID(aggregate.id, dsp.ioProc, dsp.clientData, &proc), "Creating IO proc"
        )
        procID = proc
        if let proc {
            StreamUsage.keepOnlyTrailingInputs(taps.count, device: aggregate.id, proc: proc)
        }
        try checkAudio(AudioDeviceStart(aggregate.id, proc), "Starting \(output.name)")
    }

    /// Full teardown; tapped processes return to playing directly. Safe to call repeatedly.
    func stop() {
        if let procID {
            AudioDeviceStop(aggregate.id, procID)
            AudioDeviceDestroyIOProcID(aggregate.id, procID)
            self.procID = nil
        }
        aggregate.destroy()
        taps.forEach { $0.destroy() }
    }

    /// Applies changed process lists in place. Returns false when the set of
    /// per-app taps changed, which requires a rebuild.
    func update(appTaps: [AppTapRequest]) -> Bool {
        guard appTaps.map(\.key) == Array(tapKeys.dropFirst()) else { return false }
        do {
            // Exclude from the global tap first: a moment of silence beats a moment of doubled audio.
            try taps[0].update(processes: Self.exclusions(own: ownProcess, appTaps: appTaps))
            for (tap, request) in zip(taps.dropFirst(), appTaps) {
                try tap.update(processes: request.processes)
            }
            return true
        } catch {
            return false
        }
    }

    private static func exclusions(own: AudioObjectID, appTaps: [AppTapRequest]) -> [AudioObjectID] {
        ([own] + appTaps.flatMap(\.processes)).filter { $0 != .unknown }
    }

    deinit { stop() }
}
