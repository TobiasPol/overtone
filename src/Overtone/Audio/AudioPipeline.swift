import CoreAudio
import Foundation

/// Processes that should get their own tap so their volume can be set independently.
struct AppTapRequest: Equatable {
    let key: String
    let processes: [AudioObjectID]
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
        var created: [ProcessTap] = []
        do {
            try created.append(.global(excluding: Self.exclusions(own: ownProcess, appTaps: appTaps)))
            for request in appTaps {
                try created.append(.app(key: request.key, processes: request.processes))
            }
            aggregate = try AggregateDevice(output: output, taps: created)
        } catch {
            created.forEach { $0.destroy() }
            throw error
        }
        taps = created
        let rate = aggregate.id.nominalSampleRate
        sampleRate = rate > 0 ? rate : max(output.id.nominalSampleRate, 44_100)
        outputChannels = output.id.preferredStereoChannels(channelCount: output.outputChannels)
        let inputs = aggregate.id.bufferLayout(scope: kAudioObjectPropertyScopeInput)
        let outputs = aggregate.id.bufferLayout(scope: kAudioObjectPropertyScopeOutput)
        let (finalRate, keys, channels) = (sampleRate, tapKeys, outputChannels)
        Log.engine.info("""
        Pipeline for \(output.name, privacy: .public) @ \(finalRate) Hz; taps \(keys, privacy: .public); \
        aggregate in \(inputs, privacy: .public) out \(outputs, privacy: .public); stereo channels \(channels.left),\(channels.right)
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
