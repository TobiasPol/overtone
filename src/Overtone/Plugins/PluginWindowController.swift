import AppKit
import AudioToolbox
import AudioToolbox.AUCocoaUIView
import CoreAudioKit

/// Shows an Audio Unit's editor: its own view controller, its Cocoa view,
/// or Apple's generic parameter view as a last resort.
@MainActor
final class PluginWindowController {
    static let shared = PluginWindowController()
    private var windows: [UUID: NSWindow] = [:]

    func show(_ plugin: HostedPlugin) {
        if let window = windows[plugin.id] {
            present(window)
            return
        }
        plugin.unit.auAudioUnit.requestViewController { [weak self] controller in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.open(plugin, controller: controller) }
            }
        }
    }

    func close(_ id: UUID) {
        windows.removeValue(forKey: id)?.close()
    }

    private func open(_ plugin: HostedPlugin, controller: NSViewController?) {
        let content = controller?.view ?? Self.cocoaView(for: plugin.audioUnit) ?? Self.genericView(for: plugin.audioUnit)
        let size = content.frame.size.width > 10 ? content.frame.size : NSSize(width: 480, height: 320)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = "\(plugin.config.name) — \(plugin.config.manufacturerName)"
        window.isReleasedWhenClosed = false
        if let controller {
            window.contentViewController = controller
        } else {
            window.contentView = content
        }
        window.center()
        windows[plugin.id] = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Classic AUv2 custom view, loaded from the plugin's view bundle.
    private static func cocoaView(for unit: AudioUnit) -> NSView? {
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        guard AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &size, &writable)
            == noErr, size >= UInt32(MemoryLayout<AudioUnitCocoaViewInfo>.size) else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { raw.deallocate() }
        guard AudioUnitGetProperty(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, raw, &size)
            == noErr else { return nil }
        let info = raw.load(as: AudioUnitCocoaViewInfo.self)
        let bundleURL = info.mCocoaAUViewBundleLocation.takeRetainedValue() as URL
        let className = info.mCocoaAUViewClass.takeRetainedValue() as String
        guard let bundle = Bundle(url: bundleURL),
              let factoryClass = bundle.classNamed(className) as? NSObject.Type,
              let factory = factoryClass.init() as? AUCocoaUIBase else { return nil }
        return factory.uiView(forAudioUnit: unit, with: NSSize(width: 480, height: 320))
    }

    private static func genericView(for unit: AudioUnit) -> NSView {
        // Title | properties | parameters.
        let view = AUGenericView(audioUnit: unit, displayFlags: AUGenericViewDisplayFlags(rawValue: 0b111))
        view.frame = NSRect(x: 0, y: 0, width: 480, height: max(view.frame.height, 200))
        return view
    }
}
