import AppKit
import CoreAudio
import Darwin

/// A Core Audio client process (anything that has opened the audio system).
struct AudioProcessInfo: Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
}

/// One user-facing application, possibly backed by several helper processes
/// (browsers render audio in helper processes, for example).
struct AudioApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String?
    let pid: pid_t
    var processObjectIDs: [AudioObjectID]
    var isPlaying: Bool
}

enum AudioProcessCatalog {
    static func processes() -> [AudioProcessInfo] {
        AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self).map {
            AudioProcessInfo(
                objectID: $0,
                pid: $0.read(kAudioProcessPropertyPID, default: pid_t(-1)),
                bundleID: $0.readString(kAudioProcessPropertyBundleID),
                isRunningOutput: $0.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0
            )
        }
    }

    /// Whether any app other than Overtone is currently playing audio.
    static func isAnyOtherProcessPlaying() -> Bool {
        let own = getpid()
        return AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)
            .contains {
                $0.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0
                    && $0.read(kAudioProcessPropertyPID, default: pid_t(-1)) != own
            }
    }

    /// Overtone's own process object, which must never be captured by its own tap.
    static func ownProcessObject() -> AudioObjectID {
        var pid = getpid()
        var address = AudioObjectID.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var object = AudioObjectID.unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            .system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        return status == noErr ? object : .unknown
    }

    /// Groups audio processes by the application responsible for them.
    static func apps() -> [AudioApp] {
        let ownPID = getpid()
        var byID: [String: AudioApp] = [:]
        for process in processes() where process.pid > 0 && process.pid != ownPID {
            let identity = AppIdentity.resolve(pid: process.pid, bundleID: process.bundleID)
            guard identity.pid != ownPID else { continue }
            var app = byID[identity.id] ?? AudioApp(
                id: identity.id, name: identity.name, bundleID: identity.bundleID,
                pid: identity.pid, processObjectIDs: [], isPlaying: false
            )
            app.processObjectIDs.append(process.objectID)
            app.isPlaying = app.isPlaying || process.isRunningOutput
            byID[identity.id] = app
        }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Maps a (possibly helper) process to the app the user thinks of as playing audio.
enum AppIdentity {
    struct Resolved {
        let id: String
        let name: String
        let bundleID: String?
        let pid: pid_t
    }

    private typealias ResponsibilityFn = @convention(c) (pid_t) -> pid_t

    /// Private libsystem SPI used by Activity Monitor to attribute XPC helpers to their app.
    private static let responsibleFn: ResponsibilityFn? = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibilityFn.self)
    }()

    static func resolve(pid: pid_t, bundleID: String?) -> Resolved {
        let responsible = responsibleFn.map { $0(pid) } ?? pid
        for candidate in [responsible, pid] where candidate > 0 {
            if let app = NSRunningApplication(processIdentifier: candidate), let id = app.bundleIdentifier {
                return Resolved(id: id, name: app.localizedName ?? id, bundleID: id, pid: candidate)
            }
        }
        if let bundleID {
            return Resolved(id: bundleID, name: prettyName(bundleID), bundleID: bundleID, pid: pid)
        }
        return Resolved(id: "pid:\(pid)", name: processName(pid) ?? "Process \(pid)", bundleID: nil, pid: pid)
    }

    private static func prettyName(_ bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
