import AppKit
import ApplicationServices

/// Captures the keyboard volume keys so they can drive Overtone's software
/// volume on outputs without a hardware volume control (HDMI, DisplayPort…).
/// Requires Accessibility permission.
@MainActor
final class VolumeKeyInterceptor {
    enum Key { case up, down, mute }

    var handler: ((Key) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isActive: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard tap == nil, Self.isTrusted else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: volumeKeyCallback, userInfo: refcon
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Decodes an NX_SYSDEFINED aux-control event. Returns nil for anything that isn't a volume key.
    fileprivate static func decode(_ event: CGEvent) -> (key: Key, isDown: Bool)? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
        let code = (ns.data1 & 0xFFFF_0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        switch code {
        case 0: return (.up, isDown)
        case 1: return (.down, isDown)
        case 7: return (.mute, isDown)
        default: return nil
        }
    }
}

private func volumeKeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<VolumeKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            interceptor.reenable()
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let decoded = VolumeKeyInterceptor.decode(event) else {
            return Unmanaged.passUnretained(event)
        }
        if decoded.isDown { interceptor.handler?(decoded.key) }
        return nil // swallow both key-down and key-up so macOS doesn't show its own HUD
    }
}
