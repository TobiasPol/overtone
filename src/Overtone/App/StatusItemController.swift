import AppKit
import SwiftUI

/// The menu bar icon: left click opens the popover, right click shows a quick menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        super.init()
        let hosting = NSHostingController(rootView: AppEnvironment(controller: controller) { MenuBarView() })
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        controller.pinPopover = { [weak self] pinned in
            self?.popover.behavior = pinned ? .applicationDefined : .transient
        }
        configureButton()
        observeIcon()
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Overtone"
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let power = menu.addItem(
            withTitle: controller.state.isEnabled ? "Turn Overtone Off" : "Turn Overtone On",
            action: #selector(togglePower), keyEquivalent: ""
        )
        power.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Overtone", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePower() { controller.state.isEnabled.toggle() }
    @objc private func openSettings() { controller.openSettings() }
    @objc private func quit() { controller.quit() }

    /// Re-renders the icon whenever power or engine status changes.
    private func observeIcon() {
        withObservationTracking {
            updateIcon()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.observeIcon() } }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let enabled = controller.state.isEnabled
        let attention: Bool = switch controller.engine.status {
        case .failed, .permissionDenied: enabled
        default: false
        }
        button.image = StatusIcon.image(attention: attention)
        button.appearsDisabled = !enabled
    }

    func popoverDidShow(_ notification: Notification) {
        controller.setPopoverVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        controller.setPopoverVisible(false)
    }
}

/// Injects every observable model into a SwiftUI hierarchy.
struct AppEnvironment<Content: View>: View {
    let controller: AppController
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(controller)
            .environment(controller.state)
            .environment(controller.engine)
            .environment(controller.presets)
            .environment(controller.autoEQ)
            .environment(controller.mixer)
            .environment(controller.plugins)
            .environment(controller.analyzer)
            .tint(controller.state.general.accent.color)
    }
}

/// Settings live in a regular window, created on first use.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(_ controller: AppController) {
        if window == nil {
            let hosting = NSHostingController(rootView: AppEnvironment(controller: controller) { SettingsView() })
            let window = NSWindow(contentViewController: hosting)
            window.title = "Overtone Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
