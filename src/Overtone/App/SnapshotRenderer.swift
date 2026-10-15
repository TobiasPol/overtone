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
        controller.engine.devices = [demo]
        controller.engine.outputDevice = demo
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

    private static func seedDemoState(_ state: AppState) {
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
