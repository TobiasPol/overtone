import AVFoundation
import Observation
import OvertoneDSP

/// An installable Audio Unit effect found on this Mac.
struct PluginComponent: Identifiable, Hashable {
    let type: UInt32
    let subType: UInt32
    let manufacturer: UInt32
    let name: String
    let manufacturerName: String

    var id: String { "\(type)-\(subType)-\(manufacturer)" }
}

/// Manages the user's Audio Unit chain and hands it to the IO thread.
@MainActor @Observable
final class PluginHost {
    private(set) var available: [PluginComponent] = []
    private(set) var plugins: [HostedPlugin] = []
    /// Saved plugins that couldn't be loaded this session; kept so their settings aren't lost.
    private(set) var unavailable: [PluginSlotConfig] = []
    var lastError: String?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let dsp: DSPCore
    @ObservationIgnored private var sampleRate = 48_000.0
    /// Units whose chain couldn't be retired in time; never released, so the IO thread can't touch freed memory.
    @ObservationIgnored private var graveyard: [HostedPlugin] = []

    init(dsp: DSPCore) {
        self.dsp = dsp
    }

    var configs: [PluginSlotConfig] {
        plugins.forEach { $0.captureState() }
        return plugins.map(\.config) + unavailable
    }

    func scanComponents() {
        let types = [kAudioUnitType_Effect, kAudioUnitType_MusicEffect]
        available = types.flatMap { type in
            AVAudioUnitComponentManager.shared().components(matching: AudioComponentDescription(
                componentType: type, componentSubType: 0, componentManufacturer: 0,
                componentFlags: 0, componentFlagsMask: 0
            ))
        }.map {
            let d = $0.audioComponentDescription
            return PluginComponent(
                type: d.componentType, subType: d.componentSubType, manufacturer: d.componentManufacturer,
                name: $0.name, manufacturerName: $0.manufacturerName
            )
        }.sorted { ($0.manufacturerName, $0.name) < ($1.manufacturerName, $1.name) }
    }

    func restore(_ configs: [PluginSlotConfig]) async {
        for config in configs {
            await insert(config)
        }
    }

    func add(_ component: PluginComponent) async {
        guard plugins.count < Int(OT_MAX_PLUGINS) else {
            lastError = "The chain is full (\(OT_MAX_PLUGINS) plugins)."
            return
        }
        await insert(PluginSlotConfig(
            componentType: component.type, componentSubType: component.subType,
            manufacturer: component.manufacturer, name: component.name,
            manufacturerName: component.manufacturerName
        ))
        onChange?()
    }

    func remove(_ plugin: HostedPlugin) {
        PluginWindowController.shared.close(plugin.id)
        plugins.removeAll { $0.id == plugin.id }
        installChain(releasing: [plugin])
        onChange?()
    }

    func removeUnavailable(_ config: PluginSlotConfig) {
        unavailable.removeAll { $0.id == config.id }
        onChange?()
    }

    /// Tries to load previously unavailable plugins again (for example after installing an update).
    func retryUnavailable() async {
        let pending = unavailable
        unavailable = []
        for config in pending {
            await insert(config)
        }
        onChange?()
    }

    func move(_ plugin: HostedPlugin, by offset: Int) {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        let target = index + offset
        guard plugins.indices.contains(target) else { return }
        plugins.swapAt(index, target)
        installChain()
        onChange?()
    }

    func setBypassed(_ plugin: HostedPlugin, _ bypassed: Bool) {
        plugin.config.isBypassed = bypassed
        installChain()
        onChange?()
    }

    /// Called while IO is stopped, before a pipeline starts at `sampleRate`.
    func prepare(sampleRate: Double) {
        self.sampleRate = sampleRate
        retire(ot_dsp_swap_plugin_chain(dsp.handle, nil), releasing: [])
        for plugin in plugins {
            do {
                try plugin.configure(sampleRate: sampleRate, dsp: dsp)
            } catch {
                lastError = error.localizedDescription
            }
        }
        installChain()
    }

    func openEditor(_ plugin: HostedPlugin) {
        PluginWindowController.shared.show(plugin)
    }

    private func insert(_ config: PluginSlotConfig) async {
        do {
            let plugin = try await HostedPlugin.instantiate(config)
            try plugin.configure(sampleRate: sampleRate, dsp: dsp)
            plugins.append(plugin)
            installChain()
        } catch {
            unavailable.append(config)
            lastError = "Couldn't load \(config.name): \(error.localizedDescription)"
            Log.plugins.error("Loading \(config.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Publishes an immutable chain reflecting `plugins`, then retires the old one.
    private func installChain(releasing removed: [HostedPlugin] = []) {
        guard let chain = ot_plugin_chain_create() else { return }
        for plugin in plugins where plugin.isInitialized {
            _ = ot_plugin_chain_append(chain, plugin.audioUnit, plugin.config.isBypassed)
        }
        retire(ot_dsp_swap_plugin_chain(dsp.handle, chain), releasing: removed)
    }

    /// Waits for the IO thread to stop using `chain` before freeing it and
    /// uninitializing removed units. Waiting is bounded by one IO cycle in
    /// practice; if the thread is stuck we leak the chain rather than risk a crash.
    private func retire(_ chain: UnsafeMutablePointer<ot_plugin_chain>?, releasing removed: [HostedPlugin]) {
        let deadline = Date().addingTimeInterval(0.5)
        while ot_dsp_plugin_chain_in_use(dsp.handle, chain) {
            guard Date() < deadline else {
                graveyard += removed
                return
            }
            usleep(250)
        }
        ot_plugin_chain_free(chain)
        removed.forEach { $0.uninitialize() }
    }
}
