import Foundation

/// "System Audio Recording" (TCC audio capture) permission.
///
/// There is no public API to query this permission, so we use the same TCC
/// SPI that Apple's own tools use, resolved at runtime. If it ever disappears
/// we fall back to simply starting and letting macOS prompt.
enum AudioCapturePermission {
    enum State { case authorized, denied, undetermined }

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let library = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let preflightFn: PreflightFn? = symbol("TCCAccessPreflight")
    private static let requestFn: RequestFn? = symbol("TCCAccessRequest")

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
    )!

    private static func symbol<T>(_ name: String) -> T? {
        guard let library, let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var state: State {
        guard let preflightFn else { return .undetermined }
        switch preflightFn(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .undetermined
        }
    }

    /// Shows the system prompt (once). Completion runs on the main queue.
    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard let requestFn else {
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(true) } }
            return
        }
        requestFn(service, nil) { granted in
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(granted) } }
        }
    }
}
