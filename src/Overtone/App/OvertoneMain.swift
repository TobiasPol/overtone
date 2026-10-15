import AppKit

@main
enum OvertoneMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SnapshotRenderer.runIfRequested() || ArtworkRenderer.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        if PluginDiagnostics.runIfRequested() { return }
        MainMenu.install()
        let controller = AppController()
        controller.start()
        statusItem = StatusItemController(controller: controller)
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.willTerminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPopover()
        return false
    }
}

/// Accessory apps have no visible menu bar, but key equivalents (copy, paste,
/// close window) are still dispatched through the main menu.
enum MainMenu {
    @MainActor
    static func install() {
        let main = NSMenu()
        main.addItem(submenu(title: "Overtone", items: [
            NSMenuItem(title: "Quit Overtone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        main.addItem(submenu(title: "Edit", items: [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        main.addItem(submenu(title: "Window", items: [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        NSApp.mainMenu = main
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }
}
