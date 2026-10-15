import CoreAudio
import Foundation

/// A private aggregate device that combines the real output device with
/// Overtone's process taps, giving one IO callback both input and output.
final class AggregateDevice {
    static let uidPrefix = "com.tobiaspol.overtone.aggregate"

    let id: AudioObjectID
    private var destroyed = false

    init(output: AudioDevice, taps: [ProcessTap]) throws {
        let tapList: [[String: Any]] = taps.map {
            [kAudioSubTapUIDKey: $0.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Overtone (\(output.name))",
            kAudioAggregateDeviceUIDKey: "\(Self.uidPrefix).\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
            kAudioAggregateDeviceTapListKey: tapList,
        ]
        var deviceID = AudioObjectID.unknown
        try checkAudio(
            AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID),
            "Creating aggregate device"
        )
        id = deviceID
    }

    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        AudioHardwareDestroyAggregateDevice(id)
    }

    deinit { destroy() }
}
