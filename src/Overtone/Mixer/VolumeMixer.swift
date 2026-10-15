import AppKit
import Observation

/// Tracks which apps are producing audio and turns per-app volume settings
/// into dedicated process taps.
@MainActor @Observable
final class VolumeMixer {
    private(set) var apps: [AudioApp] = []
    @ObservationIgnored private var timer: Timer?

    func refresh() {
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
        return AudioProcessCatalog.apps()
            .filter { settings.apps[$0.id] != nil }
            .map { AppTapRequest(key: $0.id, processes: $0.processObjectIDs.sorted()) }
            .sorted { $0.key < $1.key }
    }

    nonisolated static func tapGains(settings: MixerSettings) -> [String: Double] {
        settings.apps.mapValues(\.gain)
    }

    static func icon(for app: AudioApp) -> NSImage {
        if let running = NSRunningApplication(processIdentifier: app.pid), let icon = running.icon {
            return icon
        }
        if let bundleID = app.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
