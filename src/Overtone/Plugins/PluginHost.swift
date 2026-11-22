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
    @ObservationIgnored private var pendingRestore: [PluginSlotConfig] = []
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var retireTimers: [UUID: DispatchWorkItem] = [:]

    init(dsp: DSPCore) {
        self.dsp = dsp
    }

    var configs: [PluginSlotConfig] {
        plugins.forEach { $0.captureState() }
        return plugins.map(\.config) + unavailable + pendingRestore
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
        pendingRestore.append(contentsOf: configs)
        await drainPendingRestore()
    }

    func add(_ component: PluginComponent) async {
        guard plugins.count < Int(OT_MAX_PLUGINS) else {
            lastError = "The chain is full (\(OT_MAX_PLUGINS) plugins)."
            return
        }
        await insert(
            PluginSlotConfig(
                componentType: component.type, componentSubType: component.subType,
                manufacturer: component.manufacturer, name: component.name,
                manufacturerName: component.manufacturerName
            ),
            keepOnFailure: false
        )
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
        pendingRestore.append(contentsOf: pending)
        await drainPendingRestore()
        onChange?()
    }

    private func drainPendingRestore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        while let config = pendingRestore.first {
            await insert(config, keepOnFailure: true)
            if !pendingRestore.isEmpty { pendingRestore.removeFirst() }
        }
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

    func shutdown() {
        retireTimers.values.forEach { $0.cancel() }
        retireTimers.removeAll()
        PluginWindowController.shared.closeAll()
        let old = ot_dsp_swap_plugin_chain(dsp.handle, nil)
        let deadline = Date().addingTimeInterval(0.1)
        while ot_dsp_plugin_chain_in_use(dsp.handle, old), Date() < deadline {
            usleep(250)
        }
        if !ot_dsp_plugin_chain_in_use(dsp.handle, old) {
            ot_plugin_chain_free(old)
            plugins.forEach { $0.uninitialize() }
        }
        plugins.removeAll()
    }

    private func insert(_ config: PluginSlotConfig, keepOnFailure: Bool) async {
        do {
            let plugin = try await HostedPlugin.instantiate(config)
            guard plugins.count < Int(OT_MAX_PLUGINS) else {
                lastError = "The chain is full (\(OT_MAX_PLUGINS) plugins)."
                return
            }
            try plugin.configure(sampleRate: sampleRate, dsp: dsp)
            plugins.append(plugin)
            installChain()
        } catch {
            if keepOnFailure { unavailable.append(config) }
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

    /// Waits briefly for the IO thread to stop using `chain`, then polls asynchronously if needed
    /// so UI never stalls for long when an audio device hangs.
    private func retire(_ chain: UnsafeMutablePointer<ot_plugin_chain>?, releasing removed: [HostedPlugin]) {
        guard let chain else {
            removed.forEach { $0.uninitialize() }
            return
        }
        let syncDeadline = Date().addingTimeInterval(0.05)
        while ot_dsp_plugin_chain_in_use(dsp.handle, chain) {
            guard Date() < syncDeadline else {
                scheduleRetire(
                    address: UInt(bitPattern: chain), releasing: removed,
                    deadline: Date().addingTimeInterval(2.0)
                )
                return
            }
            usleep(250)
        }
        ot_plugin_chain_free(chain)
        removed.forEach { $0.uninitialize() }
    }

    private func scheduleRetire(address: UInt, releasing removed: [HostedPlugin], deadline: Date) {
        let id = UUID()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.retireTimers.removeValue(forKey: id)
                let chain = UnsafeMutablePointer<ot_plugin_chain>(bitPattern: address)
                if !ot_dsp_plugin_chain_in_use(self.dsp.handle, chain) {
                    ot_plugin_chain_free(chain)
                    removed.forEach { $0.uninitialize() }
                } else if Date() < deadline {
                    self.scheduleRetire(address: address, releasing: removed, deadline: deadline)
                } else {
                    self.graveyard += removed
                }
            }
        }
        retireTimers[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
    }
}
