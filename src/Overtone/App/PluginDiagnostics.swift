import AppKit
import OvertoneDSP

/// Developer tool: `Overtone --check-plugins` loads every installed Audio Unit effect, renders a
/// test tone through Overtone's real plugin chain and prints the result (exit code 1 on failures).
/// Run it from a signed bundle to verify hosting under the hardened runtime.
@MainActor
enum PluginDiagnostics {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--check-plugins") else { return false }
        Task { await exit(run() ? 0 : 1) }
        return true
    }

    private static func run() async -> Bool {
        let dsp = DSPCore()
        dsp.prepare(sampleRate: 48_000)
        let host = PluginHost(dsp: dsp)
        host.scanComponents()
        var failures = 0
        for component in host.available {
            let outcome = await check(component, dsp: dsp)
            if outcome.hasPrefix("FAIL") { failures += 1 }
            print("\(outcome)  \(component.manufacturerName): \(component.name)")
        }
        print("\(host.available.count - failures)/\(host.available.count) plugins hosted successfully")
        return failures == 0
    }

    private static func check(_ component: PluginComponent, dsp: DSPCore) async -> String {
        let config = PluginSlotConfig(
            componentType: component.type, componentSubType: component.subType,
            manufacturer: component.manufacturer, name: component.name, manufacturerName: component.manufacturerName
        )
        do {
            let plugin = try await HostedPlugin.instantiate(config)
            try plugin.configure(sampleRate: 48_000, dsp: dsp)
            defer { plugin.uninitialize() }
            let peak = render(through: plugin, dsp: dsp)
            guard peak.isFinite else { return "FAIL non-finite output" }
            return String(format: "ok   peak %.3f", peak)
        } catch {
            return "FAIL \(error.localizedDescription)"
        }
    }

    /// Renders a 440 Hz tone through a chain holding only `plugin`. IO is not running here,
    /// so swapping and freeing chains immediately is safe.
    private static func render(through plugin: HostedPlugin, dsp: DSPCore) -> Float {
        guard let chain = ot_plugin_chain_create() else { return .nan }
        _ = ot_plugin_chain_append(chain, plugin.audioUnit, false)
        ot_plugin_chain_free(ot_dsp_swap_plugin_chain(dsp.handle, chain))
        var params = ot_params()
        ot_params_init(&params, 48_000)
        dsp.publish(params)
        let frames = 8_192
        var left = (0..<frames).map { 0.25 * Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
        var right = left
        ot_dsp_process(dsp.handle, &left, &right, UInt32(frames))
        ot_plugin_chain_free(ot_dsp_swap_plugin_chain(dsp.handle, nil))
        return (left + right).reduce(0) { $1.isFinite ? max($0, abs($1)) : .nan }
    }
}
