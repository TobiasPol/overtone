import AudioToolbox
import AVFoundation
import OvertoneDSP

/// One Audio Unit effect instance inserted into Overtone's processing chain.
@MainActor
final class HostedPlugin: Identifiable {
    let id: UUID
    let unit: AVAudioUnit
    var config: PluginSlotConfig
    private(set) var isInitialized = false

    static let maxFramesPerSlice: UInt32 = 4_096

    private init(unit: AVAudioUnit, config: PluginSlotConfig) {
        id = config.id
        self.unit = unit
        self.config = config
    }

    static func instantiate(_ config: PluginSlotConfig) async throws -> HostedPlugin {
        let description = AudioComponentDescription(
            componentType: config.componentType, componentSubType: config.componentSubType,
            componentManufacturer: config.manufacturer, componentFlags: 0, componentFlagsMask: 0
        )
        let unit = try await AVAudioUnit.instantiate(with: description, options: [])
        let plugin = HostedPlugin(unit: unit, config: config)
        plugin.restoreState()
        return plugin
    }

    var audioUnit: AudioUnit { unit.audioUnit }

    /// Configures stereo Float32 I/O at `sampleRate`, wires the input callback and initializes.
    /// Must only be called while the unit is not part of an installed chain.
    func configure(sampleRate: Double, dsp: DSPCore) throws {
        uninitialize()
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
            mBitsPerChannel: 32, mReserved: 0
        )
        try set(kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Input, &format)
        try set(kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Output, &format)
        var maxFrames = Self.maxFramesPerSlice
        try set(kAudioUnitProperty_MaximumFramesPerSlice, scope: kAudioUnitScope_Global, &maxFrames)
        var callback = ot_dsp_plugin_input_callback(dsp.handle)
        try set(kAudioUnitProperty_SetRenderCallback, scope: kAudioUnitScope_Input, &callback)
        try checkAudio(AudioUnitInitialize(audioUnit), "Initializing \(config.name)")
        isInitialized = true
    }

    func uninitialize() {
        guard isInitialized else { return }
        AudioUnitUninitialize(audioUnit)
        isInitialized = false
    }

    /// Captures the unit's full state (presets, parameter values) for persistence.
    func captureState() {
        guard let state = unit.auAudioUnit.fullState else { return }
        config.state = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    }

    private func restoreState() {
        guard let data = config.state,
              let state = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        unit.auAudioUnit.fullState = state
    }

    private func set<T>(_ property: AudioUnitPropertyID, scope: AudioUnitScope, _ value: inout T) throws {
        let status = withUnsafePointer(to: &value) {
            AudioUnitSetProperty(audioUnit, property, scope, 0, $0, UInt32(MemoryLayout<T>.size))
        }
        try checkAudio(status, "Configuring \(config.name)")
    }
}
