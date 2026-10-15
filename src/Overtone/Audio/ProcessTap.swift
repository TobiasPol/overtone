import CoreAudio
import Foundation

/// Owns a Core Audio process tap. Tapped processes are muted while Overtone
/// reads the tap, and automatically unmuted if Overtone stops or crashes.
final class ProcessTap {
    let id: AudioObjectID
    let uuid: UUID
    let key: String
    private let description: CATapDescription
    private var destroyed = false

    static let globalKey = "__global__"

    /// Everything except the listed processes (Overtone itself plus apps with their own tap).
    static func global(excluding processes: [AudioObjectID]) throws -> ProcessTap {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: processes)
        description.name = "Overtone System Tap"
        return try ProcessTap(key: globalKey, description: description)
    }

    /// Only the listed processes, used for per-app volume.
    static func app(key: String, processes: [AudioObjectID]) throws -> ProcessTap {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "Overtone App Tap \(key)"
        return try ProcessTap(key: key, description: description)
    }

    private init(key: String, description: CATapDescription) throws {
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tapID = AudioObjectID.unknown
        try checkAudio(AudioHardwareCreateProcessTap(description, &tapID), "Creating process tap")
        id = tapID
        uuid = description.uuid
        self.key = key
        self.description = description
    }

    var processes: [AudioObjectID] { description.processes }

    /// Changes which processes the tap includes (or excludes) without rebuilding the device.
    func update(processes: [AudioObjectID]) throws {
        guard processes != description.processes else { return }
        description.processes = processes
        var address = AudioObjectID.address(kAudioTapPropertyDescription)
        var ref: UnsafeMutableRawPointer? = Unmanaged.passUnretained(description).toOpaque()
        let size = UInt32(MemoryLayout<UnsafeMutableRawPointer?>.size)
        try checkAudio(AudioObjectSetPropertyData(id, &address, 0, nil, size, &ref), "Updating tap")
    }

    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        AudioHardwareDestroyProcessTap(id)
    }

    deinit { destroy() }
}
