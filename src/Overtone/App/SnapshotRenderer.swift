import AppKit
import CoreAudio
import SwiftUI

/// Developer tool: `Overtone --snapshot <folder>` renders every screen to PNG
/// (for README screenshots and visual checks) without starting audio capture.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return false }
        render(to: URL(fileURLWithPath: args[index + 1]))
        return true
    }

    private static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let controller = AppController()
        // A generic device keeps the user's own device names out of screenshots.
        let demo = AudioDevice(
            id: 0, uid: "demo", name: "MacBook Pro Speakers",
            transportType: kAudioDeviceTransportTypeBuiltIn, outputChannels: 2
        )
        controller.engine.showSnapshotState(device: demo, sampleRate: 48_000)
        controller.mixer.showSnapshotApps(demoApps)
        controller.analyzer.showSnapshotLevels(demoSpectrum, meter: 0.78)
        seedDemoState(controller.state)
        for section in AppSection.allCases {
            controller.state.general.selectedSection = section
            let modes: [EQMode?] = section == .equalizer ? EQMode.allCases : [nil]
            for mode in modes {
                if let mode { controller.state.equalizer.mode = mode }
                let name = ["popover", section.rawValue, mode?.rawValue].compactMap(\.self).joined(separator: "-")
                capture(popover(controller), to: folder.appendingPathComponent("\(name).png"))
            }
        }
        capture(AppEnvironment(controller: controller) { SettingsView() }, to: folder.appendingPathComponent("settings.png"))
        print("Snapshots written to \(folder.path)")
    }

    private static func popover(_ controller: AppController) -> some View {
        AppEnvironment(controller: controller) { MenuBarView() }
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private static let demoApps = [
        AudioApp(
            id: "com.apple.Music",
            name: "Music",
            bundleID: "com.apple.Music",
            pid: 0,
            processObjectIDs: [],
            isPlaying: true
        ),
        AudioApp(
            id: "com.apple.Safari",
            name: "Safari",
            bundleID: "com.apple.Safari",
            pid: 0,
            processObjectIDs: [],
            isPlaying: true
        ),
        AudioApp(
            id: "com.apple.FaceTime",
            name: "FaceTime",
            bundleID: "com.apple.FaceTime",
            pid: 0,
            processObjectIDs: [],
            isPlaying: false
        ),
    ]

    /// A smooth, music-like spectrum (bass-heavy, gently falling) for the analyzer.
    private static var demoSpectrum: [Float] {
        (0..<SpectrumAnalyzer.barCount).map { index in
            let x = Float(index) / Float(SpectrumAnalyzer.barCount)
            let bass = 0.18 * exp(-pow((x - 0.18) / 0.1, 2))
            return max(0.05, 0.62 - 0.3 * x + bass + 0.05 * sin(Float(index) * 1.9) + 0.03 * sin(Float(index) * 4.3))
        }
    }

    private static func seedDemoState(_ state: AppState) {
        state.mixer.apps = [
            "com.apple.Music": AppVolume(volume: 0.8, isMuted: false),
            "com.apple.FaceTime": AppVolume(volume: 1, isMuted: true),
        ]
        BuiltInPresets.advanced.first { $0.name == "Rock" }?.apply(to: &state.equalizer)
        state.equalizer.basic = BasicEQ(bass: 4, mid: -1.5, treble: 3)
        state.equalizer.expert = BuiltInPresets.expert.first { $0.name == "Vocal Presence" }?.expert ?? ExpertEQ()
        state.spatial.roomEnabled = true
        state.spatial.apply(.concertHall)
        state.correction = HeadphoneCorrection(
            isEnabled: true, profileName: "Sennheiser HD 650", source: "oratory1990", preamp: -6.1,
            filters: [
                EQBand(type: .lowShelf, frequency: 105, gain: 6.4, q: 0.7),
                EQBand(type: .peak, frequency: 8_800, gain: 5.1, q: 1.42),
            ]
        )
    }

    private static func capture(_ view: some View, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
