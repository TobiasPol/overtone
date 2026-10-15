import CoreAudio
import Foundation

/// A failed Core Audio call, carrying the OSStatus and what was being attempted.
struct AudioObjectError: LocalizedError {
    let status: OSStatus
    let operation: String

    var errorDescription: String? {
        "\(operation) failed (\(FourCC.string(UInt32(bitPattern: status))))"
    }
}

enum FourCC {
    /// Renders an OSStatus or selector as 'abcd' when printable, otherwise as a number.
    static func string(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return "\(Int32(bitPattern: value))" }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}

func checkAudio(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw AudioObjectError(status: status, operation: operation()) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// Reads a plain-old-data property, returning `fallback` when it is missing.
    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        default fallback: T
    ) -> T {
        var address = Self.address(selector, scope: scope, element: element)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : fallback
    }

    /// Reads a variable-length array property of plain-old-data elements.
    func readArray<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        of type: T.Type = T.self
    ) -> [T] {
        var address = Self.address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, raw) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        return Array(UnsafeBufferPointer(start: raw.bindMemory(to: T.self, capacity: count), count: count))
    }

    /// Reads a CFString property (Core Audio hands these out retained).
    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = Self.address(selector, scope: scope)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    func write<T>(
        _ selector: AudioObjectPropertySelector,
        _ value: T,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws {
        var address = Self.address(selector, scope: scope, element: element)
        var copy = value
        let status = withUnsafePointer(to: &copy) {
            AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        try checkAudio(status, "Setting \(FourCC.string(selector))")
    }

    func hasProperty(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = Self.address(selector, scope: scope, element: element)
        return AudioObjectHasProperty(self, &address)
    }

    func isSettable(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = Self.address(selector, scope: scope, element: element)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(self, &address),
              AudioObjectIsPropertySettable(self, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }
}

/// Keeps a Core Audio property listener registered for as long as it is retained.
final class AudioPropertyListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock

    init?(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        queue: DispatchQueue = .main,
        handler: @escaping () -> Void
    ) {
        self.object = object
        address = AudioObjectID.address(selector, scope: scope)
        self.queue = queue
        block = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
}
