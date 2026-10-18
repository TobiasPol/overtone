import AppKit
import Observation
import OvertoneDSP

/// Wires settings, the audio engine and the feature models together.
@MainActor @Observable
final class AppController {
    @ObservationIgnored let state = AppState()
    @ObservationIgnored let engine = AudioEngine()
    @ObservationIgnored let presets = PresetStore()
    @ObservationIgnored let autoEQ = AutoEQCatalog()
    @ObservationIgnored let mixer = VolumeMixer()
    @ObservationIgnored let plugins: PluginHost
    @ObservationIgnored let analyzer: SpectrumAnalyzer
    @ObservationIgnored let autoPreset: AutoPresetController
    @ObservationIgnored private let store = SettingsStore()
    @ObservationIgnored private let volumeKeys = VolumeKeyInterceptor()
    @ObservationIgnored private let hud = VolumeHUD()
    @ObservationIgnored private var currentDeviceUID: String?
    @ObservationIgnored private var outputHasHardwareVolume = true
    @ObservationIgnored private var mixerKeys: Set<String> = []
    /// Lets views keep the popover open while a modal panel is showing.
    @ObservationIgnored var pinPopover: ((Bool) -> Void)?

    private(set) var isPopoverVisible = false

    init() {
        plugins = PluginHost(dsp: engine.dsp)
        analyzer = SpectrumAnalyzer(dsp: engine.dsp)
        autoPreset = AutoPresetController(state: state, dsp: engine.dsp)
    }

    func start() {
        if let saved = store.load() { state.restore(saved) }
        mixerKeys = Set(state.mixer.apps.keys)
        state.onChange = { [weak self] change in self?.handle(change) }
        wireEngine()
        engine.activate()
        plugins.onChange = { [weak self] in
            guard let self else { return }
            state.plugins = plugins.configs
        }
        let savedPlugins = state.plugins
        Task { await plugins.restore(savedPlugins) }
        volumeKeys.handler = { [weak self] key in self?.handleVolumeKey(key) }
        engine.setEnabled(state.isEnabled)
        autoPreset.update()
        updateVolumeKeyCapture()
    }

    /// Restores default settings (keeping loaded plugins) and pushes them to the engine.
    func resetAllSettings() {
        var defaults = PersistedState()
        defaults.plugins = state.plugins
        state.restore(defaults)
        mixerKeys = []
        engine.syncProcesses()
        engine.setEnabled(state.isEnabled)
        engine.publishParameters()
        autoPreset.update()
        updateAnalyzer()
        updateVolumeKeyCapture()
        store.save(state.persisted)
    }

    func willTerminate() {
        state.plugins = plugins.configs
        store.save(state.persisted)
        engine.setEnabled(false)
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        updateAnalyzer()
        engine.publishParameters()
        if !visible {
            mixer.setPolling(false)
            state.plugins = plugins.configs
        }
    }

    /// Runs `body` with the popover pinned open (for open/save panels).
    func withPinnedPopover<T>(_ body: () -> T) -> T {
        pinPopover?(true)
        defer { pinPopover?(false) }
        return body()
    }

    // MARK: - Change handling

    private func wireEngine() {
        engine.paramsProvider = { [weak self] context in
            self?.makeParams(context) ?? ParamsBuilder.make(DSPSettings(), context: context)
        }
        engine.appTapProvider = { [weak self] in
            guard let self else { return [] }
            return VolumeMixer.tapRequests(settings: state.mixer)
        }
        engine.willStart = { [weak self] rate in
            self?.plugins.prepare(sampleRate: rate)
            self?.analyzer.sampleRate = rate
            self?.autoPreset.sampleRate = rate
        }
        engine.outputDeviceChanged = { [weak self] device in self?.outputDeviceChanged(device) }
    }

    private func handle(_ change: AppState.Change) {
        switch change {
        case .power:
            engine.setEnabled(state.isEnabled)
            autoPreset.update()
            updateAnalyzer()
            updateVolumeKeyCapture()
        case .dsp:
            autoPreset.equalizerDidChange()
            engine.publishParameters()
            if let currentDeviceUID { state.storeProfile(for: currentDeviceUID) }
            updateVolumeKeyCapture()
        case .mixer:
            engine.publishParameters()
            let keys = Set(state.mixer.apps.keys)
            if keys != mixerKeys {
                mixerKeys = keys
                engine.syncProcesses()
            }
        case .general:
            updateAnalyzer()
            engine.publishParameters()
        case .autoPreset:
            autoPreset.update()
            engine.publishParameters()
        case .plugins, .profiles:
            break
        }
        store.scheduleSave { [weak self] in self?.state.persisted ?? PersistedState() }
    }

    private func makeParams(_ context: EngineContext) -> ot_params {
        let settings = DSPSettings(
            equalizer: state.equalizer, correction: state.correction, spatial: state.spatial,
            output: state.output, tapGains: VolumeMixer.tapGains(settings: state.mixer),
            analyzerEnabled: analyzerWanted, detectorEnabled: autoPreset.isActive
        )
        return ParamsBuilder.make(settings, context: context)
    }

    private var analyzerWanted: Bool {
        isPopoverVisible && state.general.showAnalyzer && state.isEnabled
    }

    private func updateAnalyzer() {
        analyzer.setRunning(analyzerWanted)
    }

    private func outputDeviceChanged(_ device: AudioDevice) {
        autoPreset.suspendForDeviceChange() // stores the user's own EQ with the old device
        currentDeviceUID = device.uid
        outputHasHardwareVolume = device.hasHardwareVolume
        state.loadProfile(for: device.uid)
        autoPreset.resumeAfterDeviceChange()
        updateVolumeKeyCapture()
    }

    // MARK: - Software volume keys

    private func updateVolumeKeyCapture() {
        let wanted = state.output.softwareVolumeKeys && state.isEnabled && !outputHasHardwareVolume
        if wanted {
            volumeKeys.start()
        } else {
            volumeKeys.stop()
        }
    }

    var volumeKeysNeedAccessibility: Bool {
        state.output.softwareVolumeKeys && !outputHasHardwareVolume && !VolumeKeyInterceptor.isTrusted
    }

    func requestAccessibility() {
        VolumeKeyInterceptor.requestTrust()
    }

    private func handleVolumeKey(_ key: VolumeKeyInterceptor.Key) {
        var output = state.output
        let step = 1.0 / 16
        switch key {
        case .up:
            output.volume = min(output.maxBoost, output.volume + step)
            output.isMuted = false
        case .down:
            output.volume = max(0, output.volume - step)
        case .mute:
            output.isMuted.toggle()
        }
        state.output = output
        hud.show(level: output.volume, maximum: output.maxBoost, muted: output.isMuted)
    }
}
