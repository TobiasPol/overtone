import Foundation
import Observation

/// The single source of truth for user-facing settings. Every mutation
/// notifies the controller, which pushes DSP parameters and schedules a save.
@MainActor @Observable
final class AppState {
    enum Change { case power, dsp, mixer, plugins, general, profiles, autoPreset }

    var isEnabled = true { didSet { notify(.power) } }
    var equalizer = EqualizerSettings() { didSet { notify(.dsp) } }
    var correction = HeadphoneCorrection() { didSet { notify(.dsp) } }
    var spatial = SpatialSettings() { didSet { notify(.dsp) } }
    var output = OutputSettings() { didSet { notify(.dsp) } }
    var mixer = MixerSettings() { didSet { notify(.mixer) } }
    var plugins: [PluginSlotConfig] = [] { didSet { notify(.plugins) } }
    var general = GeneralSettings() { didSet { notify(.general) } }
    var deviceProfiles: [String: DeviceProfile] = [:] { didSet { notify(.profiles) } }
    var autoPreset = AutoPresetSettings() { didSet { notify(.autoPreset) } }
    /// The user's own equalizer while auto mode has swapped a preset in. Saving and device
    /// profiles use this instead of `equalizer`, so auto choices never overwrite the user's EQ.
    var manualEqualizer: EqualizerSettings?

    @ObservationIgnored var onChange: ((Change) -> Void)?
    @ObservationIgnored private var isRestoring = false

    private func notify(_ change: Change) {
        guard !isRestoring else { return }
        onChange?(change)
    }

    var persisted: PersistedState {
        PersistedState(
            isEnabled: isEnabled, equalizer: manualEqualizer ?? equalizer, correction: correction, spatial: spatial,
            output: output, mixer: mixer, plugins: plugins, general: general, deviceProfiles: deviceProfiles,
            autoPreset: autoPreset
        )
    }

    /// Applies saved settings without triggering per-property change handling.
    func restore(_ state: PersistedState) {
        isRestoring = true
        defer { isRestoring = false }
        isEnabled = state.isEnabled
        equalizer = state.equalizer
        correction = state.correction
        spatial = state.spatial
        output = state.output
        mixer = state.mixer
        plugins = state.plugins
        general = state.general
        deviceProfiles = state.deviceProfiles
        autoPreset = state.autoPreset
        manualEqualizer = nil
    }

    /// Swaps in the equalizer/correction remembered for a device (or keeps the current ones).
    func loadProfile(for deviceUID: String) {
        guard general.rememberPerDevice, let profile = deviceProfiles[deviceUID] else { return }
        equalizer = profile.equalizer
        correction = profile.correction
    }

    func storeProfile(for deviceUID: String) {
        guard general.rememberPerDevice else { return }
        let profile = DeviceProfile(equalizer: manualEqualizer ?? equalizer, correction: correction)
        if deviceProfiles[deviceUID] != profile {
            deviceProfiles[deviceUID] = profile
        }
    }
}

/// On-disk settings. Each section decodes independently, so a damaged or
/// outdated section falls back to defaults without wiping the rest.
struct PersistedState: Codable {
    var isEnabled = true
    var equalizer = EqualizerSettings()
    var correction = HeadphoneCorrection()
    var spatial = SpatialSettings()
    var output = OutputSettings()
    var mixer = MixerSettings()
    var plugins: [PluginSlotConfig] = []
    var general = GeneralSettings()
    var deviceProfiles: [String: DeviceProfile] = [:]
    var autoPreset = AutoPresetSettings()

    init() {}

    init(
        isEnabled: Bool, equalizer: EqualizerSettings, correction: HeadphoneCorrection,
        spatial: SpatialSettings, output: OutputSettings, mixer: MixerSettings,
        plugins: [PluginSlotConfig], general: GeneralSettings, deviceProfiles: [String: DeviceProfile],
        autoPreset: AutoPresetSettings = AutoPresetSettings()
    ) {
        self.isEnabled = isEnabled
        self.equalizer = equalizer
        self.correction = correction
        self.spatial = spatial
        self.output = output
        self.mixer = mixer
        self.plugins = plugins
        self.general = general
        self.deviceProfiles = deviceProfiles
        self.autoPreset = autoPreset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        isEnabled = value(.isEnabled, true)
        equalizer = value(.equalizer, EqualizerSettings())
        correction = value(.correction, HeadphoneCorrection())
        spatial = value(.spatial, SpatialSettings())
        output = value(.output, OutputSettings())
        mixer = value(.mixer, MixerSettings())
        plugins = value(.plugins, [])
        general = value(.general, GeneralSettings())
        deviceProfiles = value(.deviceProfiles, [:])
        autoPreset = value(.autoPreset, AutoPresetSettings())
    }
}
