import CoreAudio
import Foundation

/// A snapshot of an output-capable Core Audio device.
struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transportType: UInt32
    let outputChannels: Int

    enum Kind {
        case builtIn, headphones, bluetooth, usb, display, airPlay, thunderbolt, virtual, other
    }

    var kind: Kind {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return name.localizedCaseInsensitiveContains("headphone") ? .headphones : .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeThunderbolt: return .thunderbolt
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate: return .virtual
        default: return .other
        }
    }

    var symbolName: String {
        switch kind {
        case .builtIn: return "laptopcomputer"
        case .headphones: return "headphones"
        case .bluetooth: return "airpodsmax"
        case .usb: return "cable.connector"
        case .display: return "tv"
        case .airPlay: return "airplay.audio"
        case .thunderbolt: return "bolt.horizontal"
        case .virtual: return "waveform"
        case .other: return "hifispeaker"
        }
    }

    /// Whether the device exposes a hardware volume control the system volume keys can drive.
    var hasHardwareVolume: Bool {
        let scope = kAudioObjectPropertyScopeOutput
        if id.isSettable(kAudioDevicePropertyVolumeScalar, scope: scope, element: kAudioObjectPropertyElementMain) {
            return true
        }
        return id.isSettable(kAudioDevicePropertyVolumeScalar, scope: scope, element: 1)
    }

    static func make(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = id.readString(kAudioDevicePropertyDeviceUID) else { return nil }
        let channels = id.channelCount(scope: kAudioObjectPropertyScopeOutput)
        guard channels > 0 else { return nil }
        return AudioDevice(
            id: id,
            uid: uid,
            name: id.readString(kAudioObjectPropertyName) ?? "Unknown Device",
            transportType: id.read(kAudioDevicePropertyTransportType, default: UInt32(0)),
            outputChannels: channels
        )
    }

    /// All user-visible output devices, excluding Overtone's own private aggregates.
    static func outputDevices() -> [AudioDevice] {
        AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, of: AudioObjectID.self)
            .compactMap(make)
            .filter { !$0.uid.hasPrefix(AggregateDevice.uidPrefix) && !$0.name.hasPrefix("CADefaultDeviceAggregate") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func defaultOutputID() -> AudioObjectID {
        AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID.unknown)
    }

    static func defaultOutput() -> AudioDevice? {
        make(defaultOutputID())
    }

    static func setDefaultOutput(_ device: AudioDevice) throws {
        try AudioObjectID.system.write(kAudioHardwarePropertyDefaultOutputDevice, device.id)
    }
}

extension AudioObjectID {
    var nominalSampleRate: Double {
        read(kAudioDevicePropertyNominalSampleRate, default: Float64(0))
    }

    func channelCount(scope: AudioObjectPropertyScope) -> Int {
        bufferLayout(scope: scope).reduce(0, +)
    }

    /// Channels per stream buffer, in IO-proc buffer order.
    func bufferLayout(scope: AudioObjectPropertyScope) -> [Int] {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, raw) == noErr else { return [] }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }

    /// Zero-based output channel indices the user configured for stereo in Audio MIDI Setup.
    func preferredStereoChannels(channelCount: Int) -> (left: Int, right: Int) {
        guard channelCount > 1 else { return (0, 0) }
        let pair = readArray(
            kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioObjectPropertyScopeOutput,
            of: UInt32.self
        )
        guard pair.count == 2 else { return (0, 1) }
        let left = Int(pair[0]) - 1, right = Int(pair[1]) - 1
        let valid = (0..<channelCount).contains(left) && (0..<channelCount).contains(right)
        return valid ? (left, right) : (0, 1)
    }
}
