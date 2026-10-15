import AppKit
import SwiftUI

/// A small on-screen volume indicator for software volume changes.
@MainActor
final class VolumeHUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = VolumeHUDModel()

    func show(level: Double, maximum: Double, muted: Bool) {
        model.level = level
        model.maximum = maximum
        model.muted = muted
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel?.animator().alphaValue = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: VolumeHUDView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 120))
    }
}

@MainActor @Observable
final class VolumeHUDModel {
    var level = 1.0
    var maximum = 2.0
    var muted = false
}

private struct VolumeHUDView: View {
    let model: VolumeHUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24)
            ProgressView(value: model.muted ? 0 : min(model.level, model.maximum), total: model.maximum)
                .progressViewStyle(.linear)
            Text(model.muted ? "Muted" : "\(Int((model.level * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(width: 220, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
