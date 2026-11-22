import AppKit
import Observation
import OvertoneDSP

/// Tracks which apps are producing audio and turns per-app volume settings
/// into dedicated process taps.
@MainActor @Observable
final class VolumeMixer {
    private(set) var apps: [AudioApp] = []
    @ObservationIgnored private var timer: Timer?
    /// Set by screenshot mode so live polling never replaces the demo apps.
    @ObservationIgnored private var isFrozen = false
    private static var iconCache: [String: NSImage] = [:]

    /// Screenshot support (`--snapshot`): shows fixed demo apps instead of live processes.
    func showSnapshotApps(_ demo: [AudioApp]) {
        apps = demo
        isFrozen = true
    }

    func refresh() {
        guard !isFrozen else { return }
        let latest = AudioProcessCatalog.apps()
        if latest != apps { apps = latest }
    }

    /// Polls play state while the mixer is on screen (process objects don't
    /// notify about every start/stop of playback).
    func setPolling(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Apps worth showing: anything playing now, plus anything with a custom setting that is running.
    func visibleApps(settings: MixerSettings) -> [AudioApp] {
        apps.filter { $0.isPlaying || settings.apps[$0.id] != nil }
    }

    static func tapRequests(settings: MixerSettings) -> [AppTapRequest] {
        guard !settings.apps.isEmpty else { return [] }
        return Array(
            AudioProcessCatalog.apps()
                .filter { settings.apps[$0.id] != nil }
                .map { AppTapRequest(key: $0.id, processes: $0.processObjectIDs.sorted()) }
                .sorted { $0.key < $1.key }
                .prefix(Int(OT_MAX_TAPS) - 1)
        )
    }

    nonisolated static func tapGains(settings: MixerSettings) -> [String: Double] {
        settings.apps.mapValues(\.gain)
    }

    static func icon(for app: AudioApp) -> NSImage {
        if let cached = iconCache[app.id] { return cached }
        let image: NSImage = if let running = NSRunningApplication(processIdentifier: app.pid), let icon = running.icon {
            icon
        } else if let bundleID = app.bundleID,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.icon(forFile: url.path)
        } else {
            NSWorkspace.shared.icon(for: .applicationBundle)
        }
        if iconCache.count > 100 { iconCache.removeAll() }
        iconCache[app.id] = image
        return image
    }
}
