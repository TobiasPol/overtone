import Foundation

/// Headphone correction loaded from AutoEQ (or an imported Equalizer APO file).
struct HeadphoneCorrection: Codable, Equatable, Sendable {
    var isEnabled = true
    var profileName: String?
    var source: String?
    var preamp = 0.0
    var filters: [EQBand] = []

    var isActive: Bool { isEnabled && !filters.isEmpty }
}

/// Named listening environments for the room simulation.
enum RoomPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case smallRoom, mediumRoom, largeRoom, studio, club, hall, concertHall, cathedral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smallRoom: return "Small Room"
        case .mediumRoom: return "Medium Room"
        case .largeRoom: return "Large Room"
        case .studio: return "Studio"
        case .club: return "Club"
        case .hall: return "Hall"
        case .concertHall: return "Concert Hall"
        case .cathedral: return "Cathedral"
        }
    }

    /// (size, damping, mix, pre-delay ms, width)
    var values: (size: Double, damping: Double, mix: Double, predelay: Double, width: Double) {
        switch self {
        case .smallRoom: return (0.30, 0.60, 0.18, 4, 0.8)
        case .mediumRoom: return (0.50, 0.50, 0.22, 10, 1.0)
        case .largeRoom: return (0.68, 0.45, 0.25, 18, 1.0)
        case .studio: return (0.40, 0.75, 0.12, 6, 0.9)
        case .club: return (0.60, 0.30, 0.30, 12, 1.0)
        case .hall: return (0.80, 0.40, 0.28, 25, 1.0)
        case .concertHall: return (0.88, 0.35, 0.32, 32, 1.0)
        case .cathedral: return (0.97, 0.20, 0.38, 45, 1.0)
        }
    }
}

struct SpatialSettings: Codable, Equatable, Sendable {
    var roomEnabled = false
    var room: RoomPreset? = .mediumRoom
    var roomSize = 0.5
    var damping = 0.5
    var mix = 0.22
    var predelayMs = 10.0
    var roomWidth = 1.0
    /// Stereo width: 0 = mono, 1 = original, 2 = extra wide.
    var width = 1.0
    var crossfeedEnabled = false
    var crossfeed = 0.5
    var crossfeedCutoff = 700.0

    mutating func apply(_ preset: RoomPreset) {
        let v = preset.values
        room = preset
        roomSize = v.size
        damping = v.damping
        mix = v.mix
        predelayMs = v.predelay
        roomWidth = v.width
    }
}

struct OutputSettings: Codable, Equatable, Sendable {
    /// Software volume, 1 = unity; values above 1 boost.
    var volume = 1.0
    var balance = 0.0
    var isMuted = false
    var maxBoost = 2.0
    var limiterEnabled = true
    var limiterCeilingDB = -0.3
    /// Route media volume keys to the software volume when the device has no hardware volume.
    var softwareVolumeKeys = true

    static let boostChoices: [Double] = [1.5, 2, 3, 4]
}
