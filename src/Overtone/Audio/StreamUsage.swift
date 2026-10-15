import CoreAudio

/// Turns off input streams the IO proc doesn't need.
///
/// The aggregate device inherits the output device's own inputs (headset microphones,
/// interface inputs). Leaving them on would open the microphone, show the privacy
/// indicator and push Bluetooth headsets into their low-quality hands-free profile.
/// Taps are always the trailing input streams, so only those stay enabled.
enum StreamUsage {
    static func keepOnlyTrailingInputs(_ keep: Int, device: AudioObjectID, proc: AudioDeviceIOProcID) {
        let streams = device.readArray(
            kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput, of: AudioObjectID.self
        ).count
        guard streams > keep else { return }
        let countOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mNumberStreams) ?? 8
        let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 12
        let size = flagsOffset + streams * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment
        )
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        raw.storeBytes(of: unsafeBitCast(proc, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(streams), toByteOffset: countOffset, as: UInt32.self)
        let flags = (raw + flagsOffset).bindMemory(to: UInt32.self, capacity: streams)
        for index in 0..<streams {
            flags[index] = index >= streams - keep ? 1 : 0
        }
        var address = AudioObjectID.address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(size), raw)
        let disabled = streams - keep
        if status == noErr {
            Log.engine.info("Disabled \(disabled) device input stream(s) on the aggregate")
        } else {
            Log.engine
                .error("Could not disable device input streams: \(FourCC.string(UInt32(bitPattern: status)), privacy: .public)")
        }
    }
}
